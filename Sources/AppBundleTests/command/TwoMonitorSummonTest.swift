@testable import AppBundle
import Common
import XCTest

@MainActor
final class TwoMonitorSummonTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { resetTestMonitorInfos() }

    /// Two monitors side by side. `left` is main.
    private func setUpTwoMonitors() -> (left: MonitorInfo, right: MonitorInfo) {
        let left = newTestMonitorInfo(
            id: 1, name: "Left",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), isMain: true,
        )
        let right = newTestMonitorInfo(
            id: 2, name: "Right",
            rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        )
        testMonitorInfos = [left, right]
        return (left, right)
    }

    func testTwoMonitorsAreVisibleToTheApp() {
        let (left, right) = setUpTwoMonitors()
        assertEquals(monitorInfos.count, 2)
        assertEquals(sortedMonitorInfos.map(\.name), ["Left", "Right"])
        assertEquals(mainMonitorInfo.name, "Left")
        assertTrue(left.rect.topLeftX < right.rect.topLeftX)
    }

    func testSummonSwapsTheTwoWorkspaces() async {
        let (left, right) = setUpTwoMonitors()
        let here = Workspace.get(byName: "here")
        let there = Workspace.get(byName: "there")
        assertTrue(left.setActiveWorkspace(here))
        assertTrue(right.setActiveWorkspace(there))
        assertTrue(here.focusWorkspace())

        let result = await parseCommand("summon-workspace there").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)

        // The summoned workspace comes to the focused monitor
        assertEquals(left.activeWorkspace.name, "there")
        assertEquals(focus.workspace.name, "there")
        // and the one it displaced takes its place, rather than a fresh stub
        assertEquals(right.activeWorkspace.name, "here")
    }

    /// The swap must respect workspace-to-monitor-force-assignment. When the displaced workspace is
    /// pinned to the focused monitor it cannot move, so the vacated monitor falls back to a stub.
    func testForceAssignedWorkspaceIsNotSwappedAway() async {
        let (left, right) = setUpTwoMonitors()
        config.workspaceToMonitorForceAssignment = ["here": [.main]]
        let here = Workspace.get(byName: "here")
        let there = Workspace.get(byName: "there")
        assertTrue(left.setActiveWorkspace(here))
        assertTrue(right.setActiveWorkspace(there))
        assertTrue(here.focusWorkspace())

        let result = await parseCommand("summon-workspace there").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)

        assertEquals(left.activeWorkspace.name, "there")
        // 'here' is pinned to the main monitor, so it must not end up on the right one
        assertTrue(right.activeWorkspace.name != "here")
    }

    func testSummonMintsNoStubWorkspace() async {
        let (left, right) = setUpTwoMonitors()
        assertTrue(left.setActiveWorkspace(Workspace.get(byName: "here")))
        assertTrue(right.setActiveWorkspace(Workspace.get(byName: "there")))
        assertTrue(Workspace.get(byName: "here").focusWorkspace())

        _ = await parseCommand("summon-workspace there").cmdOrDie.run(.defaultEnv, .emptyStdin)
        Workspace.garbageCollectUnusedWorkspaces()
        assertEquals(Workspace.all.map(\.name).sorted(), ["here", "there"])
    }
}
