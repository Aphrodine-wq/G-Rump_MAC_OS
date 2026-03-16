import XCTest
@testable import GRump

final class SuggestionEngineTests: XCTestCase {

    // MARK: - Suggestion Model

    func testSuggestionCreation() {
        let s = Suggestion(id: "test", title: "Test", prompt: "Do something", icon: "star")
        XCTAssertEqual(s.id, "test")
        XCTAssertEqual(s.title, "Test")
        XCTAssertEqual(s.prompt, "Do something")
        XCTAssertEqual(s.icon, "star")
    }

    func testSuggestionEquality() {
        let a = Suggestion(id: "a", title: "A", prompt: "pa", icon: "i")
        let b = Suggestion(id: "a", title: "A", prompt: "pa", icon: "i")
        XCTAssertEqual(a, b)
    }

    func testSuggestionInequality() {
        let a = Suggestion(id: "a", title: "A", prompt: "pa", icon: "i")
        let b = Suggestion(id: "b", title: "B", prompt: "pb", icon: "j")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Engine: Empty Activity

    func testEmptyActivityReturnsNoSuggestions() {
        let result = SuggestionEngine.suggest(activityEntries: [], workingDirectory: "/tmp")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Engine: Run Tests Suggestion

    func testSuggestsRunTestsAfterEditingTestFile() {
        let entries = makeEntries([
            ("edit_file", true, "/project/Tests/MyTest.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "run_tests" }))
    }

    func testSuggestsRunTestsAfterEditingSourceFile() {
        let entries = makeEntries([
            ("write_file", true, "/project/Sources/Model.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "run_tests" }))
    }

    // MARK: - Engine: Build Suggestion

    func testSuggestsBuildAfterMultipleEdits() {
        let entries = makeEntries([
            ("edit_file", true, "/project/Sources/A.swift"),
            ("write_file", true, "/project/Sources/B.swift"),
            ("create_file", true, "/project/Sources/C.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "run_build" }))
    }

    func testNoBuildSuggestionIfRecentBuildSucceeded() {
        let entries = makeEntries([
            ("run_build", true, nil),
            ("edit_file", true, "/project/Sources/A.swift"),
            ("write_file", true, "/project/Sources/B.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertFalse(result.contains(where: { $0.id == "run_build" }))
    }

    // MARK: - Engine: Commit Suggestion

    func testSuggestsCommitAfterFileChanges() {
        let entries = makeEntries([
            ("write_file", true, "/project/Sources/New.swift"),
            ("edit_file", true, "/project/Sources/Old.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "commit" }))
    }

    func testNoCommitSuggestionAfterRecentCommit() {
        let entries = makeEntries([
            ("git_commit", true, nil),
            ("write_file", true, "/project/Sources/New.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertFalse(result.contains(where: { $0.id == "commit" }))
    }

    // MARK: - Engine: Fix Errors Suggestion

    func testSuggestsFixErrorsAfterFailedCommand() {
        let entries = makeEntries([
            ("run_command", false, nil),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "fix_errors" }))
    }

    func testSuggestsFixErrorsAfterFailedBuild() {
        let entries = makeEntries([
            ("run_build", false, nil),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "fix_errors" }))
    }

    // MARK: - Engine: Maximum Suggestions

    func testMaxSuggestionsCapped() {
        // Create entries that should trigger many suggestions
        let entries = makeEntries([
            ("run_build", false, nil),
            ("run_tests", false, nil),
            ("edit_file", true, "/project/Tests/Test.swift"),
            ("write_file", true, "/project/Sources/A.swift"),
            ("write_file", true, "/project/Sources/B.swift"),
            ("create_file", true, "/project/Sources/C.swift"),
            ("edit_file", true, "/project/Sources/D.swift"),
            ("edit_file", true, "/project/Sources/E.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertLessThanOrEqual(result.count, 4, "Should cap at 4 suggestions")
    }

    func testNoDuplicateSuggestions() {
        let entries = makeEntries([
            ("edit_file", true, "/project/Tests/Test.swift"),
            ("write_file", true, "/project/Sources/A.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        let ids = result.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "No duplicate suggestion IDs")
    }

    // MARK: - Engine: All Suggestions Have Required Fields

    func testAllSuggestionsHaveFields() {
        let entries = makeEntries([
            ("run_build", false, nil),
            ("edit_file", true, "/project/Tests/Test.swift"),
            ("write_file", true, "/project/Sources/A.swift"),
            ("write_file", true, "/project/Sources/B.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        for suggestion in result {
            XCTAssertFalse(suggestion.id.isEmpty)
            XCTAssertFalse(suggestion.title.isEmpty)
            XCTAssertFalse(suggestion.prompt.isEmpty)
            XCTAssertFalse(suggestion.icon.isEmpty)
        }
    }

    // MARK: - Engine: Lint Suggestion

    func testSuggestsFixLintAfterLintWarnings() {
        let entries = makeEntriesWithSummary([
            ("run_linter", true, nil, "3 warnings found"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "fix_lint" }))
    }

    func testNoFixLintIfCleanLintRun() {
        let entries = makeEntriesWithSummary([
            ("run_linter", true, nil, "All clear"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertFalse(result.contains(where: { $0.id == "fix_lint" }))
    }

    func testSuggestsFixLintAfterLintErrors() {
        let entries = makeEntriesWithSummary([
            ("run_linter", true, nil, "2 error(s) detected"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "fix_lint" }))
    }

    // MARK: - Engine: Review Suggestion

    func testSuggestsReviewAfterManyEdits() {
        let entries = makeEntries([
            ("edit_file", true, "/project/Sources/A.swift"),
            ("edit_file", true, "/project/Sources/B.swift"),
            ("write_file", true, "/project/Sources/C.swift"),
            ("create_file", true, "/project/Sources/D.swift"),
            ("edit_file", true, "/project/Sources/E.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "review_code" }))
    }

    func testNoReviewIfFewEdits() {
        let entries = makeEntries([
            ("edit_file", true, "/project/Sources/A.swift"),
            ("edit_file", true, "/project/Sources/B.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertFalse(result.contains(where: { $0.id == "review_code" }))
    }

    // MARK: - Engine: Additional Commit Triggers

    func testDeleteFileTriggersCommitSuggestion() {
        let entries = makeEntries([
            ("delete_file", true, "/project/Sources/Old.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "commit" }))
    }

    func testFindAndReplaceTriggersCommitSuggestion() {
        let entries = makeEntries([
            ("find_and_replace", true, "/project/Sources/Config.swift"),
        ])
        let result = SuggestionEngine.suggest(activityEntries: entries, workingDirectory: "/project")
        XCTAssertTrue(result.contains(where: { $0.id == "commit" }))
    }

    // MARK: - Helpers

    private func makeEntries(_ specs: [(toolName: String, success: Bool, filePath: String?)]) -> [ActivityEntry] {
        specs.enumerated().map { (i, spec) in
            ActivityEntry(
                id: UUID(),
                timestamp: Date().addingTimeInterval(Double(-i)),
                toolName: spec.toolName,
                summary: spec.success ? "OK" : "Failed",
                success: spec.success,
                conversationId: UUID(),
                metadata: spec.filePath.map { ActivityEntry.Metadata(filePath: $0) }
            )
        }
    }

    private func makeEntriesWithSummary(_ specs: [(toolName: String, success: Bool, filePath: String?, summary: String)]) -> [ActivityEntry] {
        specs.enumerated().map { (i, spec) in
            ActivityEntry(
                id: UUID(),
                timestamp: Date().addingTimeInterval(Double(-i)),
                toolName: spec.toolName,
                summary: spec.summary,
                success: spec.success,
                conversationId: UUID(),
                metadata: spec.filePath.map { ActivityEntry.Metadata(filePath: $0) }
            )
        }
    }
}
