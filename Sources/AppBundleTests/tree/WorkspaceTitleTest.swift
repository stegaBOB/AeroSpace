@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceTitleTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTitleFallsBackToName() {
        config.workspaceTitles = [:]
        assertEquals(Workspace.get(byName: "3").title, "3")
    }

    func testTitleIsUsedWhenConfigured() {
        config.workspaceTitles = ["3": "Code"]
        assertEquals(Workspace.get(byName: "3").title, "Code")
    }

    /// A title is presentation only. Renaming must never change how a workspace is addressed,
    /// otherwise config bindings would start pointing at a different workspace
    func testTitleDoesNotChangeTheName() {
        config.workspaceTitles = ["3": "Code"]
        let workspace = Workspace.get(byName: "3")
        assertEquals(workspace.name, "3")
        assertTrue(Workspace.get(byName: "3") === workspace)
        assertTrue(Workspace.get(byName: "Code") !== workspace)
    }

    func testOnlyListedWorkspacesAreTitled() {
        config.workspaceTitles = ["3": "Code"]
        assertEquals(Workspace.get(byName: "4").title, "4")
    }
}
