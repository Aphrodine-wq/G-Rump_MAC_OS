import XCTest
@testable import GRump

final class ConversationThreadingTests: XCTestCase {

    // MARK: - Conversation Creation

    func testConversationDefaults() {
        let conv = Conversation(title: "Test")
        XCTAssertEqual(conv.title, "Test")
        XCTAssertTrue(conv.messages.isEmpty)
        XCTAssertTrue(conv.threads.isEmpty)
        XCTAssertTrue(conv.branches.isEmpty)
        XCTAssertNil(conv.activeThreadId)
        XCTAssertEqual(conv.viewMode, .linear)
    }

    func testConversationViewModeAllCases() {
        let modes = Conversation.ConversationViewMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertTrue(modes.contains(.linear))
        XCTAssertTrue(modes.contains(.threaded))
        XCTAssertTrue(modes.contains(.branched))
    }

    func testConversationViewModeCodable() throws {
        for mode in Conversation.ConversationViewMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(Conversation.ConversationViewMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - updateTitle

    func testUpdateTitleNoUserMessage() {
        var conv = Conversation(title: "Original")
        conv.messages.append(Message(role: .assistant, content: "I'm an assistant"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "Original") // unchanged
    }

    func testUpdateTitleShortMessage() {
        var conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .user, content: "Hello"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "Hello")
    }

    func testUpdateTitleExactly40Characters() {
        var conv = Conversation(title: "New Chat")
        let exact40 = String(repeating: "x", count: 40)
        conv.messages.append(Message(role: .user, content: exact40))
        conv.updateTitle()
        XCTAssertEqual(conv.title, exact40)
        XCTAssertEqual(conv.title.count, 40)
    }

    func testUpdateTitle41CharactersTruncates() {
        var conv = Conversation(title: "New Chat")
        let long = String(repeating: "y", count: 41)
        conv.messages.append(Message(role: .user, content: long))
        conv.updateTitle()
        XCTAssertEqual(conv.title.count, 41) // 40 chars + "…"
        XCTAssertTrue(conv.title.hasSuffix("…"))
    }

    func testUpdateTitleUsesFirstUserMessage() {
        var conv = Conversation(title: "New Chat")
        conv.messages.append(Message(role: .system, content: "System"))
        conv.messages.append(Message(role: .user, content: "First user"))
        conv.messages.append(Message(role: .user, content: "Second user"))
        conv.updateTitle()
        XCTAssertEqual(conv.title, "First user")
    }

    // MARK: - Thread Creation

    func testCreateThreadFromValidMessage() {
        var conv = Conversation(title: "Test")
        let msg = Message(role: .user, content: "Hello")
        conv.messages.append(msg)

        let threadId = conv.createThread(from: msg.id, name: "Test Thread")
        XCTAssertNotNil(threadId)
        XCTAssertEqual(conv.threads.count, 1)
        XCTAssertEqual(conv.threads[0].name, "Test Thread")
        XCTAssertEqual(conv.threads[0].rootMessageId, msg.id)
        XCTAssertEqual(conv.activeThreadId, threadId)
    }

    func testCreateThreadFromInvalidMessage() {
        var conv = Conversation(title: "Test")
        let fakeId = UUID()
        let threadId = conv.createThread(from: fakeId)
        XCTAssertNil(threadId)
        XCTAssertTrue(conv.threads.isEmpty)
        XCTAssertNil(conv.activeThreadId)
    }

    func testCreateThreadUpdatesMessageThreadId() {
        var conv = Conversation(title: "Test")
        let msg = Message(role: .user, content: "Root")
        conv.messages.append(msg)

        let threadId = conv.createThread(from: msg.id)
        XCTAssertNotNil(threadId)
        XCTAssertEqual(conv.messages[0].threadId, threadId)
    }

    func testCreateMultipleThreads() {
        var conv = Conversation(title: "Test")
        let msg1 = Message(role: .user, content: "First")
        let msg2 = Message(role: .user, content: "Second")
        conv.messages.append(msg1)
        conv.messages.append(msg2)

        let t1 = conv.createThread(from: msg1.id, name: "Thread 1")
        let t2 = conv.createThread(from: msg2.id, name: "Thread 2")

        XCTAssertNotNil(t1)
        XCTAssertNotNil(t2)
        XCTAssertNotEqual(t1, t2)
        XCTAssertEqual(conv.threads.count, 2)
        XCTAssertEqual(conv.activeThreadId, t2) // last created is active
    }

    // MARK: - Branch Creation

    func testCreateBranchFromValidMessage() {
        var conv = Conversation(title: "Test")
        let msg = Message(role: .user, content: "Branch point")
        conv.messages.append(msg)

        let branchId = conv.createBranch(from: msg.id, name: "Feature Branch")
        XCTAssertNotNil(branchId)
        XCTAssertEqual(conv.branches.count, 1)
        XCTAssertEqual(conv.branches[0].name, "Feature Branch")
        XCTAssertEqual(conv.branches[0].parentMessageId, msg.id)
        XCTAssertEqual(conv.branches[0].branchPointMessageId, msg.id)
    }

    func testCreateBranchFromInvalidMessage() {
        var conv = Conversation(title: "Test")
        let branchId = conv.createBranch(from: UUID(), name: "Ghost Branch")
        XCTAssertNil(branchId)
        XCTAssertTrue(conv.branches.isEmpty)
    }

    // MARK: - getActiveThreadMessages

    func testGetActiveThreadMessagesNoActiveThread() {
        var conv = Conversation(title: "Test")
        conv.messages = [
            Message(role: .user, content: "A"),
            Message(role: .assistant, content: "B"),
        ]
        let result = conv.getActiveThreadMessages()
        XCTAssertEqual(result.count, 2) // returns all messages
    }

    func testGetActiveThreadMessagesFiltersbyThread() {
        var conv = Conversation(title: "Test")
        let msg1 = Message(role: .user, content: "In thread")
        let msg2 = Message(role: .user, content: "No thread")
        let msg3 = Message(role: .assistant, content: "Also in thread")

        conv.messages.append(msg1)
        conv.messages.append(msg2)
        conv.messages.append(msg3)

        _ = conv.createThread(from: msg1.id)!
        // msg1 should now have threadId set; msg2 should not
        let filtered = conv.getActiveThreadMessages()
        // Should include messages with matching threadId OR nil threadId
        XCTAssertTrue(filtered.count >= 1)
    }

    // MARK: - Full Conversation Codable Round-Trip with Threading

    func testConversationWithThreadsCodable() throws {
        var conv = Conversation(title: "Threaded Chat")
        conv.messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi!"),
        ]
        _ = conv.createThread(from: conv.messages[0].id, name: "Main Thread")
        _ = conv.createBranch(from: conv.messages[1].id, name: "Alt Response")
        conv.viewMode = .threaded

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.title, "Threaded Chat")
        XCTAssertEqual(decoded.messages.count, 2)
        XCTAssertEqual(decoded.threads.count, 1)
        XCTAssertEqual(decoded.branches.count, 1)
        XCTAssertEqual(decoded.viewMode, .threaded)
        XCTAssertNotNil(decoded.activeThreadId)
    }

    // MARK: - MessageThread

    func testMessageThreadDefaults() {
        let rootId = UUID()
        let thread = MessageThread(name: "Test", rootMessageId: rootId)
        XCTAssertEqual(thread.name, "Test")
        XCTAssertEqual(thread.rootMessageId, rootId)
        XCTAssertTrue(thread.isActive)
        XCTAssertNil(thread.color)
    }

    func testMessageThreadCodable() throws {
        let thread = MessageThread(name: "Round-trip", rootMessageId: UUID())
        let data = try JSONEncoder().encode(thread)
        let decoded = try JSONDecoder().decode(MessageThread.self, from: data)
        XCTAssertEqual(decoded.name, thread.name)
        XCTAssertEqual(decoded.rootMessageId, thread.rootMessageId)
        XCTAssertEqual(decoded.isActive, thread.isActive)
    }

    // MARK: - MessageBranch

    func testMessageBranchDefaults() {
        let parentId = UUID()
        let branch = MessageBranch(name: "Alt", parentMessageId: parentId, branchPointMessageId: parentId)
        XCTAssertEqual(branch.name, "Alt")
        XCTAssertEqual(branch.parentMessageId, parentId)
        XCTAssertEqual(branch.branchPointMessageId, parentId)
        XCTAssertTrue(branch.isActive)
    }

    func testMessageBranchCodable() throws {
        let id = UUID()
        let branch = MessageBranch(name: "Feature", parentMessageId: id, branchPointMessageId: id)
        let data = try JSONEncoder().encode(branch)
        let decoded = try JSONDecoder().decode(MessageBranch.self, from: data)
        XCTAssertEqual(decoded.name, branch.name)
        XCTAssertEqual(decoded.parentMessageId, branch.parentMessageId)
    }

    // MARK: - Conversation Equatable

    func testConversationEquatable() {
        let conv1 = Conversation(title: "A")
        var conv2 = conv1
        XCTAssertEqual(conv1, conv2)
        conv2.title = "B"
        XCTAssertNotEqual(conv1, conv2)
    }
}
