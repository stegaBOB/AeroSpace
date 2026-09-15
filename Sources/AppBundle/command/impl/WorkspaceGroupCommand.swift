import AppKit
import Common

struct WorkspaceGroupCommand: Command {
    let args: WorkspaceGroupCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let group = args.target.val.raw
        let members = WorkspaceGroup.members(of: group)

        // Validate the whole plan before applying any of it, so a pinned member cannot leave the
        // monitors half switched
        for (monitor, workspace) in members {
            if let forced = workspace.forceAssignedMonitor, forced.rect.topLeftCorner != monitor.rect.topLeftCorner {
                return .fail(io.err(
                    "Can't put workspace '\(workspace.name)' on monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it",
                ))
            }
        }

        if members.allSatisfy({ $0.monitor.activeWorkspace == $0.workspace }) {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Group '\(group)' is already active. Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }

        let focusedMonitorPoint = focus.workspace.workspaceMonitor.rect.topLeftCorner
        var toFocus: Workspace? = nil
        for (monitor, workspace) in members {
            check(monitor.setActiveWorkspace(workspace), "Validated plan was rejected for \(workspace.name)")
            if monitor.rect.topLeftCorner == focusedMonitorPoint { toFocus = workspace }
        }
        // Focus does not leave the monitor the user is already on
        return .from(bool: (toFocus ?? members.first?.workspace)?.focusWorkspace() == true)
    }
}
