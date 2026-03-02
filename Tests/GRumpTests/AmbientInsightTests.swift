import XCTest
@testable import GRump

final class AmbientInsightTests: XCTestCase {

    // MARK: - AmbientInsight Creation

    func testInsightCreation() {
        let insight = AmbientInsight(
            id: UUID(),
            category: .todo,
            title: "TODO found",
            detail: "Line 42: // TODO: fix this",
            filePath: "/src/main.swift",
            lineNumber: 42,
            timestamp: Date()
        )
        XCTAssertEqual(insight.category, .todo)
        XCTAssertEqual(insight.title, "TODO found")
        XCTAssertEqual(insight.filePath, "/src/main.swift")
        XCTAssertEqual(insight.lineNumber, 42)
        XCTAssertFalse(insight.dismissed)
    }

    func testInsightDismissed() {
        var insight = AmbientInsight(
            id: UUID(), category: .error, title: "Error",
            detail: "detail", filePath: "/a.swift", lineNumber: 1, timestamp: Date()
        )
        XCTAssertFalse(insight.dismissed)
        insight.dismissed = true
        XCTAssertTrue(insight.dismissed)
    }

    // MARK: - Category

    func testAllCategories() {
        let categories = AmbientInsight.Category.allCases
        XCTAssertEqual(categories.count, 7)
        XCTAssertTrue(categories.contains(.todo))
        XCTAssertTrue(categories.contains(.unusedImport))
        XCTAssertTrue(categories.contains(.missingTest))
        XCTAssertTrue(categories.contains(.largeFile))
        XCTAssertTrue(categories.contains(.complexity))
        XCTAssertTrue(categories.contains(.error))
        XCTAssertTrue(categories.contains(.security))
    }

    func testCategoryRawValues() {
        XCTAssertEqual(AmbientInsight.Category.todo.rawValue, "TODO")
        XCTAssertEqual(AmbientInsight.Category.unusedImport.rawValue, "Unused Import")
        XCTAssertEqual(AmbientInsight.Category.missingTest.rawValue, "Missing Test")
        XCTAssertEqual(AmbientInsight.Category.largeFile.rawValue, "Large File")
        XCTAssertEqual(AmbientInsight.Category.complexity.rawValue, "Complexity")
        XCTAssertEqual(AmbientInsight.Category.error.rawValue, "Error")
        XCTAssertEqual(AmbientInsight.Category.security.rawValue, "Security")
    }

    func testCategoryIcons() {
        for category in AmbientInsight.Category.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) missing icon")
        }
    }

    func testCategoryColors() {
        for category in AmbientInsight.Category.allCases {
            XCTAssertFalse(category.color.isEmpty, "\(category.rawValue) missing color")
        }
    }

    // MARK: - Equatable

    func testInsightEquatable() {
        let id = UUID()
        let date = Date()
        let a = AmbientInsight(id: id, category: .todo, title: "T", detail: "D", filePath: "/f", lineNumber: 1, timestamp: date)
        let b = AmbientInsight(id: id, category: .todo, title: "T", detail: "D", filePath: "/f", lineNumber: 1, timestamp: date)
        XCTAssertEqual(a, b)
    }

    func testInsightNotEqual() {
        let date = Date()
        let a = AmbientInsight(id: UUID(), category: .todo, title: "A", detail: "D", filePath: "/f", lineNumber: 1, timestamp: date)
        let b = AmbientInsight(id: UUID(), category: .error, title: "B", detail: "D", filePath: "/f", lineNumber: 1, timestamp: date)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Nil Line Number

    func testInsightNilLineNumber() {
        let insight = AmbientInsight(
            id: UUID(), category: .largeFile, title: "Large File",
            detail: "500 lines", filePath: "/big.swift", lineNumber: nil, timestamp: Date()
        )
        XCTAssertNil(insight.lineNumber)
    }
}
