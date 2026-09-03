@testable import AppBundle
import Common
import XCTest

@MainActor
final class SummonWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
        testParseSingleCommandSucc("summon-workspace foo", SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())))
    }

    func testParseDashDash() {
        testParseSingleCommandSucc(
            "summon-workspace -- foo",
            SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())),
        )
        testParseSingleCommandSucc(
            "summon-workspace --fail-if-noop -- foo",
            SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())).copy(\.failIfNoop, true),
        )
        assertEquals(parseCommand("summon-workspace --").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
        assertEquals(parseCommand("summon-workspace -- --fail-if-noop").errorOrNil, "ERROR: Workspace names starting with dash are disallowed")
    }

    // The swap itself needs a workspace visible on a second monitor, which unit tests cannot set up:
    // `monitorInfos` is hardcoded to a single monitor under test. These cover the single monitor
    // path, where there is no other monitor to swap with and nothing may be minted.

    func testSummonNotVisibleWorkspaceJustFocusesIt() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        let result = await parseCommand("summon-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(focus.workspace.name, "b")
    }

    /// On one monitor there is no monitor to hand anything to, so no stub workspace may appear
    func testSummonOnSingleMonitorMintsNothing() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        _ = await parseCommand("summon-workspace b").cmdOrDie.run(.defaultEnv, .emptyStdin)
        Workspace.garbageCollectUnusedWorkspaces()
        assertEquals(Workspace.all.map(\.name), ["b"])
    }

    func testSummonAlreadyVisibleReportsNoop() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        let result = await parseCommand("summon-workspace a").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, ["Workspace 'a' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code"])
        assertEquals(focus.workspace.name, "a")
    }

    func testSummonAlreadyVisibleFailIfNoopFails() async {
        assertTrue(Workspace.get(byName: "a").focusWorkspace())

        let result = await parseCommand("summon-workspace --fail-if-noop a").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(focus.workspace.name, "a")
    }
}
