import SwiftUI

// MARK: - Message Rendering Components

struct UserMessageBlock: View {
    let message: Message
    let isEditing: Bool
    let editText: String
    let themeManager: ThemeManager
    let onEditChange: (String) -> Void
    let onCancelEdit: () -> Void
    let onSaveResend: () -> Void
    
    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.sm) {
            if isEditing {
                VStack(alignment: .trailing, spacing: Spacing.md) {
                    TextEditor(text: .constant(editText))
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 200)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.lg) {
                        Button("Cancel") {
                            onCancelEdit()
                        }
                        .buttonStyle(.plain)
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)

                        Button("Save & Resend") {
                            onSaveResend()
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(themeManager.accentColor.color)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                }
            } else {
                HStack(spacing: Spacing.md) {
                    Spacer()
                    Text(message.content)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(themeManager.palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
            }
        }
    }
}

struct AssistantMessageBlock: View {
    let message: Message
    let agentMode: AgentMode
    let themeManager: ThemeManager
    let reaction: MessageReaction?
    let onReactionChange: (MessageReaction?) -> Void
    let onRegenerate: () -> Void
    let onCopy: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Avatar and content
            HStack(alignment: .top, spacing: Spacing.md) {
                FrownyFaceLogo(size: 32, mood: logoMood)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Content
                    MarkdownTextView(
                        text: message.content,
                        onCodeBlockTap: nil
                    )
                    .textSelection(.enabled)
                    
                    // Action bar
                    AssistantActionBar(
                        reaction: reaction,
                        themeManager: themeManager,
                        onReactionChange: onReactionChange,
                        onRegenerate: onRegenerate,
                        onCopy: onCopy
                    )
                }
                
                Spacer()
            }
        }
        .padding(.trailing, 80) // Space for potential edit button
    }
    
    private var logoMood: LogoMood {
        switch agentMode {
        case .standard: return .neutral
        case .plan: return .thinking
        case .fullStack: return .happy
        case .argue: return .error
        case .spec: return .thinking
        case .parallel: return .thinking
        case .speculative: return .neutral
        }
    }
}

struct AssistantActionBar: View {
    let reaction: MessageReaction?
    let themeManager: ThemeManager
    let onReactionChange: (MessageReaction?) -> Void
    let onRegenerate: () -> Void
    let onCopy: () -> Void
    var messageContent: String = ""
    @State private var showTranslateMenu = false
    
    var body: some View {
        HStack(spacing: Spacing.xl) {
            // Thumbs up
            Button(action: { onReactionChange((reaction == .thumbsUp) ? nil : .thumbsUp) }) {
                Image(systemName: reaction == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsUp ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs up")

            // Thumbs down
            Button(action: { onReactionChange((reaction == .thumbsDown) ? nil : .thumbsDown) }) {
                Image(systemName: reaction == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsDown ? Color(red: 1.0, green: 0.4, blue: 0.4) : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs down")

            Divider().frame(height: 14)

            // Copy
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Copy message")

            // Regenerate
            Button(action: onRegenerate) {
                Image(systemName: "arrow.clockwise")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Regenerate response")

            // Translate (surfaces TranslationService)
            if TranslationService.shared.isTranslationAvailable {
                Button(action: { showTranslateMenu.toggle() }) {
                    Image(systemName: "translate")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Translate message")
                .popover(isPresented: $showTranslateMenu) {
                    TranslatePopover(text: messageContent, themeManager: themeManager)
                }
            }

            // Writing Tools (surfaces WritingToolsService)
            if WritingToolsService.shared.isWritingToolsAvailable {
                Menu {
                    Button("Improve Writing", action: { improveWithWritingTools(.proofread) })
                    Button("Make Concise", action: { improveWithWritingTools(.concise) })
                    Button("Generate Docs", action: { improveWithWritingTools(.documentation) })
                } label: {
                    Image(systemName: "pencil.and.sparkle")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .accessibilityLabel("Writing Tools")
            }
        }
        .opacity(0.6)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: Anim.quick)) {
                // Add hover effect if needed
            }
        }
    }

    private func improveWithWritingTools(_ type: WritingToolsAction) {
        Task {
            do {
                let result: String
                switch type {
                case .proofread:
                    result = try await WritingToolsService.shared.improveText(messageContent, improvement: .grammar)
                case .concise:
                    result = try await WritingToolsService.shared.improveText(messageContent, improvement: .conciseness)
                case .documentation:
                    result = try await WritingToolsService.shared.generateDocumentation(for: messageContent, language: "swift", type: .inline)
                }
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result, forType: .string)
                #endif
            } catch {
                GRumpLogger.capture.error("Writing Tools failed: \(error.localizedDescription)")
            }
        }
    }

    private enum WritingToolsAction {
        case proofread, concise, documentation
    }
}

// MARK: - Translate Popover

struct TranslatePopover: View {
    let text: String
    let themeManager: ThemeManager
    @State private var translatedText = ""
    @State private var selectedLanguage: TranslationLanguage = .spanish
    @State private var isTranslating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Image(systemName: "translate")
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("Translate")
                    .font(Typography.bodySemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
            }
            Picker("To", selection: $selectedLanguage) {
                ForEach(TranslatePopover.availableLanguages) { lang in
                    Text(lang.name).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedLanguage) { _, _ in translateText() }

            if isTranslating {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !translatedText.isEmpty {
                Text(translatedText)
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 360)
        .onAppear { translateText() }
    }

    static let availableLanguages: [TranslationLanguage] = [
        .spanish, .french, .german, .japanese, .chineseSimplified, .korean, .portuguese
    ]

    private func translateText() {
        guard !text.isEmpty else { return }
        isTranslating = true
        Task {
            do {
                translatedText = try await TranslationService.shared.translate(text, to: selectedLanguage)
            } catch {
                translatedText = "Translation unavailable"
            }
            isTranslating = false
        }
    }
}

enum MessageReaction {
    case thumbsUp
    case thumbsDown
}
