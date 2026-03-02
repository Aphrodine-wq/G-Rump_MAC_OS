import XCTest
@testable import GRump

final class LSPServiceTests: XCTestCase {

    // MARK: - LSPDiagnostic

    func testDiagnosticSeverityIcons() {
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.error.icon, "xmark.circle.fill")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.warning.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.information.icon, "info.circle.fill")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.hint.icon, "lightbulb.fill")
    }

    func testDiagnosticSeverityLabels() {
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.error.label, "Error")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.warning.label, "Warning")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.information.label, "Info")
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.hint.label, "Hint")
    }

    func testDiagnosticSeverityRawValues() {
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.error.rawValue, 1)
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.warning.rawValue, 2)
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.information.rawValue, 3)
        XCTAssertEqual(LSPDiagnostic.DiagnosticSeverity.hint.rawValue, 4)
    }

    func testDiagnosticInit() {
        let diag = LSPDiagnostic(
            file: "/test.swift",
            line: 10,
            column: 5,
            severity: .error,
            message: "Expected ';'",
            source: "sourcekit"
        )
        XCTAssertEqual(diag.file, "/test.swift")
        XCTAssertEqual(diag.line, 10)
        XCTAssertEqual(diag.column, 5)
        XCTAssertEqual(diag.severity, .error)
        XCTAssertEqual(diag.message, "Expected ';'")
        XCTAssertEqual(diag.source, "sourcekit")
    }

    func testDiagnosticUniqueIDs() {
        let a = LSPDiagnostic(file: "a.swift", line: 1, column: 1, severity: .error, message: "msg", source: "s")
        let b = LSPDiagnostic(file: "a.swift", line: 1, column: 1, severity: .error, message: "msg", source: "s")
        XCTAssertNotEqual(a.id, b.id, "Each diagnostic should have a unique ID")
    }

    func testDiagnosticHashable() {
        let a = LSPDiagnostic(file: "a.swift", line: 1, column: 1, severity: .error, message: "msg", source: "s")
        var set = Set<LSPDiagnostic>()
        set.insert(a)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - LSPCompletionItem

    func testCompletionItemInit() {
        let item = LSPCompletionItem(
            label: "myFunc",
            detail: "() -> Void",
            kind: .function,
            insertText: "myFunc()"
        )
        XCTAssertEqual(item.label, "myFunc")
        XCTAssertEqual(item.detail, "() -> Void")
        XCTAssertEqual(item.kind, .function)
        XCTAssertEqual(item.insertText, "myFunc()")
    }

    func testCompletionKindIcons() {
        XCTAssertEqual(LSPCompletionItem.CompletionKind.method.icon, "f.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.function.icon, "f.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.variable.icon, "v.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.classKind.icon, "c.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.enumCase.icon, "e.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.keyword.icon, "k.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.module.icon, "m.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.snippet.icon, "text.badge.plus")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.constructor.icon, "hammer")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.constant.icon, "number.square")
        XCTAssertEqual(LSPCompletionItem.CompletionKind.typeParameter.icon, "t.square")
    }

    func testCompletionKindRawValues() {
        XCTAssertEqual(LSPCompletionItem.CompletionKind.text.rawValue, 1)
        XCTAssertEqual(LSPCompletionItem.CompletionKind.method.rawValue, 2)
        XCTAssertEqual(LSPCompletionItem.CompletionKind.function.rawValue, 3)
        XCTAssertEqual(LSPCompletionItem.CompletionKind.constructor.rawValue, 4)
        XCTAssertEqual(LSPCompletionItem.CompletionKind.field.rawValue, 5)
        XCTAssertEqual(LSPCompletionItem.CompletionKind.unknown.rawValue, 0)
    }

    func testCompletionItemHashable() {
        let item = LSPCompletionItem(label: "test", detail: nil, kind: .method, insertText: nil)
        var set = Set<LSPCompletionItem>()
        set.insert(item)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - LSPHoverInfo

    func testHoverInfoInit() {
        let hover = LSPHoverInfo(contents: "Documentation here", range: nil)
        XCTAssertEqual(hover.contents, "Documentation here")
        XCTAssertNil(hover.range)
    }

    func testHoverInfoWithRange() {
        let range = NSRange(location: 10, length: 5)
        let hover = LSPHoverInfo(contents: "doc", range: range)
        XCTAssertEqual(hover.range?.location, 10)
        XCTAssertEqual(hover.range?.length, 5)
    }

    // MARK: - LSPLocation

    func testLocationInit() {
        let loc = LSPLocation(file: "/test.swift", line: 42, column: 7)
        XCTAssertEqual(loc.file, "/test.swift")
        XCTAssertEqual(loc.line, 42)
        XCTAssertEqual(loc.column, 7)
    }

    func testLocationUniqueIDs() {
        let a = LSPLocation(file: "a.swift", line: 1, column: 1)
        let b = LSPLocation(file: "a.swift", line: 1, column: 1)
        XCTAssertNotEqual(a.id, b.id)
    }
}
