import Common

struct StripCommand: Command {
    let args: StripCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }

        let wantStrip = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: window.strip == nil
        }
        if wantStrip == (window.strip != nil) {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Window '\(window.windowId)' is already \(wantStrip ? "a strip" : "not a strip"). Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }
        guard let workspace = window.nodeWorkspace else {
            return .fail(io.err("Window '\(window.windowId)' doesn't belong to any workspace"))
        }
        if !wantStrip {
            window.strip = nil
            // Back into the tiling division it was taken out of
            window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            return .succ
        }
        // The band comes from where the window already is, so there is nothing to configure
        guard let windowRect = window.lastAppliedLayoutPhysicalRect else {
            return .fail(io.err("Window '\(window.windowId)' has not been laid out yet, so its edge and size are unknown"))
        }
        window.strip = stripFromGeometry(
            window: windowRect,
            monitor: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps,
            ordinal: newStripOrdinal(),
        )
        // A strip is not part of the tiling division, so it leaves the tiling tree
        window.bind(to: workspace.stripWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        return .succ
    }
}
