import XCTest
@testable import GRump

final class ModelsTests: XCTestCase {

    func testMessageCodableRoundTrip() throws {
        let msg = Message(role: .user, content: "Hello", timestamp: Date())
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.role, msg.role)
        XCTAssertEqual(decoded.content, msg.content)
    }

    func testConversationCodableRoundTrip() throws {
        var conv = Conversation(title: "Test")
        conv.messages = [
            Message(role: .user, content: "Hi"),
            Message(role: .assistant, content: "Hello!"),
        ]
        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)
        XCTAssertEqual(decoded.title, conv.title)
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.messages[0].content, "Hi")
        XCTAssertEqual(decoded.messages[1].content, "Hello!")
    }

    func testConversationUpdateTitle() {
        var conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .user, content: "What is Swift?"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "What is Swift?")
    }

    func testConversationUpdateTitleTruncates() {
        var conv = Conversation(title: "New Chat")
        let long = String(repeating: "a", count: 50)
        conv.messages.append(Message(role: .user, content: long))
        conv.updateTitle()
        XCTAssertEqual(conv.title.count, 41)
        XCTAssertTrue(conv.title.hasSuffix("…"))
    }
}
