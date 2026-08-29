@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class DragToSplitTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDropZoneSplitsTowardNearestEdge() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        func zone(_ x: CGFloat, _ y: CGFloat) -> (Orientation, Bool) {
            let z = dragDropZone(in: rect, at: CGPoint(x: x, y: y)); return (z.orientation, z.insertBefore)
        }
        assertTrue(zone(5, 50) == (.h, true))    // left edge -> horizontal, before
        assertTrue(zone(95, 50) == (.h, false))  // right edge -> horizontal, after
        assertTrue(zone(50, 5) == (.v, true))    // top edge -> vertical, before
        assertTrue(zone(50, 95) == (.v, false))  // bottom edge -> vertical, after
    }

    func testSplitHighlightRect() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 80)
        func fields(_ r: Rect) -> [CGFloat] { [r.topLeftX, r.topLeftY, r.width, r.height] }
        assertEquals(fields(dragSplitHighlightRect(in: rect, orientation: .h, insertBefore: true)), [0, 0, 50, 80])   // left half
        assertEquals(fields(dragSplitHighlightRect(in: rect, orientation: .h, insertBefore: false)), [50, 0, 50, 80]) // right half
        assertEquals(fields(dragSplitHighlightRect(in: rect, orientation: .v, insertBefore: true)), [0, 0, 100, 40])  // top half
        assertEquals(fields(dragSplitHighlightRect(in: rect, orientation: .v, insertBefore: false)), [0, 40, 100, 40]) // bottom half
    }

    func testSplitWindowForDragBottom() {
        let workspace = Workspace.get(byName: name)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        // Drop dragged on the bottom of target -> vertical split, dragged ends up below target
        splitWindowForDrag(dragged, into: target, orientation: .v, insertBefore: false)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .v_tiles([.window(2), .window(1)]),
        ]))
    }

    func testSplitWindowForDragLeft() {
        let workspace = Workspace.get(byName: name)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        // Drop dragged on the left of target -> horizontal split, dragged ends up left of target
        splitWindowForDrag(dragged, into: target, orientation: .h, insertBefore: true)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .h_tiles([.window(1), .window(2)]),
        ]))
    }

    func testCommitPendingDragSplits() {
        let workspace = Workspace.get(byName: name)
        let dragged = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        draggedTiledWindowId = dragged.windowId
        pendingDrag = .split(target: target.windowId, orientation: .v, insertBefore: false)

        commitPendingDragIfPossible()

        assertTrue(pendingDrag == nil)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .v_tiles([.window(2), .window(1)]),
        ]))
        draggedTiledWindowId = nil
    }

    func testCommitPendingDragMovesToWorkspace() {
        let wsA = Workspace.get(byName: name)
        let wsB = Workspace.get(byName: "drag-target-ws")
        let b1 = TestWindow.new(id: 1, parent: wsB.rootTilingContainer)
        let dragged = TestWindow.new(id: 2, parent: wsA.rootTilingContainer)
        draggedTiledWindowId = dragged.windowId
        pendingDrag = .moveToWorkspace("drag-target-ws", near: b1.windowId, after: true)

        commitPendingDragIfPossible()

        assertEquals(wsB.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
        draggedTiledWindowId = nil
    }
}
