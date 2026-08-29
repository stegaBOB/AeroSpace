import AppKit
import Common

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let rawAppBundleId: String?
    let appId: KnownBundleId?
    let nsApp: NSRunningApplication
    private let axApp: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var windowsCount = 0
    var lastNativeFocusedWindowId: UInt32? = nil
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to integrate this global mutable state to https://github.com/nikitabobko/AeroSpace/issues/1215
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    @MainActor private static var wipPids: [pid_t: AwaitableOneTimeBroadcastLatch] = [:]

    private init(
        _ nsApp: NSRunningApplication,
        _ axApp: AXUIElement,
        _ axSubscriptions: [AxSubscription],
        _ thread: Thread,
    ) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.pid = nsApp.processIdentifier
        self.rawAppBundleId = nsApp.bundleIdentifier
        self.appId = nsApp.bundleIdentifier.flatMap { KnownBundleId.init(rawValue: $0) }
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        let pid = nsApp.processIdentifier
        // AX requests crash if you send them to yourself
        if pid == myPid { return nil }

        if let existing = allAppsMap[pid] { return existing }
        try checkCancellation()
        if let wip = wipPids[pid] {
            try await wip.await()
            return allAppsMap[pid]
        }
        let wip = AwaitableOneTimeBroadcastLatch()
        wipPids[pid] = wip

        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
                let handlers: HandlerToNotifKeyMapping = unsafe [
                    (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                ]
                let job = RunLoopJob(.cancellable)
                let subscriptions = (try? unsafe AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
                let isGood = !subscriptions.isEmpty
                let app = isGood ? MacApp(nsApp, axApp, subscriptions, Thread.current) : nil

                let appAxSubscriptionsThreadGuarded = app?.appAxSubscriptions
                let windowsThreadGuarded = app?.windows
                let axAppThreadGuarded = app?.axApp

                Task.startUnstructured { @MainActor in
                    allAppsMap[pid] = app
                    wipPids[pid] = nil
                    await wip.signalToAll()
                }
                if isGood {
                    CFRunLoopRun()

                    // Destroy AX objects in reverse order of their creation
                    appAxSubscriptionsThreadGuarded?.destroy()
                    windowsThreadGuarded?.destroy()
                    axAppThreadGuarded?.destroy()
                }
            }
        }
        thread.name = "AxAppThread \(nsApp.idForDebug)"
        thread.start()

        try await wip.await()
        return allAppsMap[pid]
    }

    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId, .cancellable) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            if AXUIElementPerformAction(closeButton.cast, kAXPressAction as CFString) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    func getAxSize(_ windowId: UInt32, _ cm: CancellationMode) async throws -> CGSize? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    // todo merge together with detectNewWindows
    func getFocusedWindow(_ cm: CancellationMode) async throws -> Window? {
        let windowId = try await thread?.runInLoop(cm) { [nsApp, axApp, windows] job in
            try axApp.threadGuarded.get(Ax.focusedWindowAttr)
                .flatMap { try windows.threadGuarded.getOrRegisterAxWindow(windowId: $0.windowId, $0.ax.cast, nsApp, job) }?
                .windowId
        }
        guard let windowId else { return nil }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        if serverArgs.isReadOnly { return }
        MacApp.focusJob?.cancel()
        // Performance optimization. If possible avoid doing AX requests
        // (important for apps which are slow at responding even such basic AX requests. E.g. Godot)
        // Beware of the macOS bug: https://github.com/nikitabobko/AeroSpace/issues/101
        if (!NSScreen.screensHaveSeparateSpaces || monitorInfos.count == 1) &&
            (lastNativeFocusedWindowId == windowId || windowsCount == 1)
        {
            nsApp.activate(options: .activateIgnoringOtherApps)
        } else {
            MacApp.focusJob = withWindowAsync(windowId, .cancellable) { [nsApp] window, job in
                // Raise firstly to make sure that by the time we activate the app, the window would be already on top
                window.set(Ax.isMainAttr, true)
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                nsApp.activate(options: .activateIgnoringOtherApps)
            }
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { [axApp] window, job in
            try disableAnimations(app: axApp.threadGuarded, job) {
                try setFrame(window, topLeft, size, job)
            }
        }
    }

    func setAxFrameForTermination(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        let semaphore = DispatchSemaphore(value: 0)
        let job = withWindowAsync(windowId, .nonCancellable) { [axApp] window, job in
            try? disableAnimations(app: axApp.threadGuarded, job) {
                try setFrame(window, topLeft, size, job)
            }
            semaphore.signal()
        }
        switch job.isCancelled {
            case true: return
            case false: semaphore.wait()
        }
    }

    func getAxWindowsCount(_ cm: CancellationMode) async throws -> Int? {
        try await thread?.runInLoop(cm) { [axApp] job in
            axApp.threadGuarded.get(Ax.windowsAttr)?.count
        }
    }

    func getAxRect(_ windowId: UInt32, _ cm: CancellationMode) async throws -> Rect? {
        try await withWindow(windowId, cm) { window, job in
            try AppBundle.getAxRect(window: window, job: job)
        }
    }

    func getAxRectForTermination(_ windowId: UInt32) -> Rect? {
        let future = CompletableFuture<Rect?>()
        let job = withWindowAsync(windowId, .nonCancellable) { window, job in
            future.complete(try AppBundle.getAxRect(window: window, job: job))
        }
        return switch job.isCancelled {
            case true: nil
            case false: future.blockingGet()
        }
    }

    func isWindowHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            window.isWindowHeuristic(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } == true
    }

    func getAxUiElementWindowType(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> AxUiElementWindowType {
        return try await withWindow(windowId, cm) { [nsApp, axApp, appId] window, job in
            window.getWindowType(axApp: axApp.threadGuarded, appId, nsApp.activationPolicy, windowLevel)
        } ?? .window
    }

    func isDialogHeuristic(_ windowId: UInt32, _ windowLevel: MacOsWindowLevel?, _ cm: CancellationMode) async throws -> Bool {
        try await withWindow(windowId, cm) { [appId] window, job in
            window.isDialogHeuristic(appId, windowLevel)
        } == true
    }

    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId, .cancellable) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    func dumpWindowAxInfo(windowId: UInt32, _ cm: CancellationMode) async throws -> [String: Json] {
        try await withWindow(windowId, cm) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    func dumpAppAxInfo(_ cm: CancellationMode) async throws -> [String: Json] {
        try await thread?.runInLoop(cm) { [axApp] job in
            dumpAxRecursive(axApp.threadGuarded, .app)
        } ?? [:]
    }

    func getAxTitle(_ windowId: UInt32, _ cm: CancellationMode) async throws -> String? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    func isMacosNativeFullscreen(_ windowId: UInt32, _ cm: CancellationMode) async throws -> Bool? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    func isMacosNativeMinimized(_ windowId: UInt32, _ cm: CancellationMode) async throws -> Bool? {
        try await withWindow(windowId, cm) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                await app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    guard let app = try await MacApp.getOrRegister(nsApp) else { return (nsApp.processIdentifier, []) }
                    return (nsApp.processIdentifier, try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId))
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [UInt32]] = [:]
            for try await (pid, windowIds) in group {
                if let app = MacApp.allAppsMap[pid] {
                    result[app] = windowIds
                }
            }
            return result
        }
    }

    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [UInt32] {
        if nsApp.isTerminated {
            await destroy()
            return []
        }
        guard let thread else { return [] }
        let (alive, dead) = try await thread.runInLoop(.cancellable) { [nsApp, windows, axApp] (job) -> ([UInt32], [UInt32]) in
            var alive: [UInt32: AxWindow] = windows.threadGuarded
            var dead = [UInt32: AxWindow]()
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                (alive, dead) = try alive.partition {
                    try job.checkCancellation()
                    return $0.value.ax.containingWindowId() != nil
                }
            }

            var axWindowIds = Set<UInt32>()
            for (id, window) in axApp.threadGuarded.get(Ax.windowsAttr) ?? [] {
                try job.checkCancellation()
                axWindowIds.insert(id)
                try alive.getOrRegisterAxWindow(windowId: id, window, nsApp, job)
            }

            for (id, window) in try alive.extractBackgroundNativeTabs(axWindowIds, job) {
                dead[id] = window
            }

            windows.threadGuarded = alive
            return (Array(alive.keys), Array(dead.keys))
        }
        windowsCount = alive.count
        for windowId in dead {
            setFrameJobs.removeValue(forKey: windowId)?.cancel()
        }
        return alive
    }

    private func destroy() async {
        _ = await Task.startUnstructured { @MainActor [pid] in _ = MacApp.allAppsMap.removeValue(forKey: pid) }.result
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        thread?.runInLoopAsync(job: RunLoopJob(.nonCancellable)) { job in CFRunLoopStop(CFRunLoopGetCurrent()) }
        thread = nil // Disallow all future job submissions
    }

    private func withWindow<T>(
        _ windowId: UInt32,
        _ cm: CancellationMode,
        _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?,
    ) async throws -> T? {
        try await thread?.runInLoop(cm) { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ cm: CancellationMode, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> ()) -> RunLoopJob {
        thread?.runInLoopAsync(job: RunLoopJob(cm)) { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            try? body(window.ax, job)
        } ?? .cancelled
    }
}

private final class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    // periphery:ignore
    private let axSubscriptions: [AxSubscription] // keep subscriptions in memory

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscriptions: [AxSubscription]) {
        self.windowId = windowId
        self.ax = ax
        assert(!axSubscriptions.isEmpty)
        self.axSubscriptions = axSubscriptions
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        let handlers: HandlerToNotifKeyMapping = unsafe [
            (refreshObs, [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification]),
            (movedObs, [kAXMovedNotification]),
            (resizedObs, [kAXResizedNotification]),
        ]
        let subscriptions = try unsafe AxSubscription.bulkSubscribe(nsApp, ax, job, handlers)
        return !subscriptions.isEmpty ? AxWindow(windowId: windowId, ax, subscriptions) : nil
    }
}

extension [UInt32: AxWindow] {
    @discardableResult
    fileprivate mutating func getOrRegisterAxWindow(windowId id: UInt32, _ axWindow: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/nikitabobko/AeroSpace/issues/1001
        if isLeftMouseButtonDown { return nil }

        if let window = try AxWindow.new(windowId: id, axWindow, nsApp, job) {
            self[id] = window
            return window
        } else {
            return nil
        }
    }

    /// Removes and returns the windows that back unselected native macOS tabs.
    ///
    /// Apps with native tabs (Finder, Terminal, Ghostty) keep one window per tab. Only the selected
    /// tab stays in `kAXWindowsAttribute`, but every tab keeps a live CGWindow, so
    /// ``AXUIElement/containingWindowId()`` still answers for the unselected ones and they linger as
    /// windows that cannot be focused or seen. https://github.com/nikitabobko/AeroSpace/issues/345
    ///
    /// Absence from `axWindowIds` alone is not enough to identify them: windows on inactive macOS
    /// Spaces are absent too. A tab is recognized by the tab bar of the selected window it hides
    /// behind - same exact frame, and no more of them than that tab bar has tabs.
    fileprivate mutating func extractBackgroundNativeTabs(_ axWindowIds: Set<UInt32>, _ job: RunLoopJob) throws -> [UInt32: AxWindow] {
        // AX requests are expensive, so pay for them only once something is actually absent
        if allSatisfy({ axWindowIds.contains($0.key) }) { return [:] }

        var frames = [UInt32: Rect]()
        for (id, window) in self {
            try job.checkCancellation()
            frames[id] = try getAxRect(window: window.ax, job: job)
        }

        // Only a window that something hides behind can be a tab bar worth reading
        let absentFrames = frames.filter { !axWindowIds.contains($0.key) }.values
        var tabCounts = [UInt32: Int]()
        for (id, frame) in frames where axWindowIds.contains(id) && absentFrames.contains(where: { $0.isSameFrame(frame) }) {
            try job.checkCancellation()
            tabCounts[id] = try self[id].map { try nativeTabCount(window: $0.ax, job: job) } ?? 0
        }

        var tabs = [UInt32: AxWindow]()
        for id in backgroundNativeTabIds(frames: frames, axWindowIds: axWindowIds, tabCounts: tabCounts) {
            tabs[id] = removeValue(forKey: id)
        }
        return tabs
    }
}

/// The number of native tabs `window` shows in its tab bar. 0 when it has none.
private func nativeTabCount(window: AXUIElement, job: RunLoopJob) throws -> Int {
    for child in window.get(Ax.childrenAttr) ?? [] {
        try job.checkCancellation()
        if child.get(Ax.roleAttr) == kAXTabGroupRole {
            return child.get(Ax.tabsAttr)?.count ?? 0
        }
    }
    return 0
}

/// The ids in `frames` that are absent from `axWindowIds` and hide behind a window that is present.
/// See `extractBackgroundNativeTabs` for why that identifies an unselected native tab.
///
/// `tabCounts` maps a present window to the number of tabs in its tab bar. A window without a tab
/// bar hides nothing, and a tab bar of n tabs accounts for exactly n - 1 hidden windows, so anything
/// beyond that is left alone rather than guessed at.
func backgroundNativeTabIds(frames: [UInt32: Rect], axWindowIds: Set<UInt32>, tabCounts: [UInt32: Int]) -> Set<UInt32> {
    var tabs = Set<UInt32>()
    for (id, frame) in frames where axWindowIds.contains(id) {
        let hidden = (tabCounts[id] ?? 0) - 1
        if hidden <= 0 { continue }
        let candidates = frames
            .filter { !axWindowIds.contains($0.key) && !tabs.contains($0.key) && $0.value.isSameFrame(frame) }
            .keys
            .sorted() // Any of them is equally a tab. Sort only to keep the choice reproducible
        tabs.formUnion(candidates.prefix(hidden))
    }
    return tabs
}

private func getAxRect(window: AXUIElement, job: RunLoopJob) throws -> Rect? {
    guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
    try job.checkCancellation()
    guard let size = window.get(Ax.sizeAttr) else { return nil }
    return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
}

private func setFrame(_ window: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    // Set size and then the position. The order is important https://github.com/nikitabobko/AeroSpace/issues/143
    //                                                        https://github.com/nikitabobko/AeroSpace/issues/335
    if let size { window.set(Ax.sizeAttr, size) }
    try job.checkCancellation()
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    try job.checkCancellation()
    if let size { window.set(Ax.sizeAttr, size) }
}

// Some undocumented magic
// References: https://github.com/koekeishiya/yabai/commit/3fe4c77b001e1a4f613c26f01ea68c0f09327f3a
//             https://github.com/rxhanson/Rectangle/pull/285
private func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
