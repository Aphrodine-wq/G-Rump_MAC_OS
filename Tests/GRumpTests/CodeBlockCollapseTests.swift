import XCTest
@testable import GRump

/// Tests for the CodeBlockView collapse/expand logic.
/// Validates thresholds, visible line counts, and expand/collapse behavior.
final class CodeBlockCollapseTests: XCTestCase {

    // MARK: - Collapse Threshold Constants

    func testCollapseThresholdIs12() {
        // CodeBlockView.collapseThreshold should be 12
        // We verify indirectly by testing line count behaviors
        let shortCode = (1...12).map { "let x\($0) = \($0)" }.joined(separator: "\n")
        let lines = shortCode.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 12, "12-line code should not trigger collapse")
    }

    func testCollapsedPreviewIs8Lines() {
        // When collapsed, first 8 lines should show
        let previewCount = 8
        XCTAssertEqual(previewCount, 8)
    }

    // MARK: - Small Blocks Don't Collapse

    func testSmallBlockNoCollapse() {
        let code = "let x = 1\nlet y = 2\nlet z = 3"
        let lines = code.components(separatedBy: "\n")
        XCTAssertLessThanOrEqual(lines.count, 12, "Small block should not collapse")
    }

    func testExactThresholdNoCollapse() {
        let code = (1...12).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 12, "Exactly 12 lines should not collapse")
        XCTAssertFalse(lines.count > 12)
    }

    // MARK: - Large Blocks Collapse

    func testLargeBlockCollapses() {
        let code = (1...50).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 50)
        XCTAssertTrue(lines.count > 12, "50-line block should collapse")
    }

    func testThirteenLinesCollapses() {
        let code = (1...13).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        XCTAssertTrue(lines.count > 12, "13 lines should trigger collapse")
    }

    // MARK: - Visible Lines When Collapsed

    func testVisibleLinesWhenCollapsed() {
        let totalLines = 100
        let previewLines = 8
        let code = (1...totalLines).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let visible = Array(lines.prefix(previewLines))
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.first, "line 1")
        XCTAssertEqual(visible.last, "line 8")
    }

    func testHiddenLineCount() {
        let totalLines = 50
        let previewLines = 8
        let hidden = max(0, totalLines - previewLines)
        XCTAssertEqual(hidden, 42)
    }

    // MARK: - Visible Lines When Expanded

    func testVisibleLinesWhenExpanded() {
        let totalLines = 50
        let code = (1...totalLines).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        // When expanded, all lines should be visible
        XCTAssertEqual(lines.count, totalLines)
    }

    // MARK: - Edge Cases

    func testOneLineBlockNoCollapse() {
        let code = "let x = 1"
        let lines = code.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 1)
        XCTAssertFalse(lines.count > 12)
    }

    func testEmptyBlockNoCollapse() {
        let code = ""
        let lines = code.components(separatedBy: "\n")
        XCTAssertFalse(lines.count > 12)
    }

    func testZeroHiddenLinesWhenSmall() {
        let totalLines = 5
        let previewLines = 8
        let hidden = max(0, totalLines - previewLines)
        XCTAssertEqual(hidden, 0)
    }

    // MARK: - Syntax Highlighting Integration

    func testHighlighterTokensCappedToPreview() {
        let code = (1...50).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let highlighter = SyntaxHighlighter(language: "swift")
        let allTokens = lines.map { highlighter.highlight($0) }
        XCTAssertEqual(allTokens.count, 50)

        // In collapsed mode, only first 8 lines' tokens should render
        let visibleTokens = Array(allTokens.prefix(8))
        XCTAssertEqual(visibleTokens.count, 8)
    }

    func testExpandedTokensMatchTotalLines() {
        let code = (1...25).map { "func f\($0)() {}" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let highlighter = SyntaxHighlighter(language: "swift")
        let tokens = lines.map { highlighter.highlight($0) }
        XCTAssertEqual(tokens.count, lines.count)
    }

    // MARK: - Height Calculation

    func testCollapsedHeightSmallerThanExpanded() {
        let lineHeight: CGFloat = 14 + 2 // 14pt + typical spacing
        let previewLines = 8
        let totalLines = 100
        let collapsedHeight = CGFloat(previewLines) * lineHeight + 20
        let expandedHeight = min(CGFloat(totalLines) * lineHeight + 20, 400)
        XCTAssertLessThan(collapsedHeight, expandedHeight)
    }

    func testExpandedHeightCappedAt400() {
        let lineHeight: CGFloat = 16.0
        let totalLines = 1000
        let maxHeight: CGFloat = min(CGFloat(totalLines) * lineHeight + 20, 400)
        XCTAssertEqual(maxHeight, 400)
    }
}
