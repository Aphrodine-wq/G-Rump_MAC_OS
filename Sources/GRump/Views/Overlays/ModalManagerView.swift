import SwiftUI

// MARK: - Modal Manager View
struct ModalManagerView<Content: View>: View {
    @Binding var showProfile: Bool
    @Binding var showThreadNavigation: Bool
    @Binding var showSettings: Bool
    @Binding var settingsInitialTab: SettingsTab?
    @Binding var messageFieldFocused: Bool
    @FocusState var focusState: Bool

    @ObservedObject var viewModel: ChatViewModel
    let content: Content

    var body: some View {
        content
            .sheet(isPresented: $showProfile, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                profileSheetContent
            }
            .sheet(isPresented: $showThreadNavigation, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                ThreadNavigationView(viewModel: viewModel)
                    .frame(minWidth: 320, minHeight: 400)
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                settingsInitialTab = nil
                Task { await viewModel.refreshLocalOllamaAvailability() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                settingsSheetContent
            }
    }

    // MARK: - Sheet Contents

    private var profileSheetContent: some View {
        Text("Profile Sheet")
    }

    @ViewBuilder
    private var settingsSheetContent: some View {
        #if os(macOS)
        SettingsView(
            apiKey: $viewModel.apiKey,
            selectedModel: $viewModel.selectedModel,
            systemPrompt: $viewModel.systemPrompt,
            workingDirectory: $viewModel.workingDirectory,
            onSetWorkingDirectory: { viewModel.setWorkingDirectory($0) },
            platformUser: viewModel.platformUser,
            onPlatformLoginSuccess: { await viewModel.refreshPlatformUser() },
            onPlatformLogout: { viewModel.logoutPlatform() },
            initialTab: settingsInitialTab,
            onExportJSON: { viewModel.runExportJSONPanel() },
            onExportMarkdown: { viewModel.runExportMarkdownPanel(onlyCurrent: false) },
            onImport: { viewModel.runImportPanel() },
            onApplyPreset: { viewModel.applyPreset($0) },
            onClearPreset: { viewModel.clearAppliedPreset() },
            appliedPresetName: viewModel.appliedPresetName,
            systemRunHistory: viewModel.systemRunHistory,
            onRestartOnboarding: {
                showSettings = false
                UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            }
        )
        #else
        SettingsView(
            apiKey: $viewModel.apiKey,
            selectedModel: $viewModel.selectedModel,
            systemPrompt: $viewModel.systemPrompt,
            workingDirectory: $viewModel.workingDirectory,
            onSetWorkingDirectory: { viewModel.setWorkingDirectory($0) },
            platformUser: viewModel.platformUser,
            onPlatformLoginSuccess: { await viewModel.refreshPlatformUser() },
            onPlatformLogout: { viewModel.logoutPlatform() },
            initialTab: settingsInitialTab,
            onApplyPreset: { viewModel.applyPreset($0) },
            onClearPreset: { viewModel.clearAppliedPreset() },
            appliedPresetName: viewModel.appliedPresetName,
            systemRunHistory: viewModel.systemRunHistory,
            onRestartOnboarding: {
                showSettings = false
                UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            }
        )
        #endif
    }
}
