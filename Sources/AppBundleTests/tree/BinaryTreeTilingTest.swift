@testable import AppBundle
import Common
import XCTest

@MainActor
final class BinaryTreeTilingTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testDwindleSplitOrientation() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: name).rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 50)
        assertTrue(window.dwindleSplitOrientation == .h) // wider than tall -> side by side
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 50, height: 100)
        assertTrue(window.dwindleSplitOrientation == .v) // taller than wide -> stacked
    }

    func testBinaryTreeInsertWrapsFocusedWindow() async throws {
        config.tilingInsertionStrategy = .binaryTree
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 50) // wide -> .h

        let w2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await w2.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)

        // The focused window is wrapped in a fresh binary container and the newcomer goes beside it
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .h_tiles([.window(1), .window(2)]),
        ]))
    }

    func testBinaryTreeSpiral() async throws {
        config.tilingInsertionStrategy = .binaryTree
        config.enableNormalizationFlattenContainers = true // match real runtime normalization
        let workspace = Workspace.get(byName: name)

        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)
        w1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 200, height: 100) // wide -> .h

        let w2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await w2.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
        workspace.normalizeContainers()
        // With two windows the redundant wrapper is flattened to a single side-by-side container
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))

        assertEquals(w2.focusWindow(), true)
        w2.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 100, topLeftY: 0, width: 80, height: 100) // tall -> .v
        let w3 = TestWindow.new(id: 3, parent: workspace.rootTilingContainer)
        try await w3.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)
        workspace.normalizeContainers()

        // The focused right-hand window is split vertically, producing the dwindle spiral
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([
            .window(1),
            .v_tiles([.window(2), .window(3)]),
        ]))
    }

    func testMoveNodeToWorkspaceDwindles() async throws {
        config.tilingInsertionStrategy = .binaryTree
        let wsB = Workspace.get(byName: "B")
        let b1 = TestWindow.new(id: 1, parent: wsB.rootTilingContainer)
        assertEquals(b1.focusWindow(), true) // b1 is the MRU window of workspace B
        b1.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 50) // wide -> .h

        let a1 = TestWindow.new(id: 2, parent: Workspace.get(byName: name).rootTilingContainer)
        assertEquals(a1.focusWindow(), true)

        try await parseCommand("move-node-to-workspace B").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // Moving a tiled window into a workspace splits its focused tile, just like opening a new one
        assertEquals(wsB.rootTilingContainer.layoutDescription, .h_tiles([
            .h_tiles([.window(1), .window(2)]),
        ]))
    }

    func testMoveNodeToWorkspaceI3AppendsFlat() async throws {
        config.tilingInsertionStrategy = .i3
        let wsB = Workspace.get(byName: "B")
        let b1 = TestWindow.new(id: 1, parent: wsB.rootTilingContainer)
        assertEquals(b1.focusWindow(), true)

        let a1 = TestWindow.new(id: 2, parent: Workspace.get(byName: name).rootTilingContainer)
        assertEquals(a1.focusWindow(), true)

        try await parseCommand("move-node-to-workspace B").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // i3 mode is unchanged: the window is flat-appended to the target root
        assertEquals(wsB.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testI3StrategyAppendsSibling() async throws {
        config.tilingInsertionStrategy = .i3
        let workspace = Workspace.get(byName: name)
        let w1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(w1.focusWindow(), true)
        let w2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        try await w2.relayoutWindow(on: workspace, .nonCancellable, forceTile: true)

        // Default i3 behavior: the newcomer is appended next to the focused window, no nesting
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }
}
