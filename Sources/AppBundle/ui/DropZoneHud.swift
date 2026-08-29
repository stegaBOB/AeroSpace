import AppKit
import Common
import SwiftUI

/// A translucent highlight shown while dragging a tiled window, previewing where it will land:
/// a half of the target tile for an edge (split) drop, or the whole tile for a center (swap) drop.
public final class DropZoneHud: NSPanelHud {
    @MainActor public static let shared = DropZoneHud()
    private let hostingView = NSHostingView(rootView: DropZoneView())

    override private init() {
        super.init()
        // The overlay must never swallow the mouse events that drive the drag
        self.ignoresMouseEvents = true
        self.hasShadow = false
        contentView?.addSubview(hostingView)
    }

    /// `rect` is in AeroSpace's monitor-normalized, top-left-origin space (same as layout rects).
    func show(at rect: Rect) {
        let frame = rect.toAppKitScreenCgRect()
        setFrame(frame, display: true)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        if !isVisible { orderFrontRegardless() }
    }

    func hide() {
        if isVisible { close() }
    }
}

struct DropZoneView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.accentColor.opacity(0.30))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2),
            )
    }
}
