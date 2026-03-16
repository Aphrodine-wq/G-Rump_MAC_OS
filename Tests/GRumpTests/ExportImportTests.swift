import XCTest
@testable import GRump

/// Tests for the conversation export/import functionality.
/// Validates Markdown string generation, JSON round-trip, and filename sanitization.
final class ExportImportTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a Conversation with the given messages for testing.
    private func makeConversation(
        title: String = "Test Chat",
        messages: [(Message.Role, String)]
    ) -> Conversation {
        Conversation(
            title: title,
            messages: messages.map { Message(role: $0.0, content: $0.1) }
        )
    }

    // MARK: - Markdown String Generation

    @MainActor
    func testMarkdownString_userAndAssistant() {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [
            (.user, "What is Swift?"),
            (.assistant, "Swift is a programming language."),
        ])
        let md = vm.markdownString(for: conv)
        XCTAssertTrue(md.contains("## User"))
        XCTAssertTrue(md.contains("What is Swift?"))
        XCTAssertTrue(md.contains("## Assistant"))
        XCTAssertTrue(md.contains("Swift is a programming language."))
    }

    @MainActor
    func testMarkdownString_excludesSystemMessages() {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [
            (.system, "You are a helper."),
            (.user, "Hello"),
        ])
        let md = vm.markdownString(for: conv)
        XCTAssertFalse(md.contains("You are a helper."))
        XCTAssertTrue(md.contains("Hello"))
    }

    @MainActor
    func testMarkdownString_includesToolResults() {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [
            (.user, "Read file"),
            (.tool, "File contents here"),
        ])
        let md = vm.markdownString(for: conv)
        XCTAssertTrue(md.contains("*(Tool result)*"))
        XCTAssertTrue(md.contains("File contents here"))
    }

    @MainActor
    func testMarkdownString_emptyConversation() {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [])
        let md = vm.markdownString(for: conv)
        XCTAssertTrue(md.isEmpty)
    }

    @MainActor
    func testMarkdownString_separatesWithHorizontalRule() {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [
            (.user, "First"),
            (.assistant, "Second"),
        ])
        let md = vm.markdownString(for: conv)
        XCTAssertTrue(md.contains("---"))
    }

    // MARK: - JSON Round-Trip

    func testConversationCodableRoundTrip() throws {
        let conv = makeConversation(messages: [
            (.user, "Hello"),
            (.assistant, "Hi there"),
        ])
        let data = try JSONEncoder().encode([conv])
        let decoded = try JSONDecoder().decode([Conversation].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].title, "Test Chat")
        XCTAssertEqual(decoded[0].messages.count, 2)
        XCTAssertEqual(decoded[0].messages[0].content, "Hello")
        XCTAssertEqual(decoded[0].messages[1].content, "Hi there")
    }

    func testMultipleConversationCodableRoundTrip() throws {
        let convs = [
            makeConversation(title: "Chat 1", messages: [(.user, "A")]),
            makeConversation(title: "Chat 2", messages: [(.user, "B")]),
        ]
        let data = try JSONEncoder().encode(convs)
        let decoded = try JSONDecoder().decode([Conversation].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].title, "Chat 1")
        XCTAssertEqual(decoded[1].title, "Chat 2")
    }

    // MARK: - Export to File

    @MainActor
    func testExportConversationsAsJSON_writesToFile() throws {
        let vm = ChatViewModel()
        let conv = makeConversation(messages: [(.user, "Exported")])
        vm.conversations = [conv]

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        vm.exportConversations(to: tmp, conversationIds: nil)

        let data = try Data(contentsOf: tmp)
        let decoded = try JSONDecoder().decode([Conversation].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].messages[0].content, "Exported")
    }

    @MainActor
    func testExportConversationsAsMarkdown_writesToFile() throws {
        let vm = ChatViewModel()
        let conv = makeConversation(title: "My Chat", messages: [
            (.user, "Question"),
            (.assistant, "Answer"),
        ])
        vm.conversations = [conv]

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: tmp) }

        vm.exportConversationsAsMarkdown(to: tmp, conversationIds: nil)

        let content = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(content.contains("# My Chat"))
        XCTAssertTrue(content.contains("## User"))
        XCTAssertTrue(content.contains("Question"))
    }

    // MARK: - Import from File

    @MainActor
    func testImportConversations_appendsToExisting() throws {
        let vm = ChatViewModel()
        vm.conversations = [makeConversation(title: "Existing", messages: [(.user, "A")])]

        let importData = [makeConversation(title: "Imported", messages: [(.user, "B")])]
        let data = try JSONEncoder().encode(importData)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp)

        vm.importConversations(from: tmp)

        XCTAssertEqual(vm.conversations.count, 2)
        XCTAssertEqual(vm.importExportMessage, "Imported 1 conversation.")
    }

    @MainActor
    func testImportConversations_invalidJSON_setsErrorMessage() {
        let vm = ChatViewModel()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try? "not json".data(using: .utf8)?.write(to: tmp)
        vm.importConversations(from: tmp)

        XCTAssertNotNil(vm.importExportMessage)
        XCTAssertTrue(vm.importExportMessage?.contains("Import failed") ?? false)
    }

    // MARK: - Filename Sanitization

    #if os(macOS)
    func testFilenameGRumpSanitization_basicString() {
        let sanitized = "Hello World".grumpSanitizedForFilename
        XCTAssertEqual(sanitized, "Hello-World")
    }

    func testFilenameGRumpSanitization_specialCharacters() {
        let sanitized = "What's <this>?".grumpSanitizedForFilename
        XCTAssertFalse(sanitized.contains("<"))
        XCTAssertFalse(sanitized.contains(">"))
        XCTAssertFalse(sanitized.contains("'"))
    }

    func testFilenameGRumpSanitization_emptyString() {
        let sanitized = "".grumpSanitizedForFilename
        XCTAssertEqual(sanitized, "conversation")
    }

    func testFilenameGRumpSanitization_longString() {
        let long = String(repeating: "a", count: 200)
        let sanitized = long.grumpSanitizedForFilename
        XCTAssertLessThanOrEqual(sanitized.count, 80)
    }
    #endif
}
