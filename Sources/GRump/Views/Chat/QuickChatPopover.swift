import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Quick Chat Popover

/// Floating panel for quick AI interactions from the menu bar.
/// Shares ChatViewModel with main app — same conversation, memory, and tools.
/// Compact mode: single text field + streaming response, no sidebar.
struct QuickChatPopover: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @State private var quickInput: String = ""
    @State private var isExpanded = false
    @FocusState private var inputFocused: Bool

    @AppStorage("QuickChatAutoDismiss") private var autoDismiss = true
    @AppStorage("QuickChatPinned") private var isPinned = false

    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Response area
            if !viewModel.streamingContent.isEmpty || viewModel.isLoading {
                responseArea
                Divider()
            } else if let lastAssistant = lastAssistantMessage {
                lastResponseArea(lastAssistant)
                Divider()
            }

            // Input
            inputArea
        }
        .frame(minHeight: 120, maxHeight: 500)
        .background(themeManager.palette.bgDark)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        .onAppear { inputFocused = true }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "brain.head.profile")
                .font(.caption)
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text("Quick Chat")
                .font(.caption.bold())
                .foregroundColor(themeManager.palette.textPrimary)

            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            }

            Button(action: { isPinned.toggle() }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.caption2)
                    .foregroundColor(isPinned ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin popover" : "Pin popover")

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Response Area

    private var responseArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if viewModel.isLoading && viewModel.streamingContent.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .padding(8)
                } else {
                    Text(viewModel.streamingContent)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(themeManager.palette.textPrimary)
                        .textSelection(.enabled)
                        .padding(8)
                }
            }
        }
        .frame(maxHeight: 300)
    }

    private func lastResponseArea(_ content: String) -> some View {
        ScrollView {
            Text(String(content.suffix(500)))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(themeManager.palette.textPrimary.opacity(0.8))
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $quickInput, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.caption)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundColor(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                     ? themeManager.palette.textMuted
                                     : themeManager.palette.effectiveAccent)
            }
            .buttonStyle(.plain)
            .disabled(quickInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .padding(12)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = quickInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isLoading else { return }

        viewModel.userInput = text
        quickInput = ""

        // Trigger send via the main view model
        Task {
            await viewModel.sendMessage()
        }
    }

    private var lastAssistantMessage: String? {
        viewModel.messages.last(where: { $0.role == .assistant })?.content
    }
}

// MARK: - Quick Chat Window Controller (macOS)

#if os(macOS)
/// Manages the floating NSPanel for QuickChatPopover.
@MainActor
final class QuickChatWindowController: NSObject, ObservableObject {
    static let shared = QuickChatWindowController()

    private var panel: NSPanel?
    @Published var isVisible = false

    private override init() {
        super.init()
    }

    func show(viewModel: ChatViewModel, themeManager: ThemeManager) {
        if let existing = panel, existing.isVisible {
            existing.close()
            isVisible = false
            return
        }

        let popoverView = QuickChatPopover(onDismiss: { [weak self] in
            self?.dismiss()
        })
        .environmentObject(viewModel)
        .environmentObject(themeManager)

        let hostingView = NSHostingView(rootView: popoverView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: 300)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = hostingView
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = true
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isReleasedWhenClosed = false

        // Position near menu bar
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 400
            let y = screenFrame.maxY - 20
            newPanel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
        }

        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
        isVisible = true

        GRumpLogger.general.info("QuickChatPopover shown")
    }

    func dismiss() {
        panel?.close()
        panel = nil
        isVisible = false
    }

    func toggle(viewModel: ChatViewModel, themeManager: ThemeManager) {
        if isVisible {
            dismiss()
        } else {
            show(viewModel: viewModel, themeManager: themeManager)
        }
    }
}
#endif
