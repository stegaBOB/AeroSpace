import Common
import SwiftUI

public let renameWorkspaceWindowId = "\(aeroSpaceAppName).renameWorkspace"

public final class RenameWorkspaceModel: ObservableObject {
    @MainActor public static let shared = RenameWorkspaceModel()
    /// The name of the workspace being renamed. Non nil opens the window
    @Published public var workspaceName: String? = nil

    private init() {}
}

@MainActor
public func getRenameWorkspaceWindow(model: RenameWorkspaceModel) -> some Scene {
    SwiftUI.Window("Rename workspace", id: renameWorkspaceWindowId) {
        RenameWorkspaceView(model: model)
            .onAppear {
                // Same reason as the message window: an accessory app cannot accept keyboard input
                // until the activation policy is set
                NSApp.setActivationPolicy(.accessory)
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows where window.identifier?.rawValue == renameWorkspaceWindowId {
                    window.level = .floating
                    window.styleMask.remove(.miniaturizable)
                }
            }
    }
    .windowResizability(.contentSize)
}

struct RenameWorkspaceView: View {
    @StateObject private var model: RenameWorkspaceModel
    @Environment(\.dismiss) private var dismiss: DismissAction
    @FocusState private var focus: Bool
    @State private var draft: String = ""

    init(model: RenameWorkspaceModel) {
        self._model = .init(wrappedValue: model)
    }

    var body: some View {
        let workspaceName = model.workspaceName ?? ""
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename workspace \(workspaceName)")
                .font(.headline)
            TextField("", text: $draft)
                .focused($focus)
                .frame(width: 260)
                .onSubmit { commit(draft) }
            Text("Only the displayed title changes. Commands and bindings keep addressing this workspace as '\(workspaceName)'.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 260, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                // Clearing the title is the way back to the configured title, or to the name
                Button("Reset") { commit(nil) }
                Spacer()
                Button("Cancel") { close() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commit(draft) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trim().isEmpty)
            }
        }
        .padding()
        .onAppear {
            draft = model.workspaceName.map { Workspace.get(byName: $0).title } ?? ""
            focus = true
        }
        .onChange(of: model.workspaceName) { name in
            switch name {
                case let name?: draft = Workspace.get(byName: name).title
                case nil: dismiss()
            }
        }
        .onDisappear { model.workspaceName = nil }
    }

    private func commit(_ title: String?) {
        if let workspaceName = model.workspaceName {
            WorkspaceTitleStore.setTitle(title, ofWorkspace: workspaceName)
            updateTrayText()
        }
        close()
    }

    private func close() {
        model.workspaceName = nil
        dismiss()
    }
}
