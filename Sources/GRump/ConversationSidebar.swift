import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

private extension String {
    /// Safe for use as a filename (alphanumeric, hyphen, underscore).
    var sanitizedForFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let s = unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "conversation" : String(trimmed.prefix(80))
    }
}

private struct IdentifiableConversationWrapper: Identifiable {
    let conversation: Conversation
    var id: UUID { conversation.id }
}

struct ConversationSidebar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSettings: Bool
    @Binding var showProfile: Bool
    var onOpenFolder: () -> Void
    @State private var conversationToRename: IdentifiableConversationWrapper?
    @State private var conversationToDelete: IdentifiableConversationWrapper?
    @State private var newChatButtonHovered = false
    @State private var collapsedSections: Set<String> = []

    private var filteredConversations: [Conversation] {
        viewModel.conversations
    }

    private func groupLabel(for date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now),
           date >= sevenDaysAgo { return "Last 7 Days" }
        if let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now),
           date >= thirtyDaysAgo { return "Last 30 Days" }
        // Monthly bucket: "January 2026"
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    private var groupedConversations: [(String, [Conversation])] {
        let grouped = Dictionary(grouping: filteredConversations) { groupLabel(for: $0.createdAt) }
        let fixedOrder = ["Today", "Yesterday", "Last 7 Days", "Last 30 Days"]
        var result: [(String, [Conversation])] = []
        for key in fixedOrder {
            if let items = grouped[key], !items.isEmpty {
                result.append((key, items))
            }
        }
        let monthKeys = grouped.keys.filter { !fixedOrder.contains($0) }
            .sorted { a, b in
                let dateA = grouped[a]?.first?.createdAt ?? .distantPast
                let dateB = grouped[b]?.first?.createdAt ?? .distantPast
                return dateA > dateB
            }
        for key in monthKeys {
            if let items = grouped[key], !items.isEmpty {
                result.append((key, items))
            }
        }
        return result
    }

    private func isSectionCollapsed(_ label: String) -> Bool {
        collapsedSections.contains(label)
    }

    private func toggleSection(_ label: String) {
        withAnimation(.easeInOut(duration: Anim.quick)) {
            if collapsedSections.contains(label) {
                collapsedSections.remove(label)
            } else {
                collapsedSections.insert(label)
            }
        }
    }

    private var sidebarHeader: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.xl) {
                    FrownyFaceLogo(size: 28)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("G-Rump")
                            .font(Typography.sidebarTitle)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text("AI Coding Agent")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, Spacing.xxxl * themeManager.density.scaleFactor)
            .padding(.vertical, Spacing.xxxl * themeManager.density.scaleFactor)
            .background(themeManager.palette.bgSidebar)

            Rectangle()
                .fill(themeManager.palette.borderCrisp)
                .frame(height: Border.thin)

            HStack(spacing: Spacing.lg) {
                Button(action: { viewModel.createNewConversation() }) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "square.and.pencil")
                            .font(Typography.bodyMedium)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        Text("New chat")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(newChatButtonHovered ? themeManager.palette.effectiveAccent.opacity(0.08) : themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                        .stroke(newChatButtonHovered ? themeManager.palette.effectiveAccent.opacity(0.4) : themeManager.palette.borderCrisp, lineWidth: Border.thin))
                }
                .buttonStyle(.plain)
                .onHover { newChatButtonHovered = $0 }
                .animation(.easeInOut(duration: Anim.quick), value: newChatButtonHovered)
                .help("New Chat (⌘N)")
                .accessibilityLabel("New chat")
            }
            .padding(.horizontal, Spacing.xl * themeManager.density.scaleFactor)
            .padding(.vertical, Spacing.xl * themeManager.density.scaleFactor)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)
        }
    }

    private var conversationListView: some View {
        Group {
            if filteredConversations.isEmpty {
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        Text("No conversations yet")
                            .font(Typography.bodySmall)
                            .foregroundColor(themeManager.palette.textMuted)
                        Text("⌘N")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.colossal)
                }
            } else {
                List {
                    ForEach(filteredConversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: viewModel.currentConversation?.id == conversation.id,
                            onSelect: { viewModel.selectConversation(conversation) },
                            onDelete: { conversationToDelete = IdentifiableConversationWrapper(conversation: conversation) },
                            onRename: { conversationToRename = IdentifiableConversationWrapper(conversation: conversation) },
                            onDuplicate: { viewModel.duplicateConversation(conversation) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: Spacing.lg, bottom: 1, trailing: Spacing.lg))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                conversationToDelete = IdentifiableConversationWrapper(conversation: conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var sidebarBottomBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(themeManager.palette.borderCrisp).frame(height: Border.thin)

            Button(action: onOpenFolder) {
                HStack(spacing: Spacing.xl) {
                    Image(systemName: "folder.badge.plus")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open folder")
                            .font(Typography.bodySmallMedium)
                            .foregroundColor(themeManager.palette.textSecondary)
                        if !viewModel.workingDirectory.isEmpty {
                            Text((viewModel.workingDirectory as NSString).lastPathComponent)
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.xxl)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open folder")
            .help("Select project folder to work in")

            Button(action: { showProfile = true }) {
                HStack(spacing: Spacing.xl) {
                    Image(systemName: "person.crop.circle")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("Profile")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                    if let user = viewModel.platformUser {
                        Text("\(user.creditsBalance)")
                            .font(Typography.micro)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.effectiveAccent.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.xxl)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
            .help("Open Profile")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            conversationListView
            sidebarBottomBar
        }
        .background(themeManager.palette.bgSidebar)
        .confirmationDialog(
            "Delete \"\(conversationToDelete?.conversation.title ?? "")\"?",
            isPresented: Binding(
                get: { conversationToDelete != nil },
                set: { if !$0 { conversationToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let wrapper = conversationToDelete {
                    viewModel.deleteConversation(wrapper.conversation)
                }
                conversationToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
        } message: {
            Text("This conversation and all its messages will be permanently deleted.")
        }
        .sheet(item: $conversationToRename) { wrapper in
            RenameConversationSheet(
                conversation: wrapper.conversation,
                viewModel: viewModel,
                onDismiss: { conversationToRename = nil }
            )
        }
        .overlay(alignment: .top) {
            if let msg = viewModel.importExportMessage {
                    Text(msg)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(themeManager.palette.bgCard)
                    .padding(Spacing.md)
                    .onTapGesture { viewModel.importExportMessage = nil }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        viewModel.importExportMessage = nil
                    }
            }
        }
    }

}

// MARK: - Conversation Row

struct ConversationRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let conversation: Conversation
    let isSelected: Bool
    var onSelect: (() -> Void)? = nil
    let onDelete: () -> Void
    let onRename: () -> Void
    var onDuplicate: (() -> Void)? = nil
    @State private var isHovered = false

    var messageCount: Int { conversation.messages.count }

    private var lastMessagePreview: String? {
        // Walk backwards to find last user/assistant message — avoids full array scan
        for msg in conversation.messages.reversed() {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            return String(content.replacingOccurrences(of: "\n", with: " ").prefix(80))
        }
        return nil
    }

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(isSelected ? themeManager.palette.effectiveAccent : Color.clear)
                    .frame(width: 2, height: 18)

                Text(conversation.title)
                    .font(isSelected ? Typography.bodySmallSemibold : Typography.bodySmall)
                    .foregroundColor(isSelected ? themeManager.palette.textPrimary : themeManager.palette.textSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(
                    isSelected
                        ? themeManager.palette.effectiveAccent.opacity(0.10)
                        : (isHovered ? themeManager.palette.bgInput.opacity(0.5) : Color.clear)
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
        .contextMenu {
            Button(action: onRename) {
                Label("Rename…", systemImage: "pencil")
            }
            if let duplicate = onDuplicate {
                Button(action: duplicate) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(action: { exportAsMarkdown(conversation) }) {
                Label("Export as Markdown", systemImage: "doc.text")
            }
            Button(action: { exportAsGrumpFile(conversation) }) {
                Label("Export as .grump", systemImage: "doc.zipper")
            }
            #if os(macOS)
            Button(action: { ShareSheetHelper.shareConversation(conversation) }) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            #endif

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete Conversation", systemImage: "trash")
            }
        }
        .onDrag { conversation.itemProvider }
    }

    // MARK: - Export Helpers

    private func exportAsMarkdown(_ conversation: Conversation) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(conversation.title).md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                let md = conversation.asMarkdown()
                try? md.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }

    private func exportAsGrumpFile(_ conversation: Conversation) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(conversation.title).grump"
        panel.allowedContentTypes = [.grumpConversation]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                if let data = try? JSONEncoder().encode(conversation) {
                    try? data.write(to: url)
                }
            }
        }
        #endif
    }
}

// MARK: - Rename Conversation Sheet

private struct RenameConversationSheet: View {
    let conversation: Conversation
    @ObservedObject var viewModel: ChatViewModel
    var onDismiss: () -> Void
    @State private var title: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    init(conversation: Conversation, viewModel: ChatViewModel, onDismiss: @escaping () -> Void) {
        self.conversation = conversation
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _title = State(initialValue: conversation.title)
    }

    var body: some View {
        VStack(spacing: Spacing.huge) {
            Text("Rename conversation")
                .font(Typography.heading2)
                .foregroundColor(themeManager.palette.textPrimary)

            TextField("Title", text: $title)
                .font(Typography.body)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitRename() }

            HStack(spacing: Spacing.lg) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    submitRename()
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.colossal)
        .frame(minWidth: 320)
        .background(themeManager.palette.bgDark)
    }

    private func submitRename() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        viewModel.renameConversation(conversation, to: t)
    }
}
