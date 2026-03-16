import XCTest
@testable import GRump

/// Tests for MemoryStore — entry lifecycle, persistence, retrieval, content truncation.
final class MemoryStoreIntegrationTests: XCTestCase {

    private var tmpDir: URL!
    private var store: MemoryStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-mem-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = MemoryStore(baseDirectory: tmpDir.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Basic Entry Operations

    func testInitiallyEmpty() {
        XCTAssertEqual(store.count(), 0)
        XCTAssertTrue(store.recentEntries().isEmpty)
    }

    func testAddEntry() {
        store.addEntry(conversationId: "conv1", userMessage: "Hello", assistantContent: "Hi back")
        XCTAssertEqual(store.count(), 1)
    }

    func testAddMultipleEntries() {
        for i in 0..<5 {
            store.addEntry(conversationId: "c\(i)", userMessage: "Q\(i)", assistantContent: "A\(i)")
        }
        XCTAssertEqual(store.count(), 5)
    }

    // MARK: - Retrieval

    func testRecentEntriesReturnsMostRecent() {
        store.addEntry(conversationId: "c1", userMessage: "First", assistantContent: "A1")
        store.addEntry(conversationId: "c2", userMessage: "Second", assistantContent: "A2")

        let entries = store.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 2)
        // Most recent first
        XCTAssertTrue(entries[0].content.contains("Second"))
    }

    func testRecentEntriesLimit() {
        for i in 0..<20 {
            store.addEntry(conversationId: "c", userMessage: "Q\(i)", assistantContent: "A\(i)")
        }
        let limited = store.recentEntries(limit: 5)
        XCTAssertEqual(limited.count, 5)
    }

    func testRetrieveEntries() {
        store.addEntry(conversationId: "c1", userMessage: "Swift concurrency", assistantContent: "Use actors")
        let entries = store.retrieveEntries(query: "Swift", limit: 10)
        XCTAssertFalse(entries.isEmpty)
    }

    // MARK: - Content Formatting

    func testEntryContainsUserMessage() {
        store.addEntry(conversationId: "c1", userMessage: "How do I use async/await?", assistantContent: "Use the async keyword")
        let entries = store.recentEntries()
        XCTAssertTrue(entries[0].content.contains("User:"))
        XCTAssertTrue(entries[0].content.contains("async/await"))
    }

    func testEntryContainsAssistantContent() {
        store.addEntry(conversationId: "c1", userMessage: "Q", assistantContent: "Use the async keyword")
        let entries = store.recentEntries()
        XCTAssertTrue(entries[0].content.contains("Assistant:"))
    }

    func testEntryWithToolCallSummary() {
        store.addEntry(conversationId: "c1", userMessage: "Fix the bug", assistantContent: "Done", toolCallSummary: "edit_file: main.swift")
        let entries = store.recentEntries()
        XCTAssertTrue(entries[0].content.contains("Actions:"))
        XCTAssertTrue(entries[0].content.contains("edit_file"))
    }

    func testLongUserMessageTruncated() {
        let longMsg = String(repeating: "x", count: 500)
        store.addEntry(conversationId: "c", userMessage: longMsg, assistantContent: "ok")
        let entries = store.recentEntries()
        // User message should be truncated to 200 chars
        let userPart = entries[0].content.components(separatedBy: "\n").first ?? ""
        XCTAssertLessThanOrEqual(userPart.count, 210) // "User: " prefix + 200 chars
    }

    // MARK: - Clear

    func testClear() {
        store.addEntry(conversationId: "c", userMessage: "Q", assistantContent: "A")
        XCTAssertEqual(store.count(), 1)
        store.clear()
        XCTAssertEqual(store.count(), 0)
    }

    // MARK: - Persistence

    func testPersistenceRoundTrip() {
        store.addEntry(conversationId: "c1", userMessage: "Q", assistantContent: "A")

        let store2 = MemoryStore(baseDirectory: tmpDir.path)
        XCTAssertEqual(store2.count(), 1)
        let entries = store2.recentEntries()
        XCTAssertTrue(entries[0].content.contains("Q"))
    }

    func testClearPersists() {
        store.addEntry(conversationId: "c", userMessage: "Q", assistantContent: "A")
        store.clear()

        let store2 = MemoryStore(baseDirectory: tmpDir.path)
        XCTAssertEqual(store2.count(), 0)
    }

    // MARK: - Edge Cases

    func testEmptyBaseDirectory() {
        let emptyStore = MemoryStore(baseDirectory: "")
        emptyStore.addEntry(conversationId: "c", userMessage: "Q", assistantContent: "A")
        XCTAssertEqual(emptyStore.count(), 0)
    }

    func testEntryHasTimestamp() {
        store.addEntry(conversationId: "c", userMessage: "Q", assistantContent: "A")
        let entries = store.recentEntries()
        XCTAssertFalse(entries[0].timestamp.isEmpty)
    }

    func testEntryHasConversationId() {
        store.addEntry(conversationId: "myConvId", userMessage: "Q", assistantContent: "A")
        let entries = store.recentEntries()
        XCTAssertEqual(entries[0].conversationId, "myConvId")
    }

    // MARK: - MemoryEntry Model

    func testMemoryEntryCreation() {
        let entry = MemoryEntry(id: UUID(), conversationId: "c1", timestamp: "2026-01-01", content: "test")
        XCTAssertEqual(entry.conversationId, "c1")
        XCTAssertEqual(entry.timestamp, "2026-01-01")
        XCTAssertEqual(entry.content, "test")
    }

    func testMemoryEntryCodable() throws {
        let entry = MemoryEntry(id: UUID(), conversationId: "c1", timestamp: "2026-01-01", content: "test")
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MemoryEntry.self, from: data)
        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.content, entry.content)
    }
}
