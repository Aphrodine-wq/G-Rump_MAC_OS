import XCTest
@testable import GRump

final class GRumpDefaultsTests: XCTestCase {

    // MARK: - System Prompt

    func testDefaultSystemPromptNotEmpty() {
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty)
    }

    func testDefaultSystemPromptContainsBrandName() {
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"))
    }

    func testDefaultSystemPromptContainsCoreGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Inspect before modifying"), "Missing inspection guidance")
        XCTAssertTrue(prompt.contains("Minimal, surgical changes"), "Missing minimal changes guidance")
        XCTAssertTrue(prompt.contains("Verify your work"), "Missing verification guidance")
        XCTAssertTrue(prompt.contains("Recover from errors"), "Missing error recovery guidance")
        XCTAssertTrue(prompt.contains("Think step by step"), "Missing step-by-step guidance")
    }

    func testDefaultSystemPromptContainsToolGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("tree_view"))
        XCTAssertTrue(prompt.contains("grep_search"))
        XCTAssertTrue(prompt.contains("read_file"))
        XCTAssertTrue(prompt.contains("edit_file"))
        XCTAssertTrue(prompt.contains("run_command"))
        XCTAssertTrue(prompt.contains("web_search"))
    }

    func testDefaultSystemPromptContainsCodeQualityStandards() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Code Quality Standards"))
        XCTAssertTrue(prompt.contains("error handling"))
    }

    func testDefaultSystemPromptContainsCommunicationStyle() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Communication Style"))
        XCTAssertTrue(prompt.contains("direct and concise"))
    }

    func testDefaultSystemPromptContainsWorkingDirectoryGuidance() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        XCTAssertTrue(prompt.contains("Working Directory"))
    }

    func testDefaultSystemPromptReasonableLength() {
        let prompt = GRumpDefaults.defaultSystemPrompt
        // Should be substantial but not absurdly long
        XCTAssertGreaterThan(prompt.count, 500, "System prompt too short")
        XCTAssertLessThan(prompt.count, 10000, "System prompt too long")
    }
}
