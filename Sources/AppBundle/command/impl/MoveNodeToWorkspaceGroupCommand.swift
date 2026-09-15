import AppKit
import Common

struct MoveNodeToWorkspaceGroupCommand: Command {
    let args: MoveNodeToWorkspaceGroupCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err("No window is focused"))
        }
        guard let workspace = WorkspaceGroup.largestMonitorMember(of: args.target.val.raw) else {
            return .fail(io.err("There are no monitors"))
        }
        return moveWindowToWorkspace(
            window,
            workspace,
            io,
            focusFollowsWindow: args.focusFollowsWindow,
            failIfNoop: args.failIfNoop,
            respectInsertionStrategy: true,
        )
    }
}
