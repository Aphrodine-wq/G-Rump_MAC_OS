import XCTest
import UniformTypeIdentifiers
@testable import GRump

final class ConversationDocumentTests: XCTestCase {

    // MARK: - UTType

    func testGrumpUTTypeExists() {
        let uttype = UTType.grumpConversation
        XCTAssertEqual(uttype.identifier, "com.grump.conversation")
    }

    // MARK: - Markdown Export

    func testEmptyConversationMarkdown() {
        let conv = Conversation(title: "Test Chat")
        let md = conv.asMarkdown()
        XCTAssertTrue(md.contains("# Test Chat"))
        XCTAssertTrue(md.contains("0 messages"))
    }

    func testConversationWithMessagesMarkdown() {
        var conv = Conversation(title: "Dev Chat")
        conv.messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]
        let md = conv.asMarkdown()
        XCTAssertTrue(md.contains("# Dev Chat"))
        XCTAssertTrue(md.contains("## User"))
        XCTAssertTrue(md.contains("Hello"))
        XCTAssertTrue(md.contains("## Assistant"))
        XCTAssertTrue(md.contains("Hi there!"))
        XCTAssertTrue(md.contains("2 messages"))
    }

    func testMarkdownExcludesSystemMessages() {
        var conv = Conversation(title: "Chat")
        conv.messages = [
            Message(role: .system, content: "You are helpful."),
            Message(role: .user, content: "Hi"),
        ]
        let md = conv.asMarkdown()
        XCTAssertFalse(md.contains("You are helpful."))
        XCTAssertTrue(md.contains("Hi"))
        XCTAssertTrue(md.contains("1 messages"))
    }

    func testMarkdownIncludesToolResults() {
        var conv = Conversation(title: "Tools")
        conv.messages = [
            Message(role: .user, content: "Run tests"),
            Message(role: .tool, content: "All tests passed"),
        ]
        let md = conv.asMarkdown()
        XCTAssertTrue(md.contains("Tool result"))
        XCTAssertTrue(md.contains("All tests passed"))
    }

    func testMarkdownContainsSeparators() {
        var conv = Conversation(title: "Sep Test")
        conv.messages = [
            Message(role: .user, content: "msg1"),
            Message(role: .assistant, content: "msg2"),
        ]
        let md = conv.asMarkdown()
        XCTAssertTrue(md.contains("---"))
    }

    // MARK: - GRumpConversationDocument

    func testDocumentDefaultInit() {
        let doc = GRumpConversationDocument()
        XCTAssertEqual(doc.conversation.title, "New Chat")
    }

    func testDocumentWithConversation() {
        let conv = Conversation(title: "My Chat")
        let doc = GRumpConversationDocument(conversation: conv)
        XCTAssertEqual(doc.conversation.title, "My Chat")
    }

    func testDocumentReadableContentTypes() {
        let types = GRumpConversationDocument.readableContentTypes
        XCTAssertTrue(types.contains(.grumpConversation))
        XCTAssertTrue(types.contains(.json))
    }

    func testDocumentWritableContentTypes() {
        let types = GRumpConversationDocument.writableContentTypes
        XCTAssertTrue(types.contains(.grumpConversation))
    }

    func testConversationJSONRoundtrip() throws {
        var conv = Conversation(title: "Roundtrip")
        conv.messages = [
            Message(role: .user, content: "Test message"),
        ]
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, "Roundtrip")
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages.first?.content, "Test message")
    }

    func testConversationDecodeFromData() throws {
        var conv = Conversation(title: "From Data")
        conv.messages = [Message(role: .assistant, content: "Hello")]
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, "From Data")
        XCTAssertEqual(decoded.messages.count, 1)
        XCTAssertEqual(decoded.messages.first?.role, .assistant)
    }

    // MARK: - Conversation Item Provider

    func testConversationItemProvider() {
        let conv = Conversation(title: "Drag Test")
        let provider = conv.itemProvider
        XCTAssertNotNil(provider)
        XCTAssertEqual(provider.suggestedName, "Drag Test.grump")
    }
}
