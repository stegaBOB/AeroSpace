/// Holds the windows pinned to a monitor edge. They are not part of the tiling division, so they do
/// not live in the tiling tree, for the same reason floating windows do not.
final class StripWindowsContainer: TreeNode, NonLeafTreeNodeObject {
    @MainActor
    init(parent: Workspace) {
        super.init(parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }
}
