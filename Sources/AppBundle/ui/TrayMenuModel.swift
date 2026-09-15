import AppKit
import Common

public final class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    @Published var experimentalUISettings: ExperimentalUISettings = ExperimentalUISettings()
    @Published var sponsorshipMessage: String = sponsorshipPrompts.randomElement().orDie()
    @Published var lastReloadConfigContainedWarnings: Bool = false
    @Published var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

@MainActor func updateTrayText() {
    let sortedMonitors = sortedMonitorInfos
    let focus = focus
    let modePrefix = activeMode?.takeIf { $0 != mainModeId }?.first.map { "(\($0.uppercased())) " } ?? ""

    // Several monitors showing members of one group are one thing to the user, so name it once
    let activeGroups = sortedMonitors.map { WorkspaceGroup.groupName(ofWorkspace: $0.activeWorkspace.name) }.toSet()
    let collapseToGroup = sortedMonitors.count > 1 && activeGroups.count == 1

    TrayMenuModel.shared.trayText = modePrefix + (
        collapseToGroup
            ? [trayLabel(sortedMonitors.map(\.activeWorkspace), focus: focus, starIfFocused: false)]
            : sortedMonitors.map { monitor in
                trayLabel([monitor.activeWorkspace], focus: focus, starIfFocused: sortedMonitors.count > 1)
            }
    ).joined(separator: " │ ")

    TrayMenuModel.shared.workspaces = trayWorkspaceViewModels(collapseToGroup: collapseToGroup, focus: focus)

    var items: [TrayItem] = collapseToGroup
        ? [trayItem(of: sortedMonitors.map(\.activeWorkspace), focus: focus)]
        : sortedMonitors.map { trayItem(of: [$0.activeWorkspace], focus: focus) }
    let mode = activeMode?.takeIf { $0 != mainModeId }?.first.map {
        TrayItem(type: .mode, name: $0.uppercased(), isActive: true, hasFullscreenWindows: false)
    }
    if let mode {
        items.insert(mode, at: 0)
    }
    TrayMenuModel.shared.trayItems = items
}

/// `workspaces` holds one entry per group when the monitors show one group each, and one entry per
/// workspace otherwise.
@MainActor
private func trayWorkspaceViewModels(collapseToGroup: Bool, focus: LiveFocus) -> [WorkspaceViewModel] {
    let grouped: [(name: String, members: [Workspace])] = collapseToGroup
        ? WorkspaceGroup.all.map { group in
            (group, Workspace.all.filter { WorkspaceGroup.groupName(ofWorkspace: $0.name) == group })
        }
        : Workspace.all.map { ($0.name, [$0]) }

    return grouped.map { (name, members) in
        let apps = members
            .flatMap { $0.allLeafWindowsRecursive }
            .map { $0.app.name?.takeIf { !$0.isEmpty } }
            .filterNotNil()
            .toSet()
        let dash = " - "
        let suffix = switch true {
            case !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case members.contains(where: \.isVisible):
                dash + (members.first { $0.isVisible }?.workspaceMonitor.name ?? "")
            default: ""
        }
        // The member named after the group carries the title, so renaming workspace 3 names group 3
        let titleSource = members.first { $0.name == name } ?? members.first
        return WorkspaceViewModel(
            name: name,
            title: titleSource?.titleWithName ?? name,
            suffix: suffix,
            isFocused: members.contains { focus.workspace == $0 },
            isEffectivelyEmpty: members.allSatisfy(\.isEffectivelyEmpty),
            isVisible: members.contains(where: \.isVisible),
            hasFullscreenWindows: members.contains { $0.allLeafWindowsRecursive.contains { $0.isFullscreen } },
        )
    }
}

@MainActor
private func trayLabel(_ workspaces: [Workspace], focus: LiveFocus, starIfFocused: Bool) -> String {
    let label = trayDisplayName(workspaces)
    let hasFullscreenWindows = workspaces.contains { $0.allLeafWindowsRecursive.contains { $0.isFullscreen } }
    let star = starIfFocused && workspaces.contains { $0 == focus.workspace } ? "*" : ""
    return star + (hasFullscreenWindows ? "[\(label)]" : label)
}

@MainActor
private func trayItem(of workspaces: [Workspace], focus: LiveFocus) -> TrayItem {
    TrayItem(
        type: .workspace,
        name: trayDisplayName(workspaces),
        isActive: workspaces.contains { $0 == focus.workspace },
        hasFullscreenWindows: workspaces.contains { $0.allLeafWindowsRecursive.contains { $0.isFullscreen } },
    )
}

@MainActor
private func trayDisplayName(_ workspaces: [Workspace]) -> String {
    guard let first = workspaces.first else { return "" }
    let group = WorkspaceGroup.groupName(ofWorkspace: first.name)
    // Prefer the member named after the group so a rename of it shows through
    return (workspaces.first { $0.name == group } ?? first).titleWithName
}

struct WorkspaceViewModel: Hashable {
    /// Addresses the workspace. Not shown on its own - see ``title``
    let name: String
    /// ``Workspace/titleWithName``, ready to display
    let title: String
    let suffix: String
    let isFocused: Bool
    let isEffectivelyEmpty: Bool
    let isVisible: Bool
    let hasFullscreenWindows: Bool
}

enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

private let validLetters = "A" ... "Z"

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    /// Display text: a workspace title or an uppercased mode
    let name: String
    let isActive: Bool
    let hasFullscreenWindows: Bool
    var systemImageName: String? {
        // System image type is only valid for numbers 0 to 50 and single capital char workspace name
        switch Int(name) {
            case let number?: if !(0 ... 50).contains(number) { return nil }
            case nil where name.count == 1: if !validLetters.contains(name) { return nil }
            default: return nil
        }
        let lowercasedName = name.lowercased()
        return switch type {
            case .mode: "\(lowercasedName).circle"
            case .workspace where isActive: "\(lowercasedName).square.fill"
            case .workspace: "\(lowercasedName).square"
        }
    }
    var id: String {
        return type.rawValue + name
    }
}
