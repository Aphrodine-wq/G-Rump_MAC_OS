import SwiftUI
#if os(macOS)
import AppKit
import CoreSpotlight
#else
import UIKit
import CoreSpotlight
#endif

struct ContentView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var frameLoop: FrameLoopService
    @EnvironmentObject var ambientService: AmbientCodeAwarenessService
    @StateObject private var state = ContentViewState()
    @FocusState private var messageFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        bodyContent
            .onChange(of: viewModel.workingDirectory) { _, newDir in
                ambientService.setWorkingDirectory(newDir)
                if !newDir.isEmpty {
                    state.lspService.start(workspaceRoot: newDir)
                }
            }
            .onAppear {
                if !viewModel.workingDirectory.isEmpty {
                    ambientService.setWorkingDirectory(viewModel.workingDirectory)
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        state.lspService.start(workspaceRoot: viewModel.workingDirectory)
                    }
                }
                // Index all conversations in Spotlight on launch (off main thread)
                let conversations = viewModel.conversations
                Task.detached(priority: .background) {
                    await SpotlightIndexer.shared.indexAllConversations(conversations)
                }
            }
            // Handoff: advertise current conversation activity
            .userActivity(GRumpActivityType.conversation) { activity in
                if let conv = viewModel.currentConversation {
                    let handoff = HandoffActivityBuilder.makeConversationActivity(
                        conversation: conv,
                        workingDirectory: viewModel.workingDirectory
                    )
                    activity.title = handoff.title
                    activity.isEligibleForHandoff = true
                    activity.isEligibleForSearch = true
                    activity.userInfo = handoff.userInfo
                    activity.requiredUserInfoKeys = handoff.requiredUserInfoKeys
                }
            }
            // Handle Spotlight search result / Handoff continuation
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                if let convId = SpotlightIndexer.conversationId(from: activity),
                   let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                    viewModel.selectConversation(conv)
                }
            }
            .onContinueUserActivity(GRumpActivityType.conversation) { activity in
                if let convId = SpotlightIndexer.conversationId(from: activity),
                   let conv = viewModel.conversations.first(where: { $0.id == convId }) {
                    viewModel.selectConversation(conv)
                }
            }
            .onChange(of: state.lspService.diagnostics) { _, newDiags in
                viewModel.lspDiagnostics = newDiags
                viewModel.lspStatusMessage = state.lspService.statusMessage
            }
            .onChange(of: viewModel.isLoading) { _, newValue in
                if !newValue && !viewModel.messages.isEmpty {
                    generateQuestionSuggestions()
                } else if newValue {
                    state.showQuestionSuggestions = false
                }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleActivityBar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.activityBarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleStatusBar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.statusBarVisible.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleZenMode"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.zenMode.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpShowLayoutCustomizer"))) { _ in
                state.showLayoutCustomizer = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpResetLayout"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.activityBarVisible = true
                    state.layoutOptions.primarySidebarVisible = true
                    state.layoutOptions.panelVisible = true
                    state.layoutOptions.statusBarVisible = true
                    state.layoutOptions.primarySidebarPosition = .right
                    state.layoutOptions.zenMode = false
                    state.layoutOptions.fullScreenMode = false
                    state.layoutOptions.centeredLayout = false
                }
                state.restoreFocus()
            }
            .onChange(of: state.layoutOptions.activityBarVisible) { _, _ in state.restoreFocus() }
            .onChange(of: state.layoutOptions.zenMode) { _, _ in state.restoreFocus() }
            .onChange(of: state.layoutOptions.primarySidebarVisible) { _, _ in state.restoreFocus() }
            .modifier(AppleIntegrationHandlers(viewModel: viewModel, state: state))
            #endif
    }

    private var messageFieldFocusedBinding: Binding<Bool> {
        Binding(
            get: { messageFieldFocused },
            set: { messageFieldFocused = $0 }
        )
    }

    private var bodyContent: some View {
        ModalManagerView(
            showProfile: $state.showProfile,
            showThreadNavigation: $state.showThreadNavigation,
            showSettings: $state.showSettings,
            settingsInitialTab: $state.settingsInitialTab,
            messageFieldFocused: messageFieldFocusedBinding,
            viewModel: viewModel,
            content: mainLayout
        )
        .overlay {
            KeyboardShortcutOverlayView(
                showSettings: $state.showSettings,
                sidebarCollapsed: $state.sidebarCollapsed,
                selectedPanelRaw: $state.selectedPanelRaw,
                rightPanelCollapsed: $state.rightPanelCollapsed,
                messageFieldFocused: messageFieldFocusedBinding,
                onShowLayoutCustomizer: { state.showLayoutCustomizer = true }
            )
        }
        .overlay(alignment: .topTrailing) {
            if state.showFPSOverlay {
                FPSOverlayView()
                    .padding(Spacing.xl)
            }
        }
        #if os(macOS)
        .background(themeManager.palette.bgDark)
        .confirmationDialog("Allow this command?", isPresented: Binding(
            get: { viewModel.pendingSystemRunApproval != nil },
            set: { if !$0, viewModel.pendingSystemRunApproval != nil { viewModel.respondToSystemRunApproval(.deny) } }
        ), titleVisibility: .visible) {
            Button("Run Once") { viewModel.respondToSystemRunApproval(.allowOnce) }
            Button("Always Allow") { viewModel.respondToSystemRunApproval(.allowAlways) }
            Button("Deny", role: .cancel) { viewModel.respondToSystemRunApproval(.deny) }
        } message: {
            if let p = viewModel.pendingSystemRunApproval {
                Text("\(p.resolvedPath)\n\n\(p.command)")
            }
        }
        .toolbar {
            ToolbarView(viewModel: viewModel, showSettings: $state.showSettings)
        }
        #endif
    }

    private var isZenMode: Bool { state.layoutOptions.zenMode }

    
    private var mainLayout: some View {
        MainLayoutView(
            layoutOptions: LayoutOptions.shared,
            primarySidebarContent: AnyView(
                SidebarLayoutView(
                    layoutOptions: LayoutOptions.shared,
                    viewModel: viewModel,
                    showSettings: $state.showSettings,
                    showProfile: $state.showProfile,
                    onOpenFolder: runFolderPicker
                )
            ),
            chatArea: AnyView(
                PanelLayoutView(
                    layoutOptions: LayoutOptions.shared,
                    showSettings: $state.showSettings,
                    chatDetailView: AnyView(chatDetailView)
                )
            ),
            onShowLayoutCustomizer: { state.showLayoutCustomizer = true }
        )
        .sheet(isPresented: $state.showLayoutCustomizer, onDismiss: {
            state.restoreFocus()
        }) {
            LayoutCustomizerView()
        }
    }

    
    private func runFolderPicker() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setWorkingDirectory(url.path)
        #endif
    }

    // MARK: - Empty States

    private var onboardingEmptyState: some View {
        EmptyStateViews.onboardingEmptyState(
            themeManager: themeManager,
            showSettings: $state.showSettings,
            settingsInitialTab: $state.settingsInitialTab
        )
    }

    private var noSelectionEmptyState: some View {
        EmptyStateViews.noSelectionEmptyState(
            viewModel: viewModel,
            themeManager: themeManager
        )
    }

    private var emptyStateView: some View {
        EmptyStateViews.emptyStateView(
            themeManager: themeManager,
            showQuestionSuggestions: $state.showQuestionSuggestions,
            suggestedQuestions: $state.suggestedQuestions,
            onPromptSelected: { prompt in
                viewModel.userInput = prompt
                messageFieldFocused = true
            }
        )
    }

    // MARK: - Chat Detail

    @ViewBuilder
    private var chatContentArea: some View {
        if !viewModel.canUseAI {
            onboardingEmptyState
        } else if viewModel.currentConversation == nil {
            noSelectionEmptyState
        } else if viewModel.messages.isEmpty && viewModel.streamingContent.isEmpty {
            emptyStateView
        } else if state.showTimeline {
            AgentTimelineView(
                toolCalls: viewModel.activeToolCalls,
                messages: viewModel.filteredMessages,
                onSelectMessage: { messageId in
                    state.showTimeline = false
                }
            )
        } else {
            MessageListView()
        }
    }

    private var modeButtonsRow: some View {
        HStack(spacing: Spacing.md) {
            ForEach(AgentMode.allCases) { mode in
                let isSelected = viewModel.agentMode == mode
                Button {
                    withAnimation(.easeInOut(duration: Anim.quick)) {
                        viewModel.agentMode = mode
                        state.showModeToast(mode)
                    }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(mode.displayName)
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(isSelected ? mode.modeAccentColor : themeManager.palette.textSecondary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(isSelected ? mode.modeAccentColor.opacity(0.12) : themeManager.palette.bgInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(isSelected ? mode.modeAccentColor.opacity(0.5) : Color.clear, lineWidth: isSelected ? 2 : 0)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
                .help(mode.description)
                .accessibilityLabel("\(mode.displayName) mode")
                .accessibilityHint(mode.description)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.huge)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    private var chatInputSection: some View {
        let onSend: () -> Void = {
            if viewModel.agentMode == .spec {
                withAnimation(.easeInOut(duration: 0.25)) {
                    state.showSpecQuestionsModal = true
                }
            } else {
                viewModel.sendMessage()
            }
        }
        return VStack(spacing: 0) {
            // Undo send toast
            if viewModel.undoSendAvailable {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text("Message sent")
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                    Button(action: { viewModel.undoSend() }) {
                        Text("Undo")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Undo send")
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.lg)
                .background(themeManager.palette.bgCard)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.undoSendAvailable)
            }

            // Mode description toast (above input)
            if let toast = state.modeToastText {
                Text(toast)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(themeManager.palette.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.huge)
                    .padding(.bottom, Spacing.sm)
            }

            // Inline Spec Context bar (replaces old modal sheet)
            if state.showSpecQuestionsModal {
                SpecContextBar(
                    isExpanded: $state.showSpecQuestionsModal,
                    userMessage: viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    onContinue: { context in
                        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.userInput = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                + "\n\n[Spec context]\n" + trimmed
                        }
                        viewModel.sendMessage()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    },
                    onSkip: {
                        viewModel.sendMessage()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    }
                )
            }

            // Question suggestions (above input)
            if state.showQuestionSuggestions && !state.suggestedQuestions.isEmpty {
                QuestionSuggestionView(
                    questions: state.suggestedQuestions,
                    onSelect: { question in
                        viewModel.userInput = question
                        state.showQuestionSuggestions = false
                        messageFieldFocused = true
                    },
                    onDismiss: {
                        state.showQuestionSuggestions = false
                    }
                )
            }

            ChatInputView(
                text: $viewModel.userInput,
                isLoading: viewModel.isLoading,
                onSend: onSend,
                focus: $messageFieldFocused,
                onStop: { viewModel.stopGeneration() }
            )
            // Mode buttons below chat bar
            if viewModel.canUseAI {
                modeButtonsRow
            }
        }
    }

    @ViewBuilder
    private var chatDetailStack: some View {
        VStack(spacing: 0) {
            if !state.isZenMode {
                ChatTopBarView(
                    viewModel: viewModel,
                    lspService: state.lspService,
                    showSettings: $state.showSettings,
                    settingsInitialTab: $state.settingsInitialTab,
                    showTimeline: $state.showTimeline
                )

                Rectangle()
                    .fill(themeManager.palette.borderCrisp.opacity(0.7))
                    .frame(height: Border.thin)
            }

            // Thread/branch view mode toggle
            if let conv = viewModel.currentConversation,
               !conv.threads.isEmpty || !conv.branches.isEmpty {
                HStack(spacing: Spacing.md) {
                    Picker("View", selection: Binding(
                        get: { viewModel.conversationViewMode },
                        set: { viewModel.setConversationViewMode($0) }
                    )) {
                        Text("Linear").tag(Conversation.ConversationViewMode.linear)
                        Text("Threaded").tag(Conversation.ConversationViewMode.threaded)
                        Text("Branched").tag(Conversation.ConversationViewMode.branched)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()

                    Button(action: { state.showThreadNavigation.toggle() }) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Threads & Branches")
                    .accessibilityLabel("Toggle thread navigation")
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.sm)
                .background(themeManager.palette.bgElevated.opacity(0.5))
            }

            chatContentArea

            if !viewModel.activeToolCalls.isEmpty {
                activeToolCallsBar
            }

            if let err = viewModel.errorMessage {
                errorBanner(err)
            }

            Rectangle()
                .fill(themeManager.palette.borderCrisp.opacity(0.7))
                .frame(height: Border.thin)

            // Chat input: centered, constrained width, lifted from bottom
            HStack {
                Spacer(minLength: 0)
                chatInputSection
                    .frame(maxWidth: 760)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.huge)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
            
            // Status bar at the bottom
            if state.layoutOptions.statusBarVisible && !state.isZenMode {
                StatusBarView(viewModel: viewModel)
            }
        }
    }

    private var chatDetailBase: some View {
        chatDetailStack
            .background(themeManager.palette.bgDark)
    }

    // MARK: - Right Panel Content

    
    private var chatDetailView: some View {
        chatDetailBase
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if newValue != nil { HapticHelper.error() }
            }
            .onChange(of: viewModel.activeToolCalls) { old, new in
                let oldCompleted = Set(old.filter { $0.status == .completed }.map(\.id))
                let newlyCompleted = new.filter { $0.status == .completed && !oldCompleted.contains($0.id) }
                if !newlyCompleted.isEmpty { HapticHelper.success() }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GRumpOpenSettings"))) { _ in
                state.showSettings = true
            }
            #endif
    }


    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.accentOrange)
                .font(Typography.bodySmall)
            Text(message)
                .font(Typography.bodySmall)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Spacer()

            Button(action: { viewModel.retryLastMessage() }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmallSemibold)
                    Text("Retry")
                        .font(Typography.captionSmallSemibold)
                }
                .foregroundColor(themeManager.palette.effectiveAccent)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(themeManager.palette.effectiveAccent.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry last message")

            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xl)
        .background(Color.accentOrange.opacity(0.08))
        .overlay(Rectangle()
            .frame(height: 1)
            .foregroundColor(.accentOrange.opacity(0.25)), alignment: .bottom)
    }

    // MARK: - Active Tool Calls Bar

    private var activeToolCallsBar: some View {
        let tools = viewModel.activeToolCalls
        let runningCount = tools.filter { $0.status == .running }.count
        let completedCount = tools.filter { $0.status == .completed }.count
        let failedCount = tools.filter { $0.status == .failed }.count
        
        return VStack(spacing: 0) {
            if tools.count > 1 {
                Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { state.toolCallsBarExpanded.toggle() } }) {
                    HStack(spacing: Spacing.lg) {
                        // Overall progress indicator
                        ZStack {
                            Circle()
                                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(completedCount + failedCount) / CGFloat(tools.count))
                                .stroke(
                                    failedCount > 0 ? Color.red : themeManager.palette.effectiveAccent,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                )
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: completedCount + failedCount)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(.textPrimary)
                            
                            HStack(spacing: Spacing.xs) {
                                if runningCount > 0 {
                                    Label("\(runningCount) running", systemImage: "arrow.triangle.2.circlepath")
                                        .font(Typography.micro)
                                        .foregroundColor(.orange)
                                }
                                if completedCount > 0 {
                                    Label("\(completedCount) done", systemImage: "checkmark.circle.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(.accentGreen)
                                }
                                if failedCount > 0 {
                                    Label("\(failedCount) failed", systemImage: "xmark.circle.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        Spacer()
                        Image(systemName: state.toolCallsBarExpanded ? "chevron.down" : "chevron.right")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, Spacing.huge)
                    .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle tool calls detail, \(tools.count) tools, \(runningCount) running, \(completedCount) done")
            }
            
            if state.toolCallsBarExpanded || tools.count <= 1 {
                ForEach(tools) { tool in
                    EnhancedToolCallRow(tool: tool, themeManager: themeManager)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
                .animation(.easeOut(duration: Anim.smooth), value: tools.map(\.id))
            }
        }
        .background(themeManager.palette.effectiveAccent.opacity(0.06))
        .overlay(Rectangle().frame(height: Border.thin).foregroundColor(themeManager.palette.borderCrisp), alignment: .top)
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "read_file", "batch_read_files": return "doc.text"
        case "write_file", "append_file": return "pencil"
        case "edit_file": return "square.and.pencil"
        case "create_file", "create_directory": return "doc.badge.plus"
        case "delete_file": return "trash"
        case "compress_files", "extract_archive": return "doc.zipper"
        case "list_directory", "tree_view": return "folder"
        case "search_files": return "magnifyingglass"
        case "grep_search": return "text.magnifyingglass"
        case "find_and_replace": return "arrow.left.arrow.right"
        case "run_command", "run_background": return "terminal"
        case "kill_process": return "stop.circle"
        case "which": return "magnifyingglass"
        case "system_run": return "terminal.fill"
        case "system_notify": return "bell.fill"
        case "clipboard_read", "clipboard_write": return "doc.on.clipboard"
        case "open_url": return "link"
        case "open_app": return "app.badge"
        case "screen_snapshot": return "rectangle.dashed.badge.record"
        case "screen_record": return "record.circle"
        case "camera_snap": return "camera.fill"
        case "window_list", "window_snapshot": return "macwindow"
        case "web_search": return "globe"
        case "read_url", "fetch_json", "download_file": return "link"
        case "view_code_outline": return "chevron.left.forwardslash.chevron.right"
        case "run_format": return "paintbrush"
        case "get_package_deps", "npm_install", "pip_install", "cargo_add": return "shippingbox"
        case "git_status", "git_add", "git_commit", "git_stash", "git_checkout", "git_push", "git_pull": return "vault"
        case "run_tests": return "checkmark.circle"
        case "get_system_info", "list_network_interfaces": return "info.circle"
        default: return "wrench"
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func toolArgSummary(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let path = args["path"] as? String { return (path as NSString).lastPathComponent }
        if let command = args["command"] as? String { return String(command.prefix(50)) }
        if let query = args["query"] as? String { return String(query.prefix(40)) }
        if let url = args["url"] as? String { return String(url.prefix(50)) }
        if let dir = args["directory"] as? String { return (dir as NSString).lastPathComponent }
        if let name = args["name_or_bundle_id"] as? String { return String(name.prefix(30)) }
        if let text = args["text"] as? String { return String(text.prefix(30)) + (text.count > 30 ? "…" : "") }
        if let paths = args["paths"] as? [String], let first = paths.first { return "\(paths.count) file(s), e.g. \((first as NSString).lastPathComponent)" }
        if let cmd = args["command"] as? String, !cmd.isEmpty { return String(cmd.prefix(40)) }
        return ""
    }

    // Generate question suggestions based on context
    private func generateQuestionSuggestions() {
        guard !viewModel.messages.isEmpty else { return }
        
        let lastMessage = viewModel.messages.last
        guard lastMessage?.role == .assistant else { return }
        
        state.suggestedQuestions = [
            "Can you explain that in more detail?",
            "How do I implement this?",
            "What are the alternatives?",
            "Show me an example",
            "What are the best practices here?"
        ]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                state.showQuestionSuggestions = true
            }
        }
    }
}

// MARK: - Tool Result Row (collapsible)

struct ToolResultRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let message: Message
    var toolName: String? = nil
    var argSummary: String? = nil
    @State private var isExpanded = false

    private var headerTitle: String {
        if let name = toolName, !name.isEmpty {
            return name
        }
        return "Tool result"
    }

    private var toolIcon: String {
        guard let name = toolName?.lowercased() else { return "wrench" }
        if name.contains("read") || name.contains("file") { return "doc.text" }
        if name.contains("write") || name.contains("edit") || name.contains("create") { return "square.and.pencil" }
        if name.contains("delete") { return "trash" }
        if name.contains("search") || name.contains("grep") || name.contains("find") { return "magnifyingglass" }
        if name.contains("command") || name.contains("run") || name.contains("shell") { return "terminal" }
        if name.contains("git") { return "arrow.triangle.branch" }
        if name.contains("list") || name.contains("tree") || name.contains("directory") { return "folder" }
        if name.contains("web") || name.contains("url") || name.contains("fetch") { return "globe" }
        if name.contains("test") { return "checkmark.circle" }
        if name.contains("clipboard") { return "doc.on.clipboard" }
        if name.contains("screen") || name.contains("window") { return "macwindow" }
        return "wrench"
    }

    private var statusColor: Color {
        let content = message.content.lowercased()
        if content.contains("error") || content.contains("failed") || content.contains("not found") {
            return .red
        }
        return .accentGreen
    }

    private var isBuildTool: Bool {
        guard let name = toolName?.lowercased() else { return false }
        return name.contains("command") || name.contains("run") || name.contains("shell") || name.contains("build")
    }

    private var parsedBuildErrors: [BuildError] {
        guard isBuildTool else { return [] }
        let errors = BuildErrorParserEngine.parse(message.content)
        return errors.isEmpty ? [] : errors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact one-liner: ✓ Tool Name · arg summary — click to expand
            Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isExpanded.toggle() } }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: statusColor == .red ? "xmark" : "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(statusColor)

                    Text(headerTitle)
                        .font(Typography.micro)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)

                    if let arg = argSummary, !arg.isEmpty {
                        Text("·")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                        Text(arg)
                            .font(Typography.micro)
                            .fontDesign(.monospaced)
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                }
                .padding(.vertical, Spacing.xxs)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Rich rendering for build errors
                if isBuildTool, !parsedBuildErrors.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(parsedBuildErrors.prefix(10)) { error in
                            HStack(alignment: .top, spacing: Spacing.md) {
                                Image(systemName: error.severity.icon)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(error.severity.color)
                                    .frame(width: 14)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(error.message)
                                        .font(Typography.captionSmallMedium)
                                        .foregroundColor(themeManager.palette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: Spacing.sm) {
                                        Text(error.fileName)
                                            .font(Typography.codeMicro)
                                            .foregroundColor(themeManager.palette.effectiveAccent)
                                        Text(":\(error.line)")
                                            .font(Typography.codeMicro)
                                            .foregroundColor(themeManager.palette.textMuted)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.xxs)
                        }

                        if parsedBuildErrors.count > 10 {
                            Text("… and \(parsedBuildErrors.count - 10) more")
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.textMuted)
                                .padding(.horizontal, Spacing.lg)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                } else {
                    ScrollView {
                        Text(message.content)
                            .font(Typography.codeSmallScaled(scale: themeManager.contentSize.scaleFactor))
                            .foregroundColor(themeManager.palette.textSecondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 300)
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(themeManager.palette.effectiveAccent)
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    scale = 1.4
                }
            }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    let message: Message
    var agentMode: AgentMode = .standard
    @State private var showCopyConfirm = false
    @State private var isHovered = false
    @State private var reaction: MessageReaction? = nil
    @State private var isEditing = false
    @State private var editText = ""

    enum MessageReaction { case thumbsUp, thumbsDown }

    var isUser: Bool { message.role == .user }

    // MARK: - Mode-Specific Styling

    private var modeMood: LogoMood {
        switch agentMode {
        case .standard, .parallel, .speculative: return .neutral
        case .plan: return .thinking
        case .fullStack: return .happy
        case .argue: return .error  // grumpy/angry face
        case .spec: return .thinking
        }
    }

    private var modeLineSpacing: CGFloat {
        switch agentMode {
        case .plan: return 2        // tighter for structured lists
        case .argue: return 5       // more spacious for readability
        case .fullStack: return 3   // standard
        case .spec: return 4        // slightly spacious for Q&A
        default: return 3
        }
    }

    private var modeBorderColor: Color? {
        switch agentMode {
        case .argue: return Color(red: 1.0, green: 0.45, blue: 0.3).opacity(0.3)
        case .plan: return Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3)
        case .fullStack: return Color(red: 0.2, green: 0.85, blue: 0.5).opacity(0.3)
        case .spec: return Color(red: 0.8, green: 0.6, blue: 1.0).opacity(0.3)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                userBlock
            } else {
                assistantBlock
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xs)
        .onHover { isHovered = $0 }
    }

    // MARK: - User Message (right-aligned plain text, flat)

    private var userBlock: some View {
        VStack(alignment: .trailing, spacing: Spacing.sm) {
            if isEditing {
                VStack(alignment: .trailing, spacing: Spacing.md) {
                    TextEditor(text: $editText)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 200)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.lg) {
                        Button("Cancel") {
                            isEditing = false
                        }
                        .buttonStyle(.plain)
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)

                        Button("Save & Resend") {
                            viewModel.editUserMessage(message.id, newContent: editText)
                            isEditing = false
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: Spacing.sm) {
                    Text(message.content)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(themeManager.palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
                        )

                    // Edit button on hover
                    if isHovered {
                        Button(action: {
                            editText = message.content
                            isEditing = true
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "pencil")
                                    .font(Typography.micro)
                                Text("Edit")
                                    .font(Typography.micro)
                            }
                            .foregroundColor(themeManager.palette.textMuted)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
        .animation(.easeInOut(duration: Anim.quick), value: isEditing)
    }

    // MARK: - Assistant Message (flat text, small inline icon)

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Inline label: tiny frowny icon + "G-Rump"
            HStack(spacing: Spacing.sm) {
                FrownyFaceLogo(size: 16, mood: modeMood)
                Text("G-Rump")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            // Tool calls as compact one-liners
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(toolCalls.prefix(6).enumerated()), id: \.offset) { _, call in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.accentGreen)
                            Text(call.name.replacingOccurrences(of: "_", with: " "))
                                .font(Typography.micro)
                                .fontDesign(.monospaced)
                                .foregroundColor(themeManager.palette.textMuted)
                        }
                    }
                    if toolCalls.count > 6 {
                        Text("+\(toolCalls.count - 6) more")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }
            }

            // Message content — flat, no bubble
            if !message.content.isEmpty {
                let hasComplexContent = message.content.contains("```") || (message.content.contains("|") && message.content.contains("---"))
                let markdownView = MarkdownTextView(text: message.content)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if hasComplexContent {
                    markdownView.drawingGroup()
                } else {
                    markdownView
                }
            }

            // Inline question option grid (auto-detected from markdown or ask_user tool)
            if let parsed = QuestionParser.parse(from: message.content) {
                QuestionOptionGrid(question: parsed) { selected in
                    viewModel.userInput = selected.label
                    Task { await viewModel.sendMessage() }
                }
                .padding(.top, Spacing.sm)
            }

            // Action bar (hover-visible): reactions + regenerate + copy
            if isHovered {
                assistantActionBar
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if let borderColor = modeBorderColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(borderColor)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.sm)
            }
        }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }

    // MARK: - Assistant Action Bar (reactions, regenerate, copy)

    private var assistantActionBar: some View {
        HStack(spacing: Spacing.xl) {
            // Thumbs up
            Button(action: { reaction = (reaction == .thumbsUp) ? nil : .thumbsUp }) {
                Image(systemName: reaction == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsUp ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs up")

            // Thumbs down
            Button(action: { reaction = (reaction == .thumbsDown) ? nil : .thumbsDown }) {
                Image(systemName: reaction == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsDown ? Color(red: 1.0, green: 0.4, blue: 0.4) : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs down")

            Divider().frame(height: 14)

            // Copy
            copyButton

            // Regenerate
            Button(action: {
                viewModel.retryLastMessage()
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.micro)
                    Text("Regenerate")
                        .font(Typography.micro)
                }
                .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Regenerate response")

            Spacer()
        }
    }

    // MARK: - Shared Components

    private var copyButton: some View {
        Button(action: {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #else
            UIPasteboard.general.string = message.content
            #endif
            showCopyConfirm = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                showCopyConfirm = false
            }
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: showCopyConfirm ? "checkmark" : "doc.on.doc")
                    .font(Typography.micro)
                Text(showCopyConfirm ? "Copied" : "Copy")
                    .font(Typography.micro)
            }
            .foregroundColor(showCopyConfirm ? .accentGreen : themeManager.palette.textMuted)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(showCopyConfirm ? "Copied to clipboard" : "Copy message")
    }

    private func toolIconForName(_ name: String) -> String {
        switch name {
        case "read_file", "batch_read_files": return "doc.text"
        case "write_file", "append_file": return "pencil"
        case "edit_file": return "square.and.pencil"
        case "create_file", "create_directory": return "doc.badge.plus"
        case "delete_file": return "trash"
        case "list_directory", "tree_view": return "folder"
        case "search_files", "grep_search": return "magnifyingglass"
        case "run_command", "run_background", "system_run": return "terminal"
        case "git_status", "git_add", "git_commit", "git_push", "git_pull": return "arrow.triangle.branch"
        case "web_search": return "globe"
        case "read_url", "fetch_json": return "link"
        case "run_tests": return "checkmark.circle"
        default: return "wrench"
        }
    }
}

// MARK: - Global Scale Button Style (press-down effect on all buttons)

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: Anim.quick, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Streaming Collapsed Preview (Personality Quips + Wave/Shimmer)

struct GRumpStreamingBubble: View {
    @EnvironmentObject var themeManager: ThemeManager
    let content: String
    var agentMode: AgentMode = .standard

    @State private var currentQuip: String = ""
    @State private var quipTimer: Timer?
    @State private var wavePhase: CGFloat = 0
    @State private var shimmerOffset: CGFloat = -200

    private static let personalityQuips: [String] = [
        "Grumpin' it",
        "frowning",
        "stressing",
        "yanking my hair out",
        "coding hella fast type shi",
        "making dad proud",
        "pushing for your dreams rn",
        "get some water this may take a while",
        "grump",
        "dude get off the keyboard",
        "professional work happenin'",
        "whoooooooops",
        "lemme cook",
        "vibes are immaculate rn",
        "trust the process",
        "almost there... maybe",
        "this is fine",
        "big brain energy",
        "no thoughts just code",
        "built different fr"
    ]

    private var phaseLabel: String {
        if content.isEmpty {
            return "Thinking"
        } else if content.count < 50 {
            return "Warming up"
        } else {
            return "Writing"
        }
    }

    private var modeLabel: String {
        switch agentMode {
        case .standard, .parallel: return "Chat"
        case .plan: return "Plan"
        case .fullStack: return "Build"
        case .argue: return "Debate"
        case .spec: return "Spec"
        case .speculative: return "Explore"
        }
    }

    private var modeMood: LogoMood {
        switch agentMode {
        case .standard, .parallel, .speculative: return .neutral
        case .plan: return .thinking
        case .fullStack: return .happy
        case .argue: return .error
        case .spec: return .thinking
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            FrownyFaceLogo(size: 16, mood: modeMood)

            // Status text with wave float + shimmer
            Text("\(modeLabel) · \(phaseLabel) · \(currentQuip)")
                .font(Typography.captionSmallMedium)
                .foregroundColor(themeManager.palette.textMuted)
                .lineLimit(1)
                .offset(y: sin(wavePhase) * 1.5)
                .overlay(
                    LinearGradient(
                        colors: [
                            .clear,
                            themeManager.palette.effectiveAccent.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 80)
                    .offset(x: shimmerOffset)
                    .mask(
                        Text("\(modeLabel) · \(phaseLabel) · \(currentQuip)")
                            .font(Typography.captionSmallMedium)
                            .lineLimit(1)
                    )
                )

            Spacer()
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .drawingGroup()
        .onAppear {
            currentQuip = Self.personalityQuips.randomElement() ?? "Grumpin' it"

            // Rotate quips every ~5 seconds
            quipTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentQuip = Self.personalityQuips.randomElement() ?? "Grumpin' it"
                }
            }

            // Wave float animation
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }

            // Shimmer sweep animation
            withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 400
            }
        }
        .onDisappear {
            quipTimer?.invalidate()
            quipTimer = nil
        }
    }
}

// MARK: - Thinking Dots (minimal bouncing)

struct ThinkingDots: View {
    var color: Color
    @State private var activeIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color.opacity(activeIndex == i ? 1.0 : 0.3))
                    .frame(width: 5, height: 5)
                    .offset(y: activeIndex == i ? -2 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: activeIndex)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                activeIndex = (activeIndex + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Streaming Message Row (alias for backward compat)

typealias StreamingMessageRow = GRumpStreamingBubble

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var dotIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            FrownyFaceLogo(size: 16)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            i == dotIndex
                                ? themeManager.palette.effectiveAccent
                                : Color.textMuted.opacity(0.4)
                        )
                        .frame(width: 5, height: 5)
                        .scaleEffect(dotIndex == i ? 1.25 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dotIndex)
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xs)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.38, repeats: true) { _ in
                dotIndex = (dotIndex + 1) % 3
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Enhanced Tool Call Row

struct EnhancedToolCallRow: View {
    let tool: ToolCallStatus
    let themeManager: ThemeManager
    @State private var animatedProgress: Double = 0
    
    private var statusColor: Color {
        switch tool.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .accentGreen
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
    
    private var statusIcon: String {
        switch tool.status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
    
    private var elapsedTime: String {
        guard let startTime = tool.startTime else { return "" }
        let endTime = tool.endTime ?? Date()
        let duration = endTime.timeIntervalSince(startTime)
        if duration < 1 {
            return "< 1s"
        } else if duration < 60 {
            return "\(Int(duration))s"
        } else {
            return "\(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s"
        }
    }
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.lg) {
                // Status indicator with animation
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if tool.status == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(statusColor)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(statusColor)
                    }
                }
                
                // Tool info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: toolIcon(tool.name))
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                        
                        Text(toolDisplayName(tool.name))
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Text(elapsedTime)
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }
                    
                    if let currentStep = tool.currentStep {
                        HStack {
                            Text(currentStep)
                                .font(Typography.micro)
                                .foregroundColor(statusColor)
                            
                            if tool.totalSteps > 1 {
                                Text("(\(tool.currentStepNumber)/\(tool.totalSteps))")
                                    .font(Typography.micro)
                                    .foregroundColor(.textMuted)
                            }
                        }
                    }
                }
            }
            
            // Progress bar for running tools
            if tool.status == .running && tool.totalSteps > 1 {
                HStack(spacing: Spacing.sm) {
                    ProgressView(value: animatedProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                        .scaleEffect(y: 0.5)
                    
                    Text("\(Int(animatedProgress * 100))%")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
            }
            
            // Tool arguments (collapsible)
            if !tool.arguments.isEmpty {
                Text(toolArgSummary(tool.arguments))
                    .font(Typography.codeSmall)
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xs)
                    .background(themeManager.palette.bgDark.opacity(0.5))
                    .cornerRadius(Radius.xs)
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.md)
        .background(themeManager.palette.bgCard.opacity(0.5))
        .cornerRadius(Radius.sm)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = tool.progress
            }
        }
        .onChange(of: tool.progress) { _, newProgress in
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
        }
    }
    
    private func toolIcon(_ name: String) -> String {
        switch name {
        case "read_file", "batch_read_files": return "doc.text"
        case "write_file", "append_file": return "pencil"
        case "edit_file": return "square.and.pencil"
        case "create_file", "create_directory": return "doc.badge.plus"
        case "delete_file": return "trash"
        case "compress_files", "extract_archive": return "doc.zipper"
        case "list_directory", "tree_view": return "folder"
        case "search_files": return "magnifyingglass"
        case "grep_search": return "text.magnifyingglass"
        case "find_and_replace": return "arrow.left.arrow.right"
        case "run_command", "run_background": return "terminal"
        case "kill_process": return "stop.circle"
        case "which": return "magnifyingglass"
        case "system_run": return "terminal.fill"
        case "system_notify": return "bell.fill"
        case "clipboard_read", "clipboard_write": return "doc.on.clipboard"
        case "open_url": return "link"
        case "open_app": return "app.badge"
        case "screen_snapshot": return "rectangle.dashed.badge.record"
        case "screen_record": return "record.circle"
        case "camera_snap": return "camera.fill"
        case "window_list", "window_snapshot": return "macwindow"
        case "web_search": return "globe"
        case "read_url", "fetch_json", "download_file": return "link"
        case "view_code_outline": return "chevron.left.forwardslash.chevron.right"
        default: return "wrench.and.screwdriver"
        }
    }
    
    private func toolDisplayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }
    
    private func toolArgSummary(_ args: String) -> String {
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return args
        }
        
        var parts: [String] = []
        if let path = json["path"] as? String {
            parts.append("path: \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        if let command = json["command"] as? String {
            parts.append("cmd: \(command.components(separatedBy: " ").first ?? command)")
        }
        if let query = json["query"] as? String {
            parts.append("query: \(String(query.prefix(30)))")
        }
        
        return parts.isEmpty ? args : parts.joined(separator: " • ")
    }
}

// MARK: - Apple Integration Notification Handlers (extracted to fix type-checker timeout)

#if os(macOS)
private struct AppleIntegrationHandlers: ViewModifier {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var state: ContentViewState

    func body(content: Content) -> some View {
        content
            // Services menu: "Ask G-Rump" with selected text
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpServiceAsk"))) { note in
                if let text = note.userInfo?["text"] as? String, !text.isEmpty {
                    viewModel.createNewConversation()
                    viewModel.userInput = text
                    viewModel.sendMessage()
                }
            }
            // Services menu / Finder: "Ask About File"
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpServiceFile"))) { note in
                if let paths = note.userInfo?["paths"] as? [String], !paths.isEmpty {
                    viewModel.createNewConversation()
                    let fileList = paths.map { "- `\($0)`" }.joined(separator: "\n")
                    viewModel.userInput = "Please analyze the following file(s):\n\(fileList)"
                    viewModel.sendMessage()
                }
            }
            // Notification action / URL scheme: open conversation by UUID
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpOpenConversation"))) { note in
                if let idString = note.userInfo?["conversationId"] as? String,
                   let uuid = UUID(uuidString: idString),
                   let conv = viewModel.conversations.first(where: { $0.id == uuid }) {
                    viewModel.selectConversation(conv)
                }
            }
            // Notification action: re-run last message in conversation
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpRunAgain"))) { note in
                if let idString = note.userInfo?["conversationId"] as? String,
                   let uuid = UUID(uuidString: idString),
                   let conv = viewModel.conversations.first(where: { $0.id == uuid }) {
                    viewModel.selectConversation(conv)
                    if let lastUserMsg = conv.messages.last(where: { $0.role == .user }) {
                        viewModel.userInput = lastUserMsg.content
                        viewModel.sendMessage()
                    }
                }
            }
            // Notification action: approve pending system_run
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpApproveAction"))) { note in
                if let _ = note.userInfo?["approvalId"] as? String {
                    viewModel.respondToSystemRunApproval(.allowOnce)
                }
            }
            // Notification action: deny pending system_run
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpDenyAction"))) { note in
                if let _ = note.userInfo?["approvalId"] as? String {
                    viewModel.respondToSystemRunApproval(.deny)
                }
            }
            // Dock menu / keyboard shortcut: new chat
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpNewChat"))) { _ in
                viewModel.createNewConversation()
            }
            // Dock menu: toggle sidebar
            .onReceive(NotificationCenter.default.publisher(for: .init("GRumpToggleSidebar"))) { _ in
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    state.layoutOptions.primarySidebarVisible.toggle()
                }
            }
    }
}
#endif
