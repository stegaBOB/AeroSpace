public struct WorkspaceGroupCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .workspaceGroup,
        help: workspace_group_help_generated,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        posArgs: [
            dashDashArg(mandatory: false),
            newMandatoryPosArgParser(\.target, parseGroupName, placeholder: "<group>"),
        ],
    )

    public var target: Lateinit<WorkspaceName> = .uninitialized
    public var failIfNoop: Bool = false
}

public struct MoveNodeToWorkspaceGroupCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .moveNodeToWorkspaceGroup,
        help: move_node_to_workspace_group_help_generated,
        flags: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--focus-follows-window": ArgParser(\.focusFollowsWindow, constSubArgParserFun(true)),
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [
            dashDashArg(mandatory: false),
            newMandatoryPosArgParser(\.target, parseGroupName, placeholder: "<group>"),
        ],
    )

    public var target: Lateinit<WorkspaceName> = .uninitialized
    public var failIfNoop: Bool = false
    public var focusFollowsWindow: Bool = false
}

/// A group name is a workspace name. The leftmost monitor's member uses it unchanged.
private func parseGroupName(i: PosArgParserInput) -> ParsedCliArgs<WorkspaceName> {
    .init(WorkspaceName.parse(i.arg), advanceBy: 1)
}
