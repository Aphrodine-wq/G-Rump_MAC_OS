import XCTest
@testable import GRump

@MainActor
final class CodeApplyServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Apply

    func testApplyWritesCodeToFile() {
        let service = CodeApplyService()
        let filePath = tempDir.appendingPathComponent("test.swift").path
        let code = "import Foundation\nprint(\"Hello\")"
        let result = service.apply(blockId: "b1", code: code, toFile: filePath)
        XCTAssertNil(result, "apply should succeed")
        XCTAssertEqual(try? String(contentsOfFile: filePath, encoding: .utf8), code)
    }

    func testApplySetsAppliedState() {
        let service = CodeApplyService()
        let filePath = tempDir.appendingPathComponent("test.swift").path
        _ = service.apply(blockId: "b1", code: "code", toFile: filePath)
        XCTAssertEqual(service.state(for: "b1"), .applied)
    }

    func testApplyCreatesParentDirectories() {
        let service = CodeApplyService()
        let filePath = tempDir.appendingPathComponent("nested/deep/test.swift").path
        let result = service.apply(blockId: "b1", code: "code", toFile: filePath)
        XCTAssertNil(result)
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
    }

    func testApplyPreservesOriginalForUndo() {
        let service = CodeApplyService()
        let filePath = tempDir.appendingPathComponent("test.swift").path
        let original = "original content"
        try! original.write(toFile: filePath, atomically: true, encoding: .utf8)

        _ = service.apply(blockId: "b1", code: "new content", toFile: filePath)
        XCTAssertEqual(try? String(contentsOfFile: filePath, encoding: .utf8), "new content")

        // Undo should restore original
        let undoResult = service.undo(blockId: "b1", filePath: filePath)
        XCTAssertNil(undoResult)
        XCTAssertEqual(try? String(contentsOfFile: filePath, encoding: .utf8), original)
    }

    // MARK: - Reject

    func testRejectSetsRejectedState() {
        let service = CodeApplyService()
        service.reject(blockId: "b2")
        XCTAssertEqual(service.state(for: "b2"), .rejected)
    }

    // MARK: - Undo

    func testUndoWithNoDataReturnsError() {
        let service = CodeApplyService()
        let result = service.undo(blockId: "nonexistent", filePath: "/tmp/nope")
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.contains("No undo data"))
    }

    func testUndoResetsStateToPending() {
        let service = CodeApplyService()
        let filePath = tempDir.appendingPathComponent("test.swift").path
        try! "original".write(toFile: filePath, atomically: true, encoding: .utf8)

        _ = service.apply(blockId: "b1", code: "new", toFile: filePath)
        XCTAssertEqual(service.state(for: "b1"), .applied)

        _ = service.undo(blockId: "b1", filePath: filePath)
        XCTAssertEqual(service.state(for: "b1"), .pending)
    }

    // MARK: - State Queries

    func testDefaultStateIsPending() {
        let service = CodeApplyService()
        XCTAssertEqual(service.state(for: "unknown"), .pending)
    }

    func testResetStatesForConversation() {
        let service = CodeApplyService()
        let convId = UUID()
        let bid1 = CodeApplyService.blockId(conversationId: convId, blockIndex: 0)
        let bid2 = CodeApplyService.blockId(conversationId: convId, blockIndex: 1)

        _ = service.apply(blockId: bid1, code: "a", toFile: tempDir.appendingPathComponent("a.swift").path)
        service.reject(blockId: bid2)

        service.resetStates(for: convId)
        XCTAssertEqual(service.state(for: bid1), .pending)
        XCTAssertEqual(service.state(for: bid2), .pending)
    }

    // MARK: - Block ID Generation

    func testBlockIdFormat() {
        let convId = UUID()
        let bid = CodeApplyService.blockId(conversationId: convId, blockIndex: 3)
        XCTAssertTrue(bid.hasPrefix(convId.uuidString))
        XCTAssertTrue(bid.hasSuffix("-block-3"))
    }

    // MARK: - File Path Detection

    func testDetectFilePathFromBackticks() {
        let context = "Here's the updated `Sources/GRump/Models.swift`:"
        let result = CodeApplyService.detectFilePath(from: context, language: "swift")
        XCTAssertEqual(result, "Sources/GRump/Models.swift")
    }

    func testDetectFilePathReturnsNilForNoPath() {
        let context = "Here's some code:"
        let result = CodeApplyService.detectFilePath(from: context, language: "swift")
        XCTAssertNil(result)
    }
}
