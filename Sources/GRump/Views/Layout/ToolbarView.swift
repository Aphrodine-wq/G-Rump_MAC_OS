import SwiftUI

// MARK: - Toolbar View
struct ToolbarView: ToolbarContent {
    let viewModel: ChatViewModel
    @Binding var showSettings: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: { viewModel.createNewConversation() }) {
                Image(systemName: "square.and.pencil")
            }
            .help("New Chat (\u{2318}N)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: {
                showSettings = true
            }) {
                Image(systemName: "gearshape")
            }
            .help("Settings (\u{2318},)")
        }
    }
}
