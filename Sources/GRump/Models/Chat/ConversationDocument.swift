import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Conversation Document
//
// FileDocument conformance for .grump files — makes conversations
// first-class citizens of the macOS/iOS file system. Users can:
//   - Save conversations as .grump files
//   - Double-click .grump files in Finder to open in G-Rump
//   - Drag conversations from sidebar to Finder
//   - Share via system ShareSheet as Markdown or JSON
//   - Quick Look .grump files without opening the app

// MARK: - Custom UTType

extension UTType {
    static let grumpConversation = UTType(exportedAs: "com.grump.conversation", conformingTo: .json)
}

// MARK: - Transferable Conformance for Conversation

extension Conversation: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // Primary: rich JSON for internal use
        CodableRepresentation(contentType: .grumpConversation)

        // Secondary: plain text Markdown for sharing
        DataRepresentation(exportedContentType: .plainText) { conversation in
            let md = conversation.asMarkdown()
            return Data(md.utf8)
        }
    }
}

// MARK: - Transferable Conformance for Message

extension Message: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        DataRepresentation(exportedContentType: .plainText) { message in
            let text: String
            switch message.role {
            case .user:      text = message.content
            case .assistant: text = message.content
            case .system:    text = "[System] \(message.content)"
            case .tool:      text = "[Tool Result] \(message.content)"
            }
            return Data(text.utf8)
        }
    }
}

// MARK: - Markdown Export Helper

extension Conversation {
    func asMarkdown() -> String {
        var sections: [String] = []
        sections.append("# \(title)")
        sections.append("")
        sections.append("*Created: \(formatted(createdAt)) · \(messages.filter { $0.role != .system }.count) messages*")
        sections.append("")
        sections.append("---")
        sections.append("")

        for message in messages where message.role != .system {
            switch message.role {
            case .user:
                sections.append("## User\n\n\(message.content)")
            case .assistant:
                sections.append("## Assistant\n\n\(message.content)")
            case .tool:
                sections.append("*(Tool result)*\n\n\(message.content)")
            case .system:
                break
            }
            sections.append("")
            sections.append("---")
            sections.append("")
        }
        return sections.joined(separator: "\n")
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - FileDocument for .grump files

struct GRumpConversationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.grumpConversation, .json] }
    static var writableContentTypes: [UTType] { [.grumpConversation] }

    var conversation: Conversation

    init(conversation: Conversation = Conversation(title: "New Chat")) {
        self.conversation = conversation
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.conversation = try JSONDecoder().decode(Conversation.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(conversation)
        return .init(regularFileWithContents: data)
    }
}

// MARK: - ShareSheet Helper (macOS)

#if os(macOS)
enum ShareSheetHelper {

    /// Present a macOS share sheet for a conversation as Markdown.
    static func shareConversation(_ conversation: Conversation, from view: NSView? = nil) {
        let markdown = conversation.asMarkdown()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(conversation.title).md")
        try? markdown.write(to: tempURL, atomically: true, encoding: .utf8)

        let picker = NSSharingServicePicker(items: [tempURL])
        if let anchor = view ?? NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
        }
    }

    /// Present a macOS share sheet for a conversation as a .grump file.
    static func shareConversationAsFile(_ conversation: Conversation, from view: NSView? = nil) {
        let data = try? JSONEncoder().encode(conversation)
        guard let data else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(conversation.title).grump")
        try? data.write(to: tempURL)

        let picker = NSSharingServicePicker(items: [tempURL])
        if let anchor = view ?? NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: anchor, preferredEdge: .minY)
        }
    }
}
#endif

// MARK: - Drag Provider for Sidebar

extension Conversation {
    /// Create an NSItemProvider for drag-and-drop from the sidebar.
    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()

        // Register as .grump file
        if let data = try? JSONEncoder().encode(self) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.grumpConversation.identifier,
                visibility: .all
            ) { completion in
                completion(data, nil)
                return nil
            }
        }

        // Also register as plain text (Markdown)
        let markdown = self.asMarkdown()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(markdown.utf8), nil)
            return nil
        }

        provider.suggestedName = "\(title).grump"
        return provider
    }
}
