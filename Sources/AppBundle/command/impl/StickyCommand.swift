import Common

struct StickyCommand: Command {
    let args: StickyCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }

        let newValue = switch args.toggle {
            case .on: true
            case .off: false
            case .toggle: !window.isSticky
        }
        if newValue == window.isSticky {
            return switch args.failIfNoop {
                case true: .fail
                case false:
                    .succ(io.err("Window '\(window.windowId)' is already \(newValue ? "sticky" : "not sticky"). Tip: use --fail-if-noop to exit with non-zero code"))
            }
        }
        window.isSticky = newValue
        return .succ
    }
}
