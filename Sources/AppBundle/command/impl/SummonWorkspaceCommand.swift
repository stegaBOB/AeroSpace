import AppKit
import Common

struct SummonWorkspaceCommand: Command {
    let args: SummonWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        let workspace = Workspace.get(byName: args.target.val.raw)
        let monitor = focus.workspace.workspaceMonitor
        if monitor.activeWorkspace == workspace {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Workspace '\(workspace.name)' is already visible on the focused monitor. Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }
        // Captured before the summon displaces it
        let displaced = monitor.activeWorkspace
        let prevMonitor = workspace.isVisible ? workspace.workspaceMonitor : nil
        if monitor.setActiveWorkspace(workspace) {
            if let prevMonitor {
                // Swap, the way Xmonad's greedyView does: the workspace this monitor gives up takes
                // the place of the summoned one, instead of leaving that monitor on a fresh stub
                // and this one assigned a workspace nobody can see.
                if !prevMonitor.setActiveWorkspace(displaced) {
                    // workspace-to-monitor-force-assignment pins the displaced workspace here
                    let stubWorkspace = getStubWorkspace(for: prevMonitor)
                    check(
                        prevMonitor.setActiveWorkspace(stubWorkspace),
                        "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(prevMonitor)",
                    )
                }
            }
            return .from(bool: workspace.focusWorkspace())
        } else {
            return .fail(io.err("Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it"))
        }
    }
}
