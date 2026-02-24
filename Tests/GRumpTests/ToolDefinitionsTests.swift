import XCTest
@testable import GRump

final class ToolDefinitionsTests: XCTestCase {

    func testToolsForCurrentPlatformNotEmpty() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        XCTAssertFalse(tools.isEmpty, "Should have at least one tool defined")
    }

    func testAllToolsHaveRequiredFields() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        for tool in tools {
            XCTAssertEqual(tool["type"] as? String, "function", "Tool must have type 'function'")
            let function = tool["function"] as? [String: Any]
            XCTAssertNotNil(function, "Tool must have 'function' key")
            let name = function?["name"] as? String
            XCTAssertNotNil(name, "Tool function must have 'name'")
            XCTAssertFalse(name?.isEmpty ?? true, "Tool name must not be empty")
            let description = function?["description"] as? String
            XCTAssertNotNil(description, "Tool '\(name ?? "?")' must have 'description'")
            XCTAssertFalse(description?.isEmpty ?? true, "Tool '\(name ?? "?")' description must not be empty")
        }
    }

    func testToolNamesAreUnique() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "Tool names must be unique, found duplicates: \(names.filter { name in names.filter { $0 == name }.count > 1 })")
    }

    func testCriticalToolsExist() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let names = Set(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        let required = ["read_file", "write_file", "edit_file", "list_directory", "run_command", "search_files", "grep_search", "web_search"]
        for toolName in required {
            XCTAssertTrue(names.contains(toolName), "Critical tool '\(toolName)' must exist")
        }
    }

    func testToolsFilteredWithDenylist() {
        let allTools = ToolDefinitions.toolsFiltered(allowlist: nil, userDenylist: [])
        let filtered = ToolDefinitions.toolsFiltered(allowlist: nil, userDenylist: ["read_file", "write_file"])
        XCTAssertLessThan(filtered.count, allTools.count, "Denylist should reduce tool count")
        let filteredNames = Set(filtered.compactMap { ($0["function"] as? [String: Any])?["name"] as? String })
        XCTAssertFalse(filteredNames.contains("read_file"))
        XCTAssertFalse(filteredNames.contains("write_file"))
    }
}
