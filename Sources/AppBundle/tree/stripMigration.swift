import Common
import Foundation

/// Moves every strip into the active workspace of the monitor it already sits on.
///
/// A strip migrates rather than being exempted from hiding. A window left behind in an invisible
/// workspace is hidden off screen, and focusing it drags that whole workspace back. Migrating keeps
/// it in the workspace you are looking at, so hiding and focus need no special case.
///
/// Runs before `normalizeContainers`, so the tree is normalized after the move, and before the tray
/// and layout passes, so neither sees stale membership.
@MainActor
func migrateStrips() {
    for window in Workspace.all.flatMap({ $0.allLeafWindowsRecursive }) where window.strip != nil {
        guard let from = window.nodeWorkspace else { continue }
        let to = from.workspaceMonitor.activeWorkspace
        if to == from { continue }

        // bind marks the window as most recent, which would hand it the focus the next time this
        // workspace is focused, and would make it the anchor for binary-tree insertion
        let mruBefore = to.mostRecentWindowRecursive
        switch window.windowParentCases {
            case .tilingContainer:
                // Slot and weight do not matter: a strip is laid out in its own band, and
                // layoutTiles leaves it out of the division
                window.bind(to: to.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
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
