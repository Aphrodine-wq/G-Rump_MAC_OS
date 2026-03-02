import XCTest
@testable import GRump

final class PersistenceTests: XCTestCase {

    func testSDConversationFromLegacy() {
        var conv = Conversation(title: "Test Chat")
        conv.messages = [
            Message(role: .user, content: "Hello"),
            Message(role: .assistant, content: "Hi there!"),
        ]
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.title, "Test Chat")
        XCTAssertEqual(sd.conversationId, conv.id)
    }

    func testSDMessageFromLegacy() {
        let msg = Message(role: .assistant, content: "Swift is great", toolCalls: [ToolCall(id: "tc1", name: "read_file", arguments: "{}")])
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.role, "assistant")
        XCTAssertEqual(sd.content, "Swift is great")
        XCTAssertNotNil(sd.toolCallsData)
    }

    func testSDConversationCodableRoundTrip() throws {
        let sd = SDConversation(from: Conversation(title: "Roundtrip"))
        let data = try JSONEncoder().encode(sd)
        let decoded = try JSONDecoder().decode(SDConversation.self, from: data)
        XCTAssertEqual(decoded.title, "Roundtrip")
        XCTAssertEqual(decoded.conversationId, sd.conversationId)
    }

    @MainActor func testGRumpPersistenceStoreShared() {
        let store = GRumpPersistenceStore.shared
        XCTAssertNotNil(store)
    }

    // MARK: - SDConversation from Legacy

    func testSDConversationFromLegacyPreservesTitle() {
        let conv = Conversation(title: "My Title")
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.title, "My Title")
    }

    func testSDConversationFromLegacyPreservesId() {
        let conv = Conversation(title: "T")
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.conversationId, conv.id)
    }

    func testSDConversationFromLegacyPreservesDates() {
        let conv = Conversation(title: "T")
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.createdAt.timeIntervalSince1970, conv.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(sd.updatedAt.timeIntervalSince1970, conv.updatedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testSDConversationFromLegacyPreservesViewMode() {
        var conv = Conversation(title: "T")
        conv.viewMode = .threaded
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.viewMode, "threaded")
    }

    func testSDConversationFromLegacyDefaultViewMode() {
        let conv = Conversation(title: "T")
        let sd = SDConversation(from: conv)
        XCTAssertEqual(sd.viewMode, "linear")
    }

    // MARK: - SDConversation toLegacy

    func testSDConversationToLegacyRoundTrip() {
        var conv = Conversation(title: "Round Trip")
        conv.viewMode = .branched
        let sd = SDConversation(from: conv)
        let back = sd.toLegacy()
        XCTAssertEqual(back.title, "Round Trip")
        XCTAssertEqual(back.id, conv.id)
        XCTAssertEqual(back.viewMode, .branched)
    }

    // MARK: - SDMessage from Legacy

    func testSDMessageFromLegacyPreservesRole() {
        let msg = Message(role: .user, content: "Hello")
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.role, "user")
    }

    func testSDMessageFromLegacyPreservesContent() {
        let msg = Message(role: .assistant, content: "World")
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.content, "World")
    }

    func testSDMessageFromLegacyPreservesTimestamp() {
        let ts = Date()
        let msg = Message(role: .user, content: "t", timestamp: ts)
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.timestamp.timeIntervalSince1970, ts.timeIntervalSince1970, accuracy: 1)
    }

    func testSDMessageFromLegacyNilToolCalls() {
        let msg = Message(role: .user, content: "t")
        let sd = SDMessage(from: msg)
        XCTAssertNil(sd.toolCallsData)
    }

    func testSDMessageFromLegacyWithToolCalls() {
        var msg = Message(role: .assistant, content: "t")
        msg.toolCalls = [ToolCall(id: "tc1", name: "read_file", arguments: "{}")]
        let sd = SDMessage(from: msg)
        XCTAssertNotNil(sd.toolCallsData)
    }

    func testSDMessageFromLegacyPreservesToolCallId() {
        var msg = Message(role: .tool, content: "result")
        msg.toolCallId = "tc-42"
        let sd = SDMessage(from: msg)
        XCTAssertEqual(sd.toolCallId, "tc-42")
    }

    // MARK: - SDMessage toLegacy

    func testSDMessageToLegacyRoundTrip() {
        var msg = Message(role: .assistant, content: "Hello back")
        msg.toolCalls = [ToolCall(id: "tc1", name: "write_file", arguments: "{\"path\":\"/a\"}")]
        let sd = SDMessage(from: msg)
        let back = sd.toLegacy()
        XCTAssertEqual(back.role, .assistant)
        XCTAssertEqual(back.content, "Hello back")
        XCTAssertEqual(back.toolCalls?.count, 1)
        XCTAssertEqual(back.toolCalls?.first?.name, "write_file")
    }

    func testSDMessageToLegacyPreservesThreading() {
        var msg = Message(role: .user, content: "t")
        let tid = UUID()
        msg.threadId = tid
        msg.isBranch = true
        msg.branchName = "Alt"
        let sd = SDMessage(from: msg)
        let back = sd.toLegacy()
        XCTAssertEqual(back.threadId, tid)
        XCTAssertTrue(back.isBranch)
        XCTAssertEqual(back.branchName, "Alt")
    }

    // MARK: - SDConversation Codable

    func testSDConversationCodablePreservesAllFields() throws {
        var conv = Conversation(title: "Full Test")
        conv.viewMode = .threaded
        let sd = SDConversation(from: conv)
        sd.isPinned = true
        sd.projectLabel = "MyProject"
        let data = try JSONEncoder().encode(sd)
        let decoded = try JSONDecoder().decode(SDConversation.self, from: data)
        XCTAssertEqual(decoded.title, "Full Test")
        XCTAssertEqual(decoded.conversationId, conv.id)
        XCTAssertTrue(decoded.isPinned)
        XCTAssertEqual(decoded.projectLabel, "MyProject")
        XCTAssertEqual(decoded.viewMode, "threaded")
    }

    // MARK: - GRumpPersistenceStore

    @MainActor func testGRumpPersistenceStoreIsSingleton() {
        let a = GRumpPersistenceStore.shared
        let b = GRumpPersistenceStore.shared
        XCTAssertTrue(a === b)
    }

    // MARK: - SwiftDataMigrator

    func testMigratorKeyAccess() {
        // hasMigrated should not crash
        _ = SwiftDataMigrator.hasMigrated
    }
}
