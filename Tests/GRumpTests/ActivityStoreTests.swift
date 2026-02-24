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
}
