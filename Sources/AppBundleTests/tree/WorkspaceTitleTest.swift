@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceTitleTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        WorkspaceTitleStore.resetAll()
    }

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
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        let workspace = Workspace.get(byName: "3")
        assertEquals(workspace.name, "3")
        assertTrue(Workspace.get(byName: "3") === workspace)
        assertTrue(Workspace.get(byName: "Rust") !== workspace)
        assertTrue(Workspace.get(byName: "Code") !== workspace)
    }

    func testOnlyListedWorkspacesAreTitled() {
        config.workspaceTitles = ["3": "Code"]
        assertEquals(Workspace.get(byName: "4").title, "4")
    }

    func testRenameWinsOverConfiguredTitle() {
        config.workspaceTitles = ["3": "Code"]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").title, "Rust")
    }

    func testRenameAppliesWithoutConfiguredTitle() {
        config.workspaceTitles = [:]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").title, "Rust")
    }

    /// Clearing the field in the rename window is the way back to the configured title
    func testBlankRenameFallsBackToConfiguredTitle() {
        config.workspaceTitles = ["3": "Code"]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        WorkspaceTitleStore.setTitle("   ", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").title, "Code")
    }

    func testBlankRenameFallsBackToNameWhenNothingIsConfigured() {
        config.workspaceTitles = [:]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        WorkspaceTitleStore.setTitle(nil, ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").title, "3")
    }

    func testRenameIsTrimmed() {
        WorkspaceTitleStore.setTitle("  Rust  ", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").title, "Rust")
    }

    func testRenameOnlyAffectsItsOwnWorkspace() {
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "4").title, "4")
    }

    func testTitleWithNameOmitsThePrefixWhenThereIsNoTitle() {
        config.workspaceTitles = [:]
        assertEquals(Workspace.get(byName: "3").titleWithName, "3")
    }

    func testTitleWithNamePrefixesAConfiguredTitle() {
        config.workspaceTitles = ["3": "Code"]
        assertEquals(Workspace.get(byName: "3").titleWithName, "3: Code")
    }

    func testTitleWithNamePrefixesARename() {
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").titleWithName, "3: Rust")
    }

    /// Titling a workspace with its own name must not produce "3: 3"
    func testTitleWithNameDoesNotRepeatTheName() {
        WorkspaceTitleStore.setTitle("3", ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").titleWithName, "3")
    }

    func testTitleWithNameDropsThePrefixAfterAReset() {
        config.workspaceTitles = [:]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        WorkspaceTitleStore.setTitle(nil, ofWorkspace: "3")
        assertEquals(Workspace.get(byName: "3").titleWithName, "3")
    }

    func testResetAllDropsEveryRename() {
        config.workspaceTitles = ["4": "Chat"]
        WorkspaceTitleStore.setTitle("Rust", ofWorkspace: "3")
        WorkspaceTitleStore.setTitle("Web", ofWorkspace: "4")
        WorkspaceTitleStore.resetAll()
        assertEquals(Workspace.get(byName: "3").title, "3")
        assertEquals(Workspace.get(byName: "4").title, "Chat")
    }
}
