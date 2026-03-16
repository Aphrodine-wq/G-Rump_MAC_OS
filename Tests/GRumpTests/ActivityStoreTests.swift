import XCTest
@testable import GRump

final class ActivityStoreTests: XCTestCase {

    func testActivityEntryCreation() {
        let entry = ActivityEntry(toolName: "readFile", summary: "Read main.swift", success: true)
        XCTAssertFalse(entry.id.uuidString.isEmpty)
        XCTAssertEqual(entry.toolName, "readFile")
        XCTAssertEqual(entry.summary, "Read main.swift")
        XCTAssertTrue(entry.success)
    }

    func testActivityEntryCodableRoundTrip() throws {
        let entry = ActivityEntry(toolName: "run_command", summary: "swift build", success: true, conversationId: UUID(), metadata: ActivityEntry.Metadata(filePath: "/src/main.swift", command: "swift build"))
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(ActivityEntry.self, from: data)
        XCTAssertEqual(decoded.toolName, entry.toolName)
        XCTAssertEqual(decoded.summary, entry.summary)
        XCTAssertEqual(decoded.success, entry.success)
        XCTAssertEqual(decoded.metadata?.filePath, "/src/main.swift")
        XCTAssertEqual(decoded.metadata?.command, "swift build")
    }

    func testActivityEntryFailure() {
        let entry = ActivityEntry(toolName: "writeFile", summary: "Error: permission denied", success: false)
        XCTAssertFalse(entry.success)
        XCTAssertTrue(entry.summary.contains("Error"))
    }

    @MainActor
    func testActivityStoreAppend() {
        let store = ActivityStore()
        XCTAssertTrue(store.entries.isEmpty)
        store.append(ActivityEntry(toolName: "test", summary: "test", success: true))
        XCTAssertEqual(store.entries.count, 1)
    }

    @MainActor
    func testActivityStoreMaxEntries() {
        let store = ActivityStore()
        for i in 0..<250 {
            store.append(ActivityEntry(toolName: "tool\(i)", summary: "s\(i)", success: true))
        }
        // Should cap at maxInMemory (200)
        XCTAssertLessThanOrEqual(store.entries.count, 200)
    }

    // MARK: - Expanded Tests

    @MainActor
    func testActivityStoreClear() {
        let store = ActivityStore()
        store.append(ActivityEntry(toolName: "a", summary: "s", success: true))
        store.append(ActivityEntry(toolName: "b", summary: "s", success: true))
        XCTAssertEqual(store.entries.count, 2)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor
    func testActivityStoreNewestFirst() {
        let store = ActivityStore()
        store.append(ActivityEntry(toolName: "first", summary: "1", success: true))
        store.append(ActivityEntry(toolName: "second", summary: "2", success: true))
        XCTAssertEqual(store.entries.first?.toolName, "second",
            "Most recent entry should be at index 0")
    }

    func testActivityEntryEquatable() {
        let id = UUID()
        let ts = Date()
        let a = ActivityEntry(id: id, timestamp: ts, toolName: "t", summary: "s", success: true)
        let b = ActivityEntry(id: id, timestamp: ts, toolName: "t", summary: "s", success: true)
        XCTAssertEqual(a, b)
    }

    func testActivityEntryNotEqual() {
        let a = ActivityEntry(toolName: "t", summary: "s", success: true)
        let b = ActivityEntry(toolName: "t", summary: "s", success: true)
        XCTAssertNotEqual(a, b, "Different UUIDs should make entries not equal")
    }

    func testActivityEntryMetadataFilePath() {
        let meta = ActivityEntry.Metadata(filePath: "/src/main.swift", command: nil)
        XCTAssertEqual(meta.filePath, "/src/main.swift")
        XCTAssertNil(meta.command)
    }

    func testActivityEntryMetadataCommand() {
        let meta = ActivityEntry.Metadata(filePath: nil, command: "swift test")
        XCTAssertNil(meta.filePath)
        XCTAssertEqual(meta.command, "swift test")
    }

    func testActivityEntryNilMetadata() {
        let entry = ActivityEntry(toolName: "t", summary: "s", success: true, metadata: nil)
        XCTAssertNil(entry.metadata)
    }

    func testActivityEntryNilConversationId() {
        let entry = ActivityEntry(toolName: "t", summary: "s", success: true, conversationId: nil)
        XCTAssertNil(entry.conversationId)
    }

    func testActivityEntryWithConversationId() {
        let cid = UUID()
        let entry = ActivityEntry(toolName: "t", summary: "s", success: true, conversationId: cid)
        XCTAssertEqual(entry.conversationId, cid)
    }

    func testActivityEntryTimestampIsRecent() {
        let entry = ActivityEntry(toolName: "t", summary: "s", success: true)
        let diff = abs(entry.timestamp.timeIntervalSinceNow)
        XCTAssertLessThan(diff, 2, "Timestamp should be within 2 seconds of now")
    }

    func testMetadataCodableRoundTrip() throws {
        let meta = ActivityEntry.Metadata(filePath: "/test", command: "ls -la")
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(ActivityEntry.Metadata.self, from: data)
        XCTAssertEqual(decoded, meta)
    }

    func testMetadataEquatable() {
        let a = ActivityEntry.Metadata(filePath: "/x", command: "y")
        let b = ActivityEntry.Metadata(filePath: "/x", command: "y")
        XCTAssertEqual(a, b)
    }

    @MainActor
    func testActivityStorePersistenceRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("activity.json").path

        defer { try? FileManager.default.removeItem(atPath: tmpDir.path) }

        let store1 = ActivityStore()
        store1.setPersistencePath(path)
        store1.append(ActivityEntry(toolName: "saved", summary: "persisted", success: true))
        XCTAssertEqual(store1.entries.count, 1)

        let store2 = ActivityStore()
        store2.setPersistencePath(path)
        XCTAssertEqual(store2.entries.count, 1)
        XCTAssertEqual(store2.entries.first?.toolName, "saved")
    }

    @MainActor
    func testActivityStoreClearRemovesPersisted() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("activity.json").path

        defer { try? FileManager.default.removeItem(atPath: tmpDir.path) }

        let store = ActivityStore()
        store.setPersistencePath(path)
        store.append(ActivityEntry(toolName: "a", summary: "s", success: true))
        store.clear()

        let store2 = ActivityStore()
        store2.setPersistencePath(path)
        XCTAssertTrue(store2.entries.isEmpty, "Clear should persist the empty state")
    }

    // MARK: - Additional Edge Cases

    @MainActor
    func testActivityStoreExactlyAtCap() {
        let store = ActivityStore()
        for i in 0..<200 {
            store.append(ActivityEntry(toolName: "t\(i)", summary: "s", success: true))
        }
        XCTAssertEqual(store.entries.count, 200, "Exactly at cap should hold 200")
        // One more should still be 200
        store.append(ActivityEntry(toolName: "overflow", summary: "s", success: true))
        XCTAssertEqual(store.entries.count, 200)
        XCTAssertEqual(store.entries.first?.toolName, "overflow", "Newest should be first")
    }

    @MainActor
    func testActivityStoreAppendAfterClear() {
        let store = ActivityStore()
        store.append(ActivityEntry(toolName: "before", summary: "s", success: true))
        store.clear()
        store.append(ActivityEntry(toolName: "after", summary: "s", success: true))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].toolName, "after")
    }

    @MainActor
    func testActivityStoreSetNilPersistencePath() {
        let store = ActivityStore()
        store.setPersistencePath(nil)
        store.append(ActivityEntry(toolName: "t", summary: "s", success: true))
        XCTAssertEqual(store.entries.count, 1, "Should still store in memory")
    }

    @MainActor
    func testActivityStorePersistenceNonexistentDir() {
        let store = ActivityStore()
        let path = "/tmp/grump-test-\(UUID().uuidString)/deep/dir/activity.json"
        store.setPersistencePath(path)
        store.append(ActivityEntry(toolName: "t", summary: "s", success: true))
        // Should create directory and persist without crash
        XCTAssertEqual(store.entries.count, 1)
        // Clean up
        try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent)
    }

    @MainActor
    func testActivityStoreLoadFromNonexistentPath() {
        let store = ActivityStore()
        store.setPersistencePath("/nonexistent/path/activity.json")
        // Should not crash, entries should be empty
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testActivityEntryMetadataBothFieldsPopulated() {
        let meta = ActivityEntry.Metadata(filePath: "/src/main.swift", command: "swift build")
        XCTAssertEqual(meta.filePath, "/src/main.swift")
        XCTAssertEqual(meta.command, "swift build")
    }

    func testActivityEntryMetadataBothFieldsNil() {
        let meta = ActivityEntry.Metadata(filePath: nil, command: nil)
        XCTAssertNil(meta.filePath)
        XCTAssertNil(meta.command)
    }

    @MainActor
    func testActivityStoreIsObservableObject() {
        let store = ActivityStore()
        let _ = store.objectWillChange
        // If this compiles, ObservableObject conformance is confirmed
    }
}
