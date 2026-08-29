import AppKit

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
/// Set while a *tiled* window is being dragged with the mouse. The layout lifts this window out of
/// the tiling division (siblings reflow to fill its slot) until the drag is committed on mouse-up.
@MainActor var draggedTiledWindowId: UInt32? = nil
var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow(.cancellable) == window }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }
