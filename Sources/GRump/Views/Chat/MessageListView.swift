import SwiftUI

// MARK: - Message List View
//
// Extracted message list component with scrolling and content rendering.
// Handles message display, streaming content, and auto-scroll behavior.

struct MessageListView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var frameLoop: FrameLoopService
    @EnvironmentObject var ambientService: AmbientCodeAwarenessService

    @State private var lastScrollTime: Date = .distantPast
    @State private var lastStreamingLength: Int = 0
    @State private var expandedMessageIds: Set<UUID> = []
    @State private var isFollowingLatest = true

    var body: some View {
        VStack(spacing: 0) {
            // Conversation search bar (Cmd+F)
            ConversationSearchBar()

            ScrollViewReader { proxy in
                ScrollView {
                    messagesListContent
                        .frame(maxWidth: 920)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(themeManager.palette.bgDark)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { _ in
                        isFollowingLatest = false
                    }
                )
                .overlay(alignment: .bottomTrailing) {
                    if !isFollowingLatest && (!displayMessages.isEmpty || !viewModel.streamingContent.isEmpty) {
                        jumpToLatestButton(proxy)
                            .padding(.trailing, Spacing.xxl)
                            .padding(.bottom, Spacing.lg)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .onAppear {
                    if !viewModel.messages.isEmpty || !viewModel.streamingContent.isEmpty {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: viewModel.currentConversation?.id) { _, _ in
                    isFollowingLatest = true
                    if !viewModel.messages.isEmpty || !viewModel.streamingContent.isEmpty {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // A newly submitted user message always resumes following.
                    // Tool and assistant updates respect the reader's scroll position.
                    if viewModel.filteredMessages.last?.role == .user,
                       viewModel.filteredMessages.last?.isInternalAgentNotice != true {
                        isFollowingLatest = true
                    }
                    if isFollowingLatest { scrollToBottom(proxy) }
                }
                .onChange(of: viewModel.streamingContent) { _, newContent in
                    guard isFollowingLatest else { return }
                    if newContent.isEmpty {
                        lastStreamingLength = 0
                        scrollToBottom(proxy)
                    } else {
                        let now = Date()
                        let len = newContent.count
                        let elapsed = now.timeIntervalSince(lastScrollTime)
                        // Adaptive scroll: sync with stream metrics throttle for jank-free scrolling
                        let scrollInterval = viewModel.streamMetrics.recommendedUpdateInterval
                        let charThreshold = max(10, viewModel.streamMetrics.recommendedBatchSize)
                        if elapsed >= scrollInterval || len - lastStreamingLength >= charThreshold || newContent.hasSuffix("\n") {
                            lastScrollTime = now
                            lastStreamingLength = len
                            scrollToBottomImmediate(proxy)
                        }
                    }
                }
                .onChange(of: viewModel.scrollToBottomTrigger) { _, _ in
                    isFollowingLatest = true
                    scrollToBottom(proxy)
                }
            }
        } // end VStack
    }

    // MARK: - Content

    private var messagesListContent: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.lg) {
            // Intent continuity banner — shows active cross-session goal
            if let intent = viewModel.intentContinuity.activeIntent, intent.status == .active {
                IntentBannerView(
                    intent: intent,
                    onPause: { viewModel.intentContinuity.pauseActiveIntent() },
                    onDismiss: { viewModel.intentContinuity.pauseActiveIntent() }
                )
                .id("intent-banner")
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            }

            ForEach(displayMessages) { message in
                messageRowView(for: message)
            }
            .animation(.easeOut(duration: Anim.quick), value: displayMessages.count)

            if !viewModel.streamingContent.isEmpty {
                PremiumStreamingRow(
                    content: viewModel.streamingContent,
                    agentMode: viewModel.agentMode,
                    metrics: viewModel.streamMetrics
                )
                .id("streaming")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }

            // Tool execution timeline
            if !viewModel.activeToolCalls.isEmpty {
                ToolTimelineView(
                    toolCalls: viewModel.activeToolCalls,
                    agentStep: viewModel.currentAgentStep,
                    agentStepMax: viewModel.currentAgentStepMax
                )
                .id("tool-timeline")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }

            if viewModel.isLoading && viewModel.streamingContent.isEmpty && viewModel.activeToolCalls.isEmpty {
                EnhancedTypingIndicator()
                    .id("typing")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity
                    ))
            }

            // Stream error with inline retry
            if let errorMsg = viewModel.streamErrorMessage {
                StreamErrorView(
                    info: viewModel.streamErrorInfo
                        ?? ChatErrorInfo(title: "Something went wrong", guidance: errorMsg, technicalDetail: errorMsg),
                    partialContent: viewModel.streamErrorPartialContent,
                    onRetry: {
                        viewModel.streamErrorMessage = nil
                        viewModel.streamErrorInfo = nil
                        viewModel.streamErrorPartialContent = nil
                        viewModel.errorMessage = nil
                        viewModel.retryLastMessage()
                    },
                    onDismiss: {
                        viewModel.streamErrorMessage = nil
                        viewModel.streamErrorInfo = nil
                        viewModel.streamErrorPartialContent = nil
                        viewModel.errorMessage = nil
                    }
                )
                .id("stream-error")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }

            // Smart follow-up suggestions
            if !viewModel.followUpSuggestions.isEmpty && !viewModel.isLoading {
                FollowUpChipsView(
                    suggestions: viewModel.followUpSuggestions,
                    onSelect: { prompt in
                        viewModel.followUpSuggestions = []
                        viewModel.userInput = prompt
                        viewModel.sendMessage()
                    }
                )
                .id("follow-ups")
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }

            Color.clear.frame(height: Spacing.massive).id("bottom")
        }
        .padding(.vertical, Spacing.xl)
    }

    /// The model needs internal notices and assistant tool-call envelopes in its
    /// history, but users should see a clean transcript instead of protocol noise.
    private var displayMessages: [Message] {
        viewModel.filteredMessages.filter { message in
            guard message.role != .system else { return false }
            guard !message.isInternalAgentNotice else { return false }
            guard !message.isProtocolOnlyAssistantEnvelope else { return false }
            return true
        }
    }

    // MARK: - Message Row

    @ViewBuilder
    private func messageRowView(for message: Message) -> some View {
        if message.role == .tool {
            let ctx = toolResultContext(for: message, messages: viewModel.filteredMessages)
            ToolResultRow(message: message, toolName: ctx?.name, argSummary: ctx?.argSummary)
                .id(message.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .leading)),
                    removal: .opacity
                ))
        } else if viewModel.conversationViewMode == .threaded {
            ThreadedMessageView(
                viewModel: viewModel,
                message: message,
                isExpanded: expandedMessageIds.contains(message.id),
                onToggleExpand: {
                    if expandedMessageIds.contains(message.id) {
                        expandedMessageIds.remove(message.id)
                    } else {
                        expandedMessageIds.insert(message.id)
                    }
                },
                onCreateThread: { viewModel.createThread(from: $0) },
                onCreateBranch: { id, name in viewModel.createBranch(from: id, name: name) },
                onSelectThread: { viewModel.setActiveThread($0) }
            )
            .id(message.id)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            ))
        } else {
            MessageRow(message: message, agentMode: viewModel.agentMode)
                .id(message.id)
                .transition(.opacity)
                .contextMenu {
                    Button(action: { viewModel.createThread(from: message.id) }) {
                        Label("Create Thread", systemImage: "bubble.left.and.bubble.right")
                    }
                    Button(action: { viewModel.createBranch(from: message.id, name: "Branch") }) {
                        Label("Create Branch", systemImage: "arrow.branch")
                    }
                }
        }
    }

    // Helper function for tool result context
    private func toolResultContext(for message: Message, messages: [Message]) -> (name: String, argSummary: String)? {
        guard let toolCallId = message.toolCallId,
              let toolCallMessage = messages.first(where: {
                  $0.toolCalls?.contains(where: { $0.id == toolCallId }) == true
              }),
              let toolCall = toolCallMessage.toolCalls?.first(where: { $0.id == toolCallId }) else {
            return nil
        }

        let argSummary: String
        if toolCall.arguments.count > 50 {
            argSummary = String(toolCall.arguments.prefix(47)) + "..."
        } else {
            argSummary = toolCall.arguments
        }

        return (name: toolCall.name, argSummary: argSummary)
    }

    // MARK: - Scrolling

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: Anim.smooth)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func scrollToBottomImmediate(_ proxy: ScrollViewProxy) {
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    private func jumpToLatestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            isFollowingLatest = true
            scrollToBottom(proxy)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text("Latest")
                    .font(Typography.captionSmallSemibold)
            }
            .foregroundColor(themeManager.palette.textPrimary)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(themeManager.palette.bgElevated)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
            .shadow(color: themeManager.palette.bgDark.opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Jump to the latest response")
    }
}
