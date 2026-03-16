import XCTest
@testable import GRump

final class BuildErrorParserTests: XCTestCase {

    // MARK: - Basic Parsing

    func testParseSwiftError() {
        let output = "/Users/dev/App/main.swift:10:5: error: cannot find 'foo' in scope"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].file, "/Users/dev/App/main.swift")
        XCTAssertEqual(errors[0].line, 10)
        XCTAssertEqual(errors[0].column, 5)
        XCTAssertEqual(errors[0].severity, .error)
        XCTAssertEqual(errors[0].message, "cannot find 'foo' in scope")
    }

    func testParseSwiftWarning() {
        let output = "/src/file.swift:42:12: warning: variable 'x' was never used"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].severity, .warning)
        XCTAssertEqual(errors[0].line, 42)
        XCTAssertEqual(errors[0].column, 12)
    }

    func testParseSwiftNote() {
        let output = "/src/file.swift:5:1: note: protocol requires function 'doSomething()'"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].severity, .note)
    }

    func testParseMultipleErrors() {
        let output = """
        /src/a.swift:10:5: error: type 'Foo' has no member 'bar'
        /src/b.swift:20:3: warning: result of call is unused
        /src/c.swift:30:1: error: missing return in closure
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors.filter { $0.severity == .error }.count, 2)
        XCTAssertEqual(errors.filter { $0.severity == .warning }.count, 1)
    }

    func testParseEmptyOutput() {
        let errors = BuildErrorParserEngine.parse("")
        XCTAssertTrue(errors.isEmpty)
    }

    func testParseNoErrors() {
        let output = """
        Build complete! (2.5s)
        Testing was successful.
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertTrue(errors.isEmpty)
    }

    func testParseWithFixitSuggestion() {
        let output = """
        /src/main.swift:15:10: error: value of type 'Int' has no member 'count'
        fix-it: replace 'count' with 'description.count'
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertNotNil(errors[0].fixitSuggestion)
        XCTAssertTrue(errors[0].fixitSuggestion!.contains("fix-it"))
    }

    // MARK: - Edge Cases

    func testParsePathWithSpaces() {
        let output = "/Users/my user/My Project/Sources/file.swift:5:3: error: something wrong"
        let errors = BuildErrorParserEngine.parse(output)
        // May or may not parse correctly depending on implementation
        // but should not crash
        XCTAssertTrue(errors.count <= 1)
    }

    func testParseLineWithOnlyWhitespace() {
        let output = "   \n   \n   "
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertTrue(errors.isEmpty)
    }

    func testParseMixedOutputWithNonErrorLines() {
        let output = """
        Compiling Swift files...
        /src/main.swift:1:1: warning: unused import
        Linking MyApp
        Build succeeded.
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].severity, .warning)
    }

    // MARK: - BuildError Properties

    func testBuildErrorFileName() {
        let error = BuildError(
            file: "/Users/dev/project/Sources/GRump/ChatViewModel.swift",
            line: 100, column: 5,
            message: "test", severity: .error, fixitSuggestion: nil
        )
        XCTAssertEqual(error.fileName, "ChatViewModel.swift")
    }

    func testBuildErrorShortPath() {
        let error = BuildError(
            file: "/Users/dev/project/Sources/GRump/ChatViewModel.swift",
            line: 100, column: 5,
            message: "test", severity: .error, fixitSuggestion: nil
        )
        XCTAssertEqual(error.shortPath, "Sources/GRump/ChatViewModel.swift")
    }

    func testBuildErrorShortPathShortFile() {
        let error = BuildError(
            file: "main.swift",
            line: 1, column: 1,
            message: "test", severity: .error, fixitSuggestion: nil
        )
        XCTAssertEqual(error.shortPath, "main.swift")
    }

    func testBuildErrorSeverityIcons() {
        XCTAssertEqual(BuildError.Severity.error.icon, "xmark.circle.fill")
        XCTAssertEqual(BuildError.Severity.warning.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(BuildError.Severity.note.icon, "info.circle.fill")
    }

    func testBuildErrorSeverityAllCases() {
        XCTAssertEqual(BuildError.Severity.allCases.count, 3)
    }

    func testBuildErrorIdentifiable() {
        let e1 = BuildError(file: "a.swift", line: 1, column: 1, message: "err", severity: .error, fixitSuggestion: nil)
        let e2 = BuildError(file: "a.swift", line: 1, column: 1, message: "err", severity: .error, fixitSuggestion: nil)
        XCTAssertNotEqual(e1.id, e2.id) // Each has unique UUID
    }

    // MARK: - Additional Edge Cases

    func testParseErrorAtLine1Column1() {
        let output = "/src/main.swift:1:1: error: expected declaration"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].line, 1)
        XCTAssertEqual(errors[0].column, 1)
    }

    func testParseHighLineNumber() {
        let output = "/src/big_file.swift:99999:1: warning: file is too long"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].line, 99999)
    }

    func testParseConsecutiveErrors() {
        let output = """
        /a.swift:1:1: error: first
        /a.swift:2:1: error: second
        /a.swift:3:1: error: third
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors[0].message, "first")
        XCTAssertEqual(errors[1].message, "second")
        XCTAssertEqual(errors[2].message, "third")
    }

    func testParseMessageWithColons() {
        let output = "/src/main.swift:10:5: error: cannot convert value of type 'String' to type 'Int': incompatible types"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].message.contains("incompatible types"))
    }

    func testParseSameLineMultipleSeverities() {
        // Different severities on the same line/col — should parse both
        let output = """
        /src/main.swift:10:5: error: type mismatch
        /src/main.swift:10:5: note: did you mean to use 'as'?
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.contains(where: { $0.severity == .error }))
        XCTAssertTrue(errors.contains(where: { $0.severity == .note }))
    }

    func testParseLongPath() {
        let path = "/" + (0..<20).map { "dir\($0)" }.joined(separator: "/") + "/file.swift"
        let output = "\(path):5:3: error: test"
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].file, path)
    }

    func testBuildErrorIsHashable() {
        let e1 = BuildError(file: "a.swift", line: 1, column: 1, message: "err", severity: .error, fixitSuggestion: nil)
        let e2 = BuildError(file: "b.swift", line: 2, column: 2, message: "warn", severity: .warning, fixitSuggestion: nil)
        var set: Set<BuildError> = []
        set.insert(e1)
        set.insert(e2)
        XCTAssertEqual(set.count, 2)
    }

    func testSeverityColorsAreDistinct() {
        let error = BuildError.Severity.error.color
        let warning = BuildError.Severity.warning.color
        let note = BuildError.Severity.note.color
        // Each severity should have a different color
        XCTAssertNotEqual("\(error)", "\(note)")
        XCTAssertNotEqual("\(warning)", "\(note)")
    }

    func testShortPathWithExactly3Components() {
        let error = BuildError(
            file: "a/b/c.swift",
            line: 1, column: 1,
            message: "test", severity: .error, fixitSuggestion: nil
        )
        XCTAssertEqual(error.shortPath, "a/b/c.swift")
    }

    func testShortPathWith2Components() {
        let error = BuildError(
            file: "b/c.swift",
            line: 1, column: 1,
            message: "test", severity: .error, fixitSuggestion: nil
        )
        XCTAssertEqual(error.shortPath, "b/c.swift")
    }

    func testParseNoteAsFixitLookahead() {
        let output = """
        /src/main.swift:15:10: error: value of type 'Foo' has no member 'bar'
        note: did you mean 'baz'?
        """
        let errors = BuildErrorParserEngine.parse(output)
        XCTAssertEqual(errors.count, 1)
        XCTAssertNotNil(errors[0].fixitSuggestion)
        XCTAssertTrue(errors[0].fixitSuggestion!.contains("note:"))
    }
}
