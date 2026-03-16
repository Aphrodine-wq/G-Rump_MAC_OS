import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

// MARK: - Export / Import Extension
//
// Contains conversation export (JSON, Markdown) and import functionality.
// Extracted from ChatViewModel.swift for maintainability.

extension ChatViewModel {

    // MARK: - Export / Import

    /// Returns a Markdown string for a single conversation (User/Assistant sections, code blocks preserved).
    func markdownString(for conversation: Conversation) -> String {
        var sections: [String] = []
        for message in conversation.messages where message.role != .system {
            switch message.role {
            case .user:
                sections.append("## User\n\n" + message.content)
            case .assistant:
                sections.append("## Assistant\n\n" + message.content)
            case .tool:
                sections.append("*(Tool result)*\n\n" + message.content)
            case .system:
                break
            }
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    #if os(macOS)
    /// Presents the save panel and exports conversations as JSON. Call from main thread.
    func runExportJSONPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "g-rump-conversations.json"
        panel.message = "Export conversations as JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportConversations(to: url, conversationIds: nil)
    }

    /// Presents the save panel and exports conversations as Markdown. If onlyCurrent is true, exports only the current conversation. Call from main thread.
    func runExportMarkdownPanel(onlyCurrent: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let defaultName = onlyCurrent ? ((currentConversation?.title ?? "conversation").grumpSanitizedForFilename + ".md") : "g-rump-conversations.md"
        panel.nameFieldStringValue = defaultName
        panel.message = onlyCurrent ? "Export current conversation as Markdown" : "Export conversations as Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ids = onlyCurrent ? currentConversation.map { Set([$0.id]) } : nil
        exportConversationsAsMarkdown(to: url, conversationIds: ids)
    }

    /// Presents the open panel and imports conversations from JSON. Call from main thread.
    func runImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a conversations JSON file to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importConversations(from: url)
    }
    #endif

    /// Exports one or more conversations as a single Markdown file.
    func exportConversationsAsMarkdown(to url: URL, conversationIds: Set<UUID>?) {
        let list = conversationIds.map { ids in conversations.filter { ids.contains($0.id) } } ?? conversations
        let parts = list.map { conv in
            "# \(conv.title)\n\n" + markdownString(for: conv)
        }
        let markdown = parts.joined(separator: "\n\n---\n\n")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            importExportMessage = "Exported \(list.count) conversation\(list.count == 1 ? "" : "s") as Markdown."
        } catch {
            GRumpLogger.general.error("Export as Markdown failed: \(error.localizedDescription)")
            importExportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportConversations(to url: URL, conversationIds: Set<UUID>?) {
        let list = conversationIds.map { ids in conversations.filter { ids.contains($0.id) } } ?? conversations
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: url, options: .atomic)
        } catch {
            GRumpLogger.general.error("Export failed: \(error.localizedDescription)")
        }
    }

    func importConversations(from url: URL) {
        importExportMessage = nil
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([Conversation].self, from: data)
            let count = imported.count
            conversations.append(contentsOf: imported)
            saveConversations()
            importExportMessage = "Imported \(count) conversation\(count == 1 ? "" : "s")."
        } catch {
            importExportMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

#if os(macOS)
extension String {
    var grumpSanitizedForFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let s = unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "conversation" : String(trimmed.prefix(80))
    }
}
#endif
