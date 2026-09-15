@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceGroupTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws { resetTestMonitorInfos() }

    private func setUpMonitors(_ count: Int) -> [MonitorInfo] {
        let monitors = (0 ..< count).map { i in
            newTestMonitorInfo(
                id: i + 1, name: "M\(i + 1)",
                rect: Rect(topLeftX: CGFloat(i) * 1920, topLeftY: 0, width: 1920, height: 1080),
                isMain: i == 0,
            )
        }
        testMonitorInfos = monitors
        return monitors
    }

    func testMemberNames() {
        assertEquals(WorkspaceGroup.memberName(group: "3", slot: 0), "3")
        assertEquals(WorkspaceGroup.memberName(group: "3", slot: 1), "3:2")
        assertEquals(WorkspaceGroup.memberName(group: "3", slot: 2), "3:3")
    }

    func testGroupNameOfWorkspace() {
        assertEquals(WorkspaceGroup.groupName(ofWorkspace: "3"), "3")
        assertEquals(WorkspaceGroup.groupName(ofWorkspace: "3:2"), "3")
        assertEquals(WorkspaceGroup.groupName(ofWorkspace: "web"), "web")
        // A suffix that is not a number is part of the name
        assertEquals(WorkspaceGroup.groupName(ofWorkspace: "a:b"), "a:b")
        assertEquals(WorkspaceGroup.groupName(ofWorkspace: "a:"), "a:")
    }

    /// On one monitor a group and a workspace are the same thing
    func testSingleMonitorGroupIsTheWorkspace() {
        _ = setUpMonitors(1)
        let members = WorkspaceGroup.members(of: "3")
        assertEquals(members.count, 1)
        assertEquals(members.map(\.workspace.name), ["3"])
    }

    func testMembersFollowMonitorOrder() {
        _ = setUpMonitors(3)
        let members = WorkspaceGroup.members(of: "3")
        assertEquals(members.map(\.monitor.name), ["M1", "M2", "M3"])
        assertEquals(members.map(\.workspace.name), ["3", "3:2", "3:3"])
    }

    /// Slots follow position, so placing the big monitor on the right proves size wins over position
    func testLargestMonitorMember() {
        let small = newTestMonitorInfo(
            id: 1, name: "Small",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1280, height: 720), isMain: true,
        )
        let big = newTestMonitorInfo(
            id: 2, name: "Big",
            rect: Rect(topLeftX: 1280, topLeftY: 0, width: 3840, height: 2160),
        )
        testMonitorInfos = [small, big]
        assertEquals(WorkspaceGroup.members(of: "3").map(\.monitor.name), ["Small", "Big"])
        assertEquals(WorkspaceGroup.largestMonitorMember(of: "3")?.name, "3:2")
    }

    func testSwitchingAGroupChangesEveryMonitor() async {
        let monitors = setUpMonitors(2)
        assertTrue(Workspace.get(byName: "start").focusWorkspace())

        let result = await parseCommand("workspace-group 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(monitors[0].activeWorkspace.name, "3")
        assertEquals(monitors[1].activeWorkspace.name, "3:2")
    }

    /// Focus must not jump to another monitor just because the group changed
    func testSwitchingKeepsFocusOnTheSameMonitor() async {
        let monitors = setUpMonitors(2)
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "right")))
        assertTrue(Workspace.get(byName: "right").focusWorkspace())

        _ = await parseCommand("workspace-group 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        // Focus was on the second monitor, so it must land on that monitor's member
        assertEquals(focus.workspace.name, "3:2")
    }

    func testSwitchingToTheActiveGroupIsANoop() async {
        _ = setUpMonitors(2)
        _ = await parseCommand("workspace-group 3").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let result = await parseCommand("workspace-group 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Group '3' is already active. Tip: use --fail-if-noop to exit with non-zero code"])

        let failing = await parseCommand("workspace-group --fail-if-noop 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(failing.exitCode.rawValue, 2)
    }

    /// A pinned member must stop the switch before it changes anything
    func testForceAssignmentBlocksTheWholeSwitch() async {
        let monitors = setUpMonitors(2)
        config.workspaceToMonitorForceAssignment = ["3:2": [.main]]
        assertTrue(monitors[0].setActiveWorkspace(Workspace.get(byName: "before")))
        assertTrue(Workspace.get(byName: "before").focusWorkspace())

        let result = await parseCommand("workspace-group 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        // Nothing moved
        assertEquals(monitors[0].activeWorkspace.name, "before")
    }

    func testMoveNodeToWorkspaceGroupUsesTheLargestMonitor() async {
        let small = newTestMonitorInfo(
            id: 1, name: "Small",
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 1280, height: 720), isMain: true,
        )
        let big = newTestMonitorInfo(
            id: 2, name: "Big",
            rect: Rect(topLeftX: 1280, topLeftY: 0, width: 3840, height: 2160),
        )
        testMonitorInfos = [small, big]
        let start = Workspace.get(byName: "start")
        assertTrue(small.setActiveWorkspace(start))
        let window = TestWindow.new(id: 1, parent: start.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        let result = await parseCommand("move-node-to-workspace-group 7").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        // The window started on the small monitor and lands on the big one's member
        assertEquals(window.nodeWorkspace?.name, "7:2")
    }
}
