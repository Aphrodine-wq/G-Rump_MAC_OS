import XCTest
@testable import GRump

/// Tests for the `<thinking>` block parser used during streaming.
/// Validates that reasoning traces wrapped in `<thinking>...</thinking>` tags
/// are correctly separated from visible content.
@MainActor
final class ThinkingParserTests: XCTestCase {

    // MARK: - Helper

    private func parse(_ text: String) -> (visible: String, thinking: String) {
        var thinking = ""
        let visible = ChatViewModel.extractThinkingBlocks(from: text, thinkingContent: &thinking)
        return (visible, thinking)
    }

    // MARK: - No Thinking Content

    func testNoThinkingTags_returnsOriginal() {
        let result = parse("Hello, world!")
        XCTAssertEqual(result.visible, "Hello, world!")
        XCTAssertEqual(result.thinking, "")
    }

    func testEmptyString_returnsEmpty() {
        let result = parse("")
        XCTAssertEqual(result.visible, "")
        XCTAssertEqual(result.thinking, "")
    }

    // MARK: - Single Complete Block

    func testSingleCompleteThinkingBlock() {
        let text = "Before<thinking>I need to think</thinking>After"
        let result = parse(text)
        XCTAssertEqual(result.visible, "BeforeAfter")
        XCTAssertEqual(result.thinking, "I need to think")
    }

    func testThinkingBlockAtStart() {
        let text = "<thinking>reasoning</thinking>Visible text"
        let result = parse(text)
        XCTAssertEqual(result.visible, "Visible text")
        XCTAssertEqual(result.thinking, "reasoning")
    }

    func testThinkingBlockAtEnd() {
        let text = "Visible text<thinking>reasoning at end</thinking>"
        let result = parse(text)
        XCTAssertEqual(result.visible, "Visible text")
        XCTAssertEqual(result.thinking, "reasoning at end")
    }

    // MARK: - Multiple Blocks

    func testMultipleThinkingBlocks() {
        let text = "A<thinking>first</thinking>B<thinking>second</thinking>C"
        let result = parse(text)
        XCTAssertEqual(result.visible, "ABC")
        XCTAssertEqual(result.thinking, "firstsecond")
    }

    // MARK: - Incomplete Block (Streaming)

    func testIncompleteThinkingBlock_treatsRestAsThinking() {
        let text = "Visible<thinking>still streaming"
        let result = parse(text)
        XCTAssertEqual(result.visible, "Visible")
        XCTAssertEqual(result.thinking, "still streaming")
    }

    // MARK: - Empty Thinking Content

    func testEmptyThinkingBlock() {
        let text = "Before<thinking></thinking>After"
        let result = parse(text)
        XCTAssertEqual(result.visible, "BeforeAfter")
        XCTAssertEqual(result.thinking, "")
    }

    // MARK: - Multiline Content

    func testMultilineThinkingContent() {
        let text = """
        Hello
        <thinking>
        Line 1
        Line 2
        </thinking>
        World
        """
        let result = parse(text)
        XCTAssertTrue(result.visible.contains("Hello"))
        XCTAssertTrue(result.visible.contains("World"))
        XCTAssertTrue(result.thinking.contains("Line 1"))
        XCTAssertTrue(result.thinking.contains("Line 2"))
    }

    // MARK: - Only Thinking Content

    func testOnlyThinkingContent() {
        let text = "<thinking>all reasoning</thinking>"
        let result = parse(text)
        XCTAssertEqual(result.visible, "")
        XCTAssertEqual(result.thinking, "all reasoning")
    }

    // MARK: - Idempotent on Non-Tag Angle Brackets

    func testAngleBracketsWithoutThinkingTag() {
        let text = "Use <div> tags and x < y > z"
        let result = parse(text)
        XCTAssertEqual(result.visible, text)
        XCTAssertEqual(result.thinking, "")
    }

    // MARK: - InOut Parameter Behavior

    func testThinkingContentAccumulatesPerCall() {
        var thinking = "previous "
        let _ = ChatViewModel.extractThinkingBlocks(from: "<thinking>new</thinking>", thinkingContent: &thinking)
        // The function replaces (does not append to) thinkingContent
        XCTAssertEqual(thinking, "new")
    }
}
