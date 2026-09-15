import Common
import Foundation

/// A group names one workspace per monitor, so a single command can change every monitor at once.
///
/// Monitors take their member by position, left to right. The leftmost monitor keeps the bare group
/// name, so on a single monitor a group and a workspace are the same thing. Position rather than
/// display identity means the rule survives a monitor swap: the leftmost screen always shows the
/// unsuffixed member, even after you move a display across the desk.
enum WorkspaceGroup {
    static let separator: Character = ":"

    /// `slot` is 0-based, left to right.
    static func memberName(group: String, slot: Int) -> String {
        slot == 0 ? group : "\(group)\(separator)\(slot + 1)"
    }

    /// The group a workspace belongs to. A name without a numeric suffix is its own group.
    static func groupName(ofWorkspace name: String) -> String {
        guard let index = name.lastIndex(of: separator) else { return name }
        let suffix = name[name.index(after: index)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return name }
        return String(name[..<index])
    }

    /// One member per monitor, in monitor order.
    @MainActor
    static func members(of group: String) -> [(monitor: MonitorInfo, workspace: Workspace)] {
        sortedMonitorInfos.enumerated().map { (slot, monitor) in
            (monitor, Workspace.get(byName: memberName(group: group, slot: slot)))
        }
    }

    /// The member that a window sent to `group` should land on: the one on the biggest monitor.
    @MainActor
    static func largestMonitorMember(of group: String) -> Workspace? {
        members(of: group).maxBy { $0.monitor.rect.width * $0.monitor.rect.height }?.workspace
    }

    /// Every group that currently has a workspace, in workspace order.
    @MainActor
    static var all: [String] {
        Workspace.all.map { groupName(ofWorkspace: $0.name) }.toSet().sorted()
    }
}
