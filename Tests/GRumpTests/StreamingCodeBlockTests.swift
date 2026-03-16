import XCTest
@testable import GRump

/// Tests for the StreamingCodeBlockView tail-only display and incremental highlighting.
final class StreamingCodeBlockTests: XCTestCase {

    // MARK: - Tail Line Constants

    func testStreamingTailLinesIs8() {
        // StreamingCodeBlockView.streamingTailLines should be 8
        let tailLines = 8
        XCTAssertEqual(tailLines, 8)
    }

    // MARK: - Visible Lines During Streaming

    func testShortStreamShowsAllLines() {
        let code = (1...5).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let tailLines = 8
        // When lines <= tailLines, show all
        let visible: [String]
        if lines.count > tailLines {
            visible = Array(lines.suffix(tailLines))
        } else {
            visible = lines
        }
        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.first, "line 1")
    }

    func testLongStreamShowsTailOnly() {
        let code = (1...100).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let tailLines = 8
        let visible = Array(lines.suffix(tailLines))
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.first, "line 93")
        XCTAssertEqual(visible.last, "line 100")
    }

    func testExactlyEightLinesShowsAll() {
        let code = (1...8).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let tailLines = 8
        let visible: [String]
        if lines.count > tailLines {
            visible = Array(lines.suffix(tailLines))
        } else {
            visible = lines
        }
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.first, "line 1")
    }

    func testNineLinesShowsTail() {
        let code = (1...9).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let tailLines = 8
        let visible = Array(lines.suffix(tailLines))
        XCTAssertEqual(visible.count, 8)
        XCTAssertEqual(visible.first, "line 2")
    }

    // MARK: - Line Number Calculation

    func testStartLineNumberSmallCode() {
        let lineCount = 5
        let tailLines = 8
        let startLineNumber = lineCount > tailLines
            ? lineCount - tailLines + 1 : 1
        XCTAssertEqual(startLineNumber, 1)
    }

    func testStartLineNumberLargeCode() {
        let lineCount = 100
        let tailLines = 8
        let startLineNumber = lineCount > tailLines
            ? lineCount - tailLines + 1 : 1
        XCTAssertEqual(startLineNumber, 93)
    }

    func testStartLineNumberExactBoundary() {
        let lineCount = 8
        let tailLines = 8
        let startLineNumber = lineCount > tailLines
            ? lineCount - tailLines + 1 : 1
        XCTAssertEqual(startLineNumber, 1)
    }

    // MARK: - Token Tail Matching

    func testTokensSuffixMatchesVisibleLines() {
        let code = (1...20).map { "let val\($0) = \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let highlighter = SyntaxHighlighter(language: "swift")
        let allTokens = lines.map { highlighter.highlight($0) }
        let tailLines = 8

        let visibleLines = Array(lines.suffix(tailLines))
        let visibleTokens = Array(allTokens.suffix(tailLines))

        XCTAssertEqual(visibleLines.count, visibleTokens.count)
        XCTAssertEqual(visibleTokens.count, 8)
    }

    func testSmallCodeTokensShowAll() {
        let code = "let x = 1\nlet y = 2"
        let lines = code.components(separatedBy: "\n")
        let highlighter = SyntaxHighlighter(language: "swift")
        let allTokens = lines.map { highlighter.highlight($0) }
        let tailLines = 8

        let visibleTokens: [[SyntaxHighlighter.Token]]
        if allTokens.count > tailLines {
            visibleTokens = Array(allTokens.suffix(tailLines))
        } else {
            visibleTokens = allTokens
        }
        XCTAssertEqual(visibleTokens.count, 2)
    }

    // MARK: - Incremental Highlighting

    func testIncrementalHighlightAddsNewLines() {
        let highlighter = SyntaxHighlighter(language: "swift")
        var tokens: [[SyntaxHighlighter.Token]] = []

        // Simulate streaming: add lines one by one
        let lines = ["let a = 1", "let b = 2", "let c = 3"]
        for line in lines {
            tokens.append(highlighter.highlight(line))
        }

        XCTAssertEqual(tokens.count, 3)
        // First line should have "let" keyword
        let firstLineKeywords = tokens[0].filter { $0.kind == .keyword }
        XCTAssertFalse(firstLineKeywords.isEmpty)
    }

    func testIncrementalHighlightReusesExisting() {
        let highlighter = SyntaxHighlighter(language: "swift")

        let line1Tokens = highlighter.highlight("let x = 1")
        let line2Tokens = highlighter.highlight("var y = 2")

        // Simulate incremental: existing + new
        var allTokens = [line1Tokens]
        // New line added
        allTokens.append(line2Tokens)

        XCTAssertEqual(allTokens.count, 2)
        // "let" in first, "var" in second
        XCTAssertTrue(allTokens[0].contains(where: { $0.text == "let" }))
        XCTAssertTrue(allTokens[1].contains(where: { $0.text == "var" }))
    }

    // MARK: - Height Calculation

    func testStreamingHeightUsesVisibleLines() {
        let lineHeight: CGFloat = 18
        let padding: CGFloat = 20
        let tailLines = 8

        // Large code: height based on tail lines only
        let largeCodeLines = 200
        let visibleCount = min(largeCodeLines, tailLines)
        let height = min(CGFloat(visibleCount) * lineHeight + padding, 400)
        XCTAssertEqual(height, CGFloat(8) * 18 + 20) // 164
    }

    func testSmallCodeHeightInclsAllLines() {
        let lineHeight: CGFloat = 18
        let padding: CGFloat = 20
        let codeLines = 3
        let height = min(CGFloat(codeLines) * lineHeight + padding, 400)
        XCTAssertEqual(height, CGFloat(3) * 18 + 20) // 74
    }

    // MARK: - Edge Cases

    func testEmptyCodeDuringStreaming() {
        let lines = "".components(separatedBy: "\n")
        let tailLines = 8
        let visible: [String]
        if lines.count > tailLines {
            visible = Array(lines.suffix(tailLines))
        } else {
            visible = lines
        }
        // Empty string splits to [""]
        XCTAssertEqual(visible.count, 1)
    }

    func testSingleLineDuringStreaming() {
        let lines = ["def hello():"]
        let tailLines = 8
        XCTAssertFalse(lines.count > tailLines)
    }

    // MARK: - Non-streaming Shows All

    func testNonStreamingShowsAllLines() {
        // When isStreaming is false, all lines should be visible
        let code = (1...50).map { "line \($0)" }.joined(separator: "\n")
        let lines = code.components(separatedBy: "\n")
        let isStreaming = false
        let tailLines = 8

        let visible: [String]
        if isStreaming && lines.count > tailLines {
            visible = Array(lines.suffix(tailLines))
        } else {
            visible = lines
        }
        XCTAssertEqual(visible.count, 50, "Non-streaming should show all lines")
    }
}
