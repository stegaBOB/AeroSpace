import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    @StateObject var viewModel = TrayMenuModel.shared
    @StateObject var messageModel = MessageModel.shared
    @StateObject var renameWorkspaceModel = RenameWorkspaceModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        menuBar(viewModel: viewModel)
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
        getRenameWorkspaceWindow(model: renameWorkspaceModel)
            .onChange(of: renameWorkspaceModel.workspaceName) { workspaceName in
                if workspaceName != nil {
                    openWindow(id: renameWorkspaceWindowId)
                }
            }
    }
}
