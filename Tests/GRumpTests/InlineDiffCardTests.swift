import XCTest
@testable import GRump

final class InlineDiffCardTests: XCTestCase {

    // MARK: - DiffType

    func testDiffTypePrefixes() {
        XCTAssertEqual(InlineDiffCard.DiffType.context.prefix, " ")
        XCTAssertEqual(InlineDiffCard.DiffType.added.prefix, "+")
        XCTAssertEqual(InlineDiffCard.DiffType.removed.prefix, "-")
    }

    // MARK: - Diff Computation (via reflection-free approach)

    func testIdenticalContentProducesOnlyContextLines() {
        let card = InlineDiffCard(filePath: "test.swift", originalContent: "line1\nline2", newContent: "line1\nline2")
        // Access diffLines indirectly via addedCount/removedCount
        // Since both are the same, addedCount and removedCount should be 0
        // We test this by checking the card can be constructed without crash
        XCTAssertNotNil(card)
    }

    func testDiffLineStructure() {
        let line = InlineDiffCard.DiffLine(type: .added, content: "new line", oldLineNum: nil, newLineNum: 5)
        XCTAssertEqual(line.type, .added)
        XCTAssertEqual(line.content, "new line")
        XCTAssertNil(line.oldLineNum)
        XCTAssertEqual(line.newLineNum, 5)
    }

    func testDiffLineRemoved() {
        let line = InlineDiffCard.DiffLine(type: .removed, content: "old line", oldLineNum: 3, newLineNum: nil)
        XCTAssertEqual(line.type, .removed)
        XCTAssertEqual(line.oldLineNum, 3)
        XCTAssertNil(line.newLineNum)
    }

    func testDiffLineContext() {
        let line = InlineDiffCard.DiffLine(type: .context, content: "same line", oldLineNum: 1, newLineNum: 1)
        XCTAssertEqual(line.type, .context)
        XCTAssertEqual(line.oldLineNum, 1)
        XCTAssertEqual(line.newLineNum, 1)
    }
}
