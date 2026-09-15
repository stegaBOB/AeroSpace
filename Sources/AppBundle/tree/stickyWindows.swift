import Common
import Foundation

/// Moves every sticky window into the active workspace of the monitor it already sits on.
///
/// Sticky is a migration rather than an exemption from hiding. A window left behind in an invisible
/// workspace is not part of the visible workspace's tree, so it cannot tile with it, and focusing it
/// drags that whole workspace back. Migrating instead leaves an ordinary window in the current
/// workspace, so layout, focus, `move`, and normalization need no special case.
///
/// Runs before `normalizeContainers`, so the tree is normalized after the move, and before the tray
/// and layout passes, so neither sees stale membership.
@MainActor
func migrateStickyWindows() {
    for window in Workspace.all.flatMap({ $0.allLeafWindowsRecursive }) where window.isSticky {
        guard let from = window.nodeWorkspace else { continue }
        let to = from.workspaceMonitor.activeWorkspace
        if to == from { continue }

        // bind marks the window as most recent, which would hand it the focus the next time this
        // workspace is focused, and would make it the anchor for binary-tree insertion
        let mruBefore = to.mostRecentWindowRecursive
        switch window.windowParentCases {
            case .tilingContainer:
                let root = to.rootTilingContainer
                // Keep the slot, but take the size of a newly inserted window. Carrying the weight
                // over ratchets the window wider on every switch: layoutTiles writes each child's
                // weight to its laid out length, so the weight read here is the length the window
                // filled in the workspace it is leaving, not a share of it
                let index = window.ownIndex.map { min($0, root.children.count) } ?? INDEX_BIND_LAST
                window.bind(to: root, adaptiveWeight: WEIGHT_AUTO, index: index)
            case .floatingWindowsContainer:
                window.bind(to: to.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            // A window macOS has taken over sits in its own container and is not ours to move
            case .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer,
                 .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .unbound:
                continue
        }
        mruBefore?.markAsMostRecentChild()
    }
}
