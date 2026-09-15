import AppKit
import Common
import Foundation

enum StripEdge: String, CaseIterable, Equatable, Sendable {
    case left, right, top, bottom

    var orientation: Orientation {
        switch self {
            case .left, .right: .h
            case .top, .bottom: .v
        }
    }
}

/// A window pinned to an edge of its monitor, at a fixed size, on every workspace.
///
/// A strip takes a whole band off one edge of what is left, so strips nest from the outside in and
/// the tiling area stays a single rectangle. A band anywhere else would cut that area in two.
struct WindowStrip: Equatable {
    let edge: StripEdge
    /// Width for a left or right strip, height for a top or bottom one
    let size: CGFloat
    /// Creation order. The first strip made is the outermost band
    let ordinal: Int
}

@MainActor private var nextStripOrdinal = 0

@MainActor
func newStripOrdinal() -> Int {
    nextStripOrdinal += 1
    return nextStripOrdinal
}

extension Workspace {
    /// Strips of this workspace, outermost first.
    @MainActor
    var strips: [Window] {
        allLeafWindowsRecursive
            .filter { $0.strip != nil }
            .sorted { ($0.strip?.ordinal ?? 0) < ($1.strip?.ordinal ?? 0) }
    }
}

/// Takes each strip's band off `rect` in creation order and returns the bands together with what is
/// left for normal tiling.
func reserveStripBands(_ rect: Rect, _ strips: [WindowStrip]) -> (bands: [Rect], rest: Rect) {
    var rest = rect
    var bands: [Rect] = []
    for strip in strips {
        // A band may never take the whole area, or tiling would have nowhere to go
        let available = rest.getDimension(strip.edge.orientation)
        let size = min(strip.size, max(available - 1, 0))
        if size <= 0 {
            bands.append(Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY, width: 0, height: 0))
            continue
        }
        switch strip.edge {
            case .left:
                bands.append(Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY, width: size, height: rest.height))
                rest = Rect(topLeftX: rest.topLeftX + size, topLeftY: rest.topLeftY, width: rest.width - size, height: rest.height)
            case .right:
                bands.append(Rect(topLeftX: rest.maxX - size, topLeftY: rest.topLeftY, width: size, height: rest.height))
                rest = Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY, width: rest.width - size, height: rest.height)
            case .top:
                bands.append(Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY, width: rest.width, height: size))
                rest = Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY + size, width: rest.width, height: rest.height - size)
            case .bottom:
                bands.append(Rect(topLeftX: rest.topLeftX, topLeftY: rest.maxY - size, width: rest.width, height: size))
                rest = Rect(topLeftX: rest.topLeftX, topLeftY: rest.topLeftY, width: rest.width, height: rest.height - size)
        }
    }
    return (bands, rest)
}

/// The edge of `rect` that `windowRect` sits nearest to, and how far the window reaches along that
/// edge's axis. Used to turn the focused window into a strip without asking for numbers.
func stripFromGeometry(window windowRect: Rect, monitor rect: Rect, ordinal: Int) -> WindowStrip {
    let toLeft = windowRect.minX - rect.minX
    let toRight = rect.maxX - windowRect.maxX
    let toTop = windowRect.minY - rect.minY
    let toBottom = rect.maxY - windowRect.maxY

    let edge: StripEdge = [
        (StripEdge.left, toLeft), (.right, toRight), (.top, toTop), (.bottom, toBottom),
    ].minByOrDie { $0.1 }.0
    return WindowStrip(edge: edge, size: windowRect.getDimension(edge.orientation), ordinal: ordinal)
}
