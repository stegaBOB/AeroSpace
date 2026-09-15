@testable import AppBundle
import Common
import XCTest

@MainActor
final class WindowStripTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { resetTestMonitorInfos() }

    private let monitor = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 800)

    private func strip(_ edge: StripEdge, _ size: CGFloat, _ ordinal: Int = 1) -> WindowStrip {
        WindowStrip(edge: edge, size: size, ordinal: ordinal)
    }

    // MARK: - band geometry

    func testRightStripTakesTheRightBand() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.right, 200)])
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 800, topLeftY: 0, width: 200, height: 800)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 800)))
    }

    func testLeftStripTakesTheLeftBand() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.left, 200)])
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 800)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 200, topLeftY: 0, width: 800, height: 800)))
    }

    func testTopStripTakesTheTopBand() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.top, 100)])
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 100)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 0, topLeftY: 100, width: 1000, height: 700)))
    }

    func testBottomStripTakesTheBottomBand() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.bottom, 100)])
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 0, topLeftY: 700, width: 1000, height: 100)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 700)))
    }

    /// Strips nest from the outside in, so the second band spans only what the first left
    func testStripsNestInCreationOrder() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.right, 200, 1), strip(.top, 100, 2)])
        // The right strip was made first, so it keeps the full height
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 800, topLeftY: 0, width: 200, height: 800)))
        // The top strip only spans the remaining width
        assertTrue(bands[1].isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 800, height: 100)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 0, topLeftY: 100, width: 800, height: 700)))
    }

    func testReversingCreationOrderReversesNesting() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.top, 100, 1), strip(.right, 200, 2)])
        assertTrue(bands[0].isSameFrame(Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 100)))
        assertTrue(bands[1].isSameFrame(Rect(topLeftX: 800, topLeftY: 100, width: 200, height: 700)))
        assertTrue(rest.isSameFrame(Rect(topLeftX: 0, topLeftY: 100, width: 800, height: 700)))
    }

    /// Whatever the strips, what is left is one rectangle. That is what stops a band cutting the
    /// tiling area in two
    func testTilingAreaIsAlwaysOneRectangle() {
        let (_, rest) = reserveStripBands(monitor, [
            strip(.left, 120, 1), strip(.right, 130, 2), strip(.top, 60, 3), strip(.bottom, 70, 4),
        ])
        assertTrue(rest.isSameFrame(Rect(topLeftX: 120, topLeftY: 60, width: 750, height: 670)))
    }

    func testAStripCannotTakeTheWholeMonitor() {
        let (bands, rest) = reserveStripBands(monitor, [strip(.right, 5000)])
        assertEquals(bands[0].width, 999)
        assertEquals(rest.width, 1)
        assertTrue(rest.width > 0)
    }

    func testNoStripsLeavesTheMonitorWhole() {
        let (bands, rest) = reserveStripBands(monitor, [])
        assertEquals(bands.count, 0)
        assertTrue(rest.isSameFrame(monitor))
    }

    // MARK: - deriving the band from the window

    func testEdgeComesFromTheNearestMonitorEdge() {
        func edge(_ r: Rect) -> StripEdge { stripFromGeometry(window: r, monitor: monitor, ordinal: 1).edge }
        assertTrue(edge(Rect(topLeftX: 0, topLeftY: 300, width: 200, height: 200)) == .left)
        assertTrue(edge(Rect(topLeftX: 800, topLeftY: 300, width: 200, height: 200)) == .right)
        assertTrue(edge(Rect(topLeftX: 400, topLeftY: 0, width: 200, height: 150)) == .top)
        assertTrue(edge(Rect(topLeftX: 400, topLeftY: 650, width: 200, height: 150)) == .bottom)
    }

    func testSizeComesFromTheWindowAlongThatAxis() {
        let vertical = stripFromGeometry(
            window: Rect(topLeftX: 700, topLeftY: 100, width: 300, height: 600), monitor: monitor, ordinal: 1)
        assertTrue(vertical.edge == .right)
        assertEquals(vertical.size, 300)

        let horizontal = stripFromGeometry(
            window: Rect(topLeftX: 100, topLeftY: 0, width: 800, height: 120), monitor: monitor, ordinal: 1)
        assertTrue(horizontal.edge == .top)
        assertEquals(horizontal.size, 120)
    }

    // MARK: - the command

    func testParse() {
        assertNil(parseCommand("strip").errorOrNil)
        testParseSingleCommandSucc("strip on", StripCmdArgs(rawArgs: []).copy(\.toggle, .on))
        assertEquals(
            parseCommand("strip --fail-if-noop").errorOrNil,
            "--fail-if-noop requires 'on' or 'off' argument",
        )
    }

    func testCommandNeedsALaidOutWindow() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        let result = await parseCommand("strip on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertTrue(window.strip == nil)
    }

    func testCommandDerivesTheBandFromTheWindow() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        let full = mainMonitorInfo.visibleRectPaddedByOuterGaps
        window.lastAppliedLayoutPhysicalRect =
            Rect(topLeftX: full.maxX - 400, topLeftY: full.topLeftY, width: 400, height: full.height)

        let result = await parseCommand("strip on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertTrue(window.strip?.edge == .right)
        assertEquals(window.strip?.size, 400)

        let off = await parseCommand("strip off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(off.exitCode.rawValue, 0)
        assertTrue(window.strip == nil)
    }

    // MARK: - following the active workspace

    func testStripFollowsTheActiveWorkspace() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: a.stripWindowsContainer)
        window.strip = strip(.right, 300)

        assertTrue(b.focusWorkspace())
        migrateStrips()
        assertEquals(window.nodeWorkspace?.name, "b")
    }

    func testNonStripWindowStaysPut() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: a.rootTilingContainer)

        assertTrue(b.focusWorkspace())
        migrateStrips()
        assertEquals(window.nodeWorkspace?.name, "a")
    }

    func testMigrationDoesNotStealMostRecent() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let stripWindow = TestWindow.new(id: 1, parent: a.stripWindowsContainer)
        stripWindow.strip = strip(.right, 300)
        let resident = TestWindow.new(id: 2, parent: b.rootTilingContainer)
        assertEquals(resident.focusWindow(), true)

        assertTrue(b.focusWorkspace())
        migrateStrips()
        assertEquals(b.mostRecentWindowRecursive?.windowId, 2)
    }

    func testMigrationIsIdempotent() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: a.stripWindowsContainer)
        window.strip = strip(.right, 300)

        assertTrue(b.focusWorkspace())
        migrateStrips()
        migrateStrips()
        migrateStrips()
        assertEquals(b.stripWindowsContainer.allLeafWindowsRecursive.map(\.windowId), [1])
        assertTrue(b.rootTilingContainer.allLeafWindowsRecursive.isEmpty)
    }

    func testStripsAreOrderedByCreation() {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let second = TestWindow.new(id: 2, parent: workspace.stripWindowsContainer)
        second.strip = strip(.top, 100, 2)
        let first = TestWindow.new(id: 1, parent: workspace.stripWindowsContainer)
        first.strip = strip(.right, 200, 1)

        assertEquals(workspace.strips.map(\.windowId), [1, 2])
    }

    /// The reported bug: a strip must not be part of the tiling division, or an otherwise empty
    /// workspace stretches it across the whole monitor
    func testStripIsOutsideTheTilingTree() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        let full = mainMonitorInfo.visibleRectPaddedByOuterGaps
        window.lastAppliedLayoutPhysicalRect =
            Rect(topLeftX: full.maxX - 400, topLeftY: full.topLeftY, width: 400, height: full.height)

        _ = await parseCommand("strip on").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // It left the tiling tree, so nothing in the division can resize it
        assertTrue(workspace.rootTilingContainer.allLeafWindowsRecursive.isEmpty)
        assertEquals(workspace.strips.map(\.windowId), [1])
    }

    func testStripOffReturnsTheWindowToTiling() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        let full = mainMonitorInfo.visibleRectPaddedByOuterGaps
        window.lastAppliedLayoutPhysicalRect =
            Rect(topLeftX: full.maxX - 400, topLeftY: full.topLeftY, width: 400, height: full.height)

        _ = await parseCommand("strip on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        _ = await parseCommand("strip off").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertTrue(workspace.strips.isEmpty)
        assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1])
    }

    /// A strip owns its band, so the mouse must not move or resize it
    func testStripIsNotAMouseTarget() {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.stripWindowsContainer)
        window.strip = strip(.right, 300)
        switch window.windowParentCases {
            case .stripWindowsContainer: break
            default: XCTFail("A strip must live in the strip container")
        }
    }

    /// A strip is not floating either. It is a third thing
    func testStripIsNotFloating() {
        let workspace = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspace.stripWindowsContainer)
        window.strip = strip(.right, 300)
        assertTrue(!window.isFloating)
    }

    /// Dropping a dragged window can never land on a strip, because drag targets are resolved
    /// inside the tiling tree only
    func testDragTargetsCannotBeStrips() {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let stripWindow = TestWindow.new(id: 1, parent: workspace.stripWindowsContainer)
        stripWindow.strip = strip(.right, 300)
        let tiled = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        let inTree = workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId)
        assertEquals(inTree, [tiled.windowId])
        assertTrue(!inTree.contains(stripWindow.windowId))
    }

    func testStripStaysOnItsMonitor() {
        let left = newTestMonitorInfo(
            id: 1, name: "L", rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), isMain: true)
        let right = newTestMonitorInfo(
            id: 2, name: "R", rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080))
        testMonitorInfos = [left, right]

        let onLeft = Workspace.get(byName: "l1")
        assertTrue(left.setActiveWorkspace(onLeft))
        assertTrue(right.setActiveWorkspace(Workspace.get(byName: "r1")))
        let window = TestWindow.new(id: 1, parent: onLeft.stripWindowsContainer)
        window.strip = strip(.right, 300)
        assertTrue(onLeft.focusWorkspace())

        assertTrue(right.setActiveWorkspace(Workspace.get(byName: "r2")))
        migrateStrips()
        assertEquals(window.nodeWorkspace?.name, "l1")

        assertTrue(Workspace.get(byName: "l2").focusWorkspace())
        migrateStrips()
        assertEquals(window.nodeWorkspace?.name, "l2")
        assertEquals(window.nodeWorkspace?.workspaceMonitor.name, "L")
    }
}
