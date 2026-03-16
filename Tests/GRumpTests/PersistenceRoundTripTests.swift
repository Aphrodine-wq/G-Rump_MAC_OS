import XCTest
@testable import GRump

/// Tests for conversation persistence (save/load round-trip).
/// Validates that conversations survive a write-to-disk and read-back cycle
/// with full message fidelity.
@MainActor
final class PersistenceRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func makeConversation(
        title: String = "Test",
        messages: [(Message.Role, String)] = [(.user, "Hello"), (.assistant, "Hi")]
    ) -> Conversation {
        Conversation(
            title: title,
            messages: messages.map { Message(role: $0.0, content: $0.1) }
        )
    }

    // MARK: - Conversations File URL

    func testConversationsFileURL_isInApplicationSupport() {
        let url = ChatViewModel.conversationsFileURL
        XCTAssertTrue(url.path.contains("Application Support"))
        XCTAssertTrue(url.lastPathComponent == "conversations.json")
    }

    func testConversationsFileURL_createsDirectory() {
        let url = ChatViewModel.conversationsFileURL
        let dir = url.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    // MARK: - JSON Encode/Decode Round-Trip

    func testConversationCodable_roundTrip() throws {
        let original = makeConversation(title: "Round Trip", messages: [
            (.user, "What is 2+2?"),
            (.assistant, "4"),
            (.user, "Thanks"),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.messages.count, original.messages.count)
        for (orig, dec) in zip(original.messages, decoded.messages) {
            XCTAssertEqual(orig.role, dec.role)
            XCTAssertEqual(orig.content, dec.content)
        }
    }

    func testConversationCodable_preservesThreadingFields() throws {
        var conv = makeConversation()
        let threadId = conv.createThread(from: conv.messages[0].id, name: "Test Thread")
        XCTAssertNotNil(threadId)

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.threads.count, 1)
        XCTAssertEqual(decoded.threads[0].name, "Test Thread")
        XCTAssertEqual(decoded.activeThreadId, threadId)
    }

    func testConversationCodable_preservesBranches() throws {
        var conv = makeConversation()
        let branchId = conv.createBranch(from: conv.messages[0].id, name: "Alt Path")
        XCTAssertNotNil(branchId)

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.branches.count, 1)
        XCTAssertEqual(decoded.branches[0].name, "Alt Path")
    }

    // MARK: - Message Field Fidelity

    func testMessage_preservesToolCallId() throws {
        var msg = Message(role: .tool, content: "result")
        msg.toolCallId = "call_abc123"

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.toolCallId, "call_abc123")
    }

    func testMessage_preservesToolCalls() throws {
        var msg = Message(role: .assistant, content: "")
        msg.toolCalls = [ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"/tmp/test\"}")]

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        XCTAssertEqual(decoded.toolCalls?.count, 1)
        XCTAssertEqual(decoded.toolCalls?[0].name, "read_file")
        XCTAssertEqual(decoded.toolCalls?[0].arguments, "{\"path\":\"/tmp/test\"}")
    }

    func testMessage_preservesTimestamp() throws {
        let msg = Message(role: .user, content: "timestamped")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)

        // Timestamps should be within 1 second
        XCTAssertEqual(msg.timestamp.timeIntervalSince1970,
                       decoded.timestamp.timeIntervalSince1970,
                       accuracy: 1.0)
    }

    // MARK: - Multiple Conversations

    func testMultipleConversations_roundTrip() throws {
        let convs = [
            makeConversation(title: "Chat 1", messages: [(.user, "Hello")]),
            makeConversation(title: "Chat 2", messages: [(.user, "World")]),
            makeConversation(title: "Chat 3", messages: [(.assistant, "!")]),
        ]
        let data = try JSONEncoder().encode(convs)
        let decoded = try JSONDecoder().decode([Conversation].self, from: data)

        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].title, "Chat 1")
        XCTAssertEqual(decoded[1].title, "Chat 2")
        XCTAssertEqual(decoded[2].title, "Chat 3")
    }

    // MARK: - Edge Cases

    func testEmptyConversation_roundTrip() throws {
        let conv = Conversation(title: "Empty")
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, "Empty")
        XCTAssertTrue(decoded.messages.isEmpty)
    }

    func testConversation_withUnicodeContent() throws {
        let conv = makeConversation(title: "Emoji Test 🎉", messages: [
            (.user, "Write Swift 🦅"),
            (.assistant, "Here's some code: let π = 3.14159"),
        ])
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, "Emoji Test 🎉")
        XCTAssertEqual(decoded.messages[0].content, "Write Swift 🦅")
        XCTAssertTrue(decoded.messages[1].content.contains("π"))
    }

    func testConversation_viewModeCodable() throws {
        var conv = makeConversation()
        conv.viewMode = .threaded
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.viewMode, .threaded)
    }

    func testConversation_titleTruncation() {
        var conv = makeConversation(title: "Original", messages: [
            (.user, "This is a very long message that should be truncated to 40 characters for the title"),
        ])
        conv.updateTitle()
        XCTAssertLessThanOrEqual(conv.title.count, 41) // 40 chars + "…"
        XCTAssertTrue(conv.title.hasSuffix("…"))
    }

    func testConversation_shortTitleNotTruncated() {
        var conv = makeConversation(title: "Original", messages: [
            (.user, "Short message"),
        ])
        conv.updateTitle()
        XCTAssertEqual(conv.title, "Short message")
    }
}
