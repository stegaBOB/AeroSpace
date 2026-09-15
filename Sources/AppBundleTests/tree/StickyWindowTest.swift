@testable import AppBundle
import Common
import XCTest

@MainActor
final class StickyWindowTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { resetTestMonitorInfos() }

    func testParse() {
        assertNil(parseCommand("sticky").errorOrNil)
        testParseSingleCommandSucc("sticky on", StickyCmdArgs(rawArgs: []).copy(\.toggle, .on))
        testParseSingleCommandSucc("sticky off", StickyCmdArgs(rawArgs: []).copy(\.toggle, .off))
        assertEquals(
            parseCommand("sticky --fail-if-noop").errorOrNil,
            "--fail-if-noop requires 'on' or 'off' argument",
        )
    }

    func testStickyCommandTogglesTheFlag() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        assertTrue(!window.isSticky)

        _ = await parseCommand("sticky").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertTrue(window.isSticky)
        _ = await parseCommand("sticky").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertTrue(!window.isSticky)
    }

    func testStickyOnIsANoopWhenAlreadySticky() async {
        let workspace = Workspace.get(byName: "a")
        assertTrue(workspace.focusWorkspace())
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)
        window.isSticky = true

        let result = await parseCommand("sticky --fail-if-noop on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertTrue(window.isSticky)
    }

    func testStickyWindowFollowsTheActiveWorkspace() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a.rootTilingContainer)
        sticky.isSticky = true

        assertTrue(b.focusWorkspace())
        migrateStickyWindows()
        assertEquals(sticky.nodeWorkspace?.name, "b")
        assertTrue(a.isEffectivelyEmpty)
    }

    func testNonStickyWindowStaysPut() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let normal = TestWindow.new(id: 1, parent: a.rootTilingContainer)

        assertTrue(b.focusWorkspace())
        migrateStickyWindows()
        assertEquals(normal.nodeWorkspace?.name, "a")
    }

    /// Migration must not steal most-recent, or the sticky window would take focus every switch and
    /// would become the anchor that binary-tree insertion splits
    func testMigrationDoesNotStealMostRecent() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a.rootTilingContainer)
        sticky.isSticky = true
        let resident = TestWindow.new(id: 2, parent: b.rootTilingContainer)
        assertEquals(resident.focusWindow(), true)

        assertTrue(b.focusWorkspace())
        migrateStickyWindows()
        assertEquals(b.mostRecentWindowRecursive?.windowId, 2)
    }

    func testMigrationIsIdempotent() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a.rootTilingContainer)
        sticky.isSticky = true

        assertTrue(b.focusWorkspace())
        migrateStickyWindows()
        migrateStickyWindows()
        migrateStickyWindows()
        assertEquals(b.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1])
    }

    /// layoutTiles writes each child's weight to its laid out length, so carrying that weight into
    /// the next workspace made the window arrive oversized and grow on every switch
    func testMigrationDoesNotCarryTheOldWidth() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a.rootTilingContainer)
        sticky.isSticky = true
        // What layout leaves behind when the window is alone on the monitor
        sticky.setWeight(a.rootTilingContainer.orientation, 1900)

        let resident = TestWindow.new(id: 2, parent: b.rootTilingContainer)
        resident.setWeight(b.rootTilingContainer.orientation, 500)

        assertTrue(b.focusWorkspace())
        migrateStickyWindows()

        assertEquals(sticky.nodeWorkspace?.name, "b")
        // It takes the size of a new window in its new home, not the 1900 it filled in the old one
        assertEquals(sticky.getWeight(b.rootTilingContainer.orientation), 500)
    }

    /// Repeated switching must not drift the width
    func testRepeatedSwitchingKeepsTheWidthStable() {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        assertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a.rootTilingContainer)
        sticky.isSticky = true
        let resident = TestWindow.new(id: 2, parent: b.rootTilingContainer)
        resident.setWeight(b.rootTilingContainer.orientation, 500)

        var widths: [CGFloat] = []
        for _ in 0 ..< 5 {
            assertTrue(b.focusWorkspace())
            migrateStickyWindows()
            widths.append(sticky.getWeight(b.rootTilingContainer.orientation))
            assertTrue(a.focusWorkspace())
            migrateStickyWindows()
        }
        assertEquals(widths, [500, 500, 500, 500, 500])
    }

    /// A sticky window stays on its own monitor. Switching the other monitor must not pull it over
    func testStickyWindowStaysOnItsMonitor() {
        let left = newTestMonitorInfo(
            id: 1, name: "L", rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), isMain: true,
        )
        let right = newTestMonitorInfo(
            id: 2, name: "R", rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        )
        testMonitorInfos = [left, right]

        let onLeft = Workspace.get(byName: "l1")
        let onRight = Workspace.get(byName: "r1")
        assertTrue(left.setActiveWorkspace(onLeft))
        assertTrue(right.setActiveWorkspace(onRight))
        let sticky = TestWindow.new(id: 1, parent: onLeft.rootTilingContainer)
        sticky.isSticky = true
        assertTrue(onLeft.focusWorkspace())

        // Change only the right monitor
        assertTrue(right.setActiveWorkspace(Workspace.get(byName: "r2")))
        migrateStickyWindows()
        assertEquals(sticky.nodeWorkspace?.name, "l1")

        // Now change the left one, which is the monitor it lives on
        assertTrue(Workspace.get(byName: "l2").focusWorkspace())
        migrateStickyWindows()
        assertEquals(sticky.nodeWorkspace?.name, "l2")
        assertEquals(sticky.nodeWorkspace?.workspaceMonitor.name, "L")
    }
}
