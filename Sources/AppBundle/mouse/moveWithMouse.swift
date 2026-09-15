import AppKit
import Common

@MainActor
private var moveWithMouseTask: Task<(), any Error>? = nil

func movedObs(_: AXObserver, ax: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let windowId = ax.containingWindowId()
    let notif = notif as String
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        guard let windowId, let window = Window.get(byId: windowId), try await isManipulatedWithMouse(window) else {
            scheduleCancellableCompleteRefreshSession(.ax(notif))
            return
        }
        moveWithMouseTask?.cancel()
        moveWithMouseTask = Task.startUnstructured {
            try checkCancellation()
            try await runLightSession(.ax(notif), token) {
                try await moveWithMouse(window)
            }
        }
    }
}

@MainActor
private func moveWithMouse(_ window: Window) async throws { // todo cover with tests
    resetClosedWindowsCache()
    switch window.windowParentCases {
        case .floatingWindowsContainer:
            try await moveFloatingWindow(window)
        case .stripWindowsContainer:
            return // A strip owns its band, so dragging must not move it
        case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            return // Unconventional windows can't be moved with mouse
        case .tilingContainer:
            moveTilingWindow(window)
        case .unbound: return
    }
}

@MainActor
private func moveFloatingWindow(_ window: Window) async throws {
    guard let targetWorkspace = try await window.getCenter(.cancellable)?.monitorApproximation.activeWorkspace else { return }
    guard let parent = window.parent else { return }
    if targetWorkspace != parent {
        window.bindAsFloatingWindow(to: targetWorkspace)
    }
}

@MainActor
private func moveTilingWindow(_ window: Window) {
    currentlyManipulatedWithMouseWindowId = window.windowId
    // Mark the window as "lifted out": the layout reflows as if it weren't there (siblings fill
    // its slot), and it floats freely under the cursor. Nothing in the tree is mutated until drop.
    draggedTiledWindowId = window.windowId
    window.lastAppliedLayoutPhysicalRect = nil
    let mouseLocation = mouseLocation
    let targetWorkspace = mouseLocation.monitorApproximation.activeWorkspace
    let target = mouseLocation
        .findWindowRecursively(in: targetWorkspace.rootTilingContainer, virtual: false, fullscreenCoversAll: false)?
        .takeIf { $0 != window }

    if targetWorkspace != window.nodeWorkspace { // hovering a different monitor/workspace
        if let target, let parent = target.parent as? TilingContainer, let targetRect = target.lastAppliedLayoutPhysicalRect {
            let after = mouseLocation.getProjection(parent.orientation) >= targetRect.center.getProjection(parent.orientation)
            pendingDrag = .moveToWorkspace(targetWorkspace.name, near: target.windowId, after: after)
            DropZoneHud.shared.show(at: dragSplitHighlightRect(in: targetRect, orientation: parent.orientation, insertBefore: !after))
        } else {
            pendingDrag = .moveToWorkspace(targetWorkspace.name, near: nil, after: false)
            DropZoneHud.shared.hide()
        }
    } else if let target, let targetRect = target.lastAppliedLayoutPhysicalRect {
        // Insert-only: dropping anywhere on a tile splits it toward the nearest edge.
        let (orientation, insertBefore) = dragDropZone(in: targetRect, at: mouseLocation)
        pendingDrag = .split(target: target.windowId, orientation: orientation, insertBefore: insertBefore)
        DropZoneHud.shared.show(at: dragSplitHighlightRect(in: targetRect, orientation: orientation, insertBefore: insertBefore))
    } else {
        // Over a gap / the dragged window's own area: dropping here is a no-op (it snaps back).
        pendingDrag = nil
        DropZoneHud.shared.hide()
    }
}

/// The sub-region of `rect` that the dragged window will occupy for a given edge split.
func dragSplitHighlightRect(in rect: Rect, orientation: Orientation, insertBefore: Bool) -> Rect {
    switch orientation {
        case .h:
            let w = rect.width / 2
            return Rect(topLeftX: insertBefore ? rect.topLeftX : rect.topLeftX + w, topLeftY: rect.topLeftY, width: w, height: rect.height)
        case .v:
            let h = rect.height / 2
            return Rect(topLeftX: rect.topLeftX, topLeftY: insertBefore ? rect.topLeftY : rect.topLeftY + h, width: rect.width, height: h)
    }
}

@MainActor var pendingDrag: PendingDrag? = nil

enum PendingDrag {
    /// Split `target` and drop the window into the half nearest where it was released.
    case split(target: UInt32, orientation: Orientation, insertBefore: Bool)
    /// Move the window to another monitor's workspace, next to `near` (or appended if nil).
    case moveToWorkspace(_ workspace: String, near: UInt32?, after: Bool)
}

/// Which way a drop splits the tile under the cursor: always toward the nearest edge.
/// `point` and `rect` are both in the top-left-origin (monitor-normalized) space.
func dragDropZone(in rect: Rect, at point: CGPoint) -> (orientation: Orientation, insertBefore: Bool) {
    let fx = rect.width > 0 ? (point.x - rect.minX) / rect.width : 0.5
    let fy = rect.height > 0 ? (point.y - rect.minY) / rect.height : 0.5
    let toLeft = fx, toRight = 1 - fx, toTop = fy, toBottom = 1 - fy
    return min(toLeft, toRight) <= min(toTop, toBottom)
        ? (.h, insertBefore: toLeft <= toRight)
        : (.v, insertBefore: toTop <= toBottom)
}

/// Wraps `target` in a new tiling container and inserts `dragged` beside it. Mirrors `join-with`.
@MainActor
func splitWindowForDrag(_ dragged: Window, into target: Window, orientation: Orientation, insertBefore: Bool) {
    if dragged == target { return }
    guard target.parent is TilingContainer else { return }
    let prevBinding = target.unbindFromParent()
    let newParent = TilingContainer(
        parent: prevBinding.parent,
        adaptiveWeight: prevBinding.adaptiveWeight,
        orientation,
        .tiles,
        index: prevBinding.index,
    )
    dragged.unbindFromParent()
    target.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: 0)
    dragged.bind(to: newParent, adaptiveWeight: WEIGHT_AUTO, index: insertBefore ? 0 : INDEX_BIND_LAST)
}

/// Commits the drag recorded during the drag. Called on mouse-up, before the tree is re-laid-out.
@MainActor
func commitPendingDragIfPossible() {
    let pending = pendingDrag
    pendingDrag = nil
    guard let pending, let draggedId = draggedTiledWindowId, let dragged = Window.get(byId: draggedId) else { return }
    switch pending {
        case .split(let targetId, let orientation, let insertBefore):
            guard let target = Window.get(byId: targetId), dragged != target,
                  dragged.nodeWorkspace == target.nodeWorkspace, target.parent is TilingContainer else { return }
            splitWindowForDrag(dragged, into: target, orientation: orientation, insertBefore: insertBefore)
        case .moveToWorkspace(let wsName, let nearId, let after):
            let workspace = Workspace.get(byName: wsName)
            dragged.unbindFromParent()
            if let nearId, let neighbor = Window.get(byId: nearId), let parent = neighbor.parent as? TilingContainer, let idx = neighbor.ownIndex {
                dragged.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: idx + (after ? 1 : 0))
            } else {
                dragged.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
            }
    }
}

@MainActor
func swapWindows(mruDominant window1: Window, _ window2: Window) {
    if window1 == window2 { return }

    let binding2 = window2.unbindFromParent()
    let binding1 = window1.unbindFromParent()

    window2.bind(to: binding1.parent, adaptiveWeight: binding1.adaptiveWeight, index: binding1.index)
    window1.bind(to: binding2.parent, adaptiveWeight: binding2.adaptiveWeight, index: binding2.index)
}

extension CGPoint {
    @MainActor
    func findWindowRecursively(
        in tree: TilingContainer,
        virtual: Bool,
        fullscreenCoversAll: Bool,
    ) -> Window? {
        if fullscreenCoversAll {
            if let window = tree.mostRecentWindowRecursive, window.isFullscreen {
                return window
            }
        }
        return _findWindowRecursively(in: tree, virtual: virtual)
    }

    @MainActor
    private func _findWindowRecursively(in tree: TilingContainer, virtual: Bool) -> Window? {
        let point = self
        let target: TreeNode? = switch tree.layout {
            case .tiles:
                tree.children.first(where: {
                    (virtual ? $0.lastAppliedLayoutVirtualRect : $0.lastAppliedLayoutPhysicalRect)?.contains(point) == true
                })
            case .accordion:
                tree.mostRecentChild
        }
        guard let target else { return nil }
        return switch target.tilingTreeNodeCasesOrDie() {
            case .window(let window): window
            case .tilingContainer(let container): _findWindowRecursively(in: container, virtual: virtual)
        }
    }
}
