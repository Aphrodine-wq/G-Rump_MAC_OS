import XCTest
@testable import GRump

@MainActor
final class ToolDispatchTests: XCTestCase {
    
    func testAllToolDefinitionsHaveExecutors() throws {
        // Get all tool definitions
        let allTools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames = allTools.compactMap { tool in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            return name
        }
        
        XCTAssertFalse(toolNames.isEmpty, "Should have tools defined")
        
        // Create a ChatViewModel instance to test method existence
        let viewModel = ChatViewModel()
        
        // Check that each tool name has a corresponding execute method
        for toolName in toolNames {
            let methodName = "execute\(toolName.camelCase)"
            let selector = NSSelectorFromString(methodName)
            
            // Verify the method exists on ChatViewModel
            XCTAssertTrue(viewModel.responds(to: selector), 
                         "Missing executor method for tool: \(toolName) (expected: \(methodName))")
        }
    }
    
    func testCriticalToolExecutorsExist() throws {
        let viewModel = ChatViewModel()
        
        // Test critical file operation tools
        let criticalTools = [
            "readFile", "writeFile", "editFile", "listDirectory", 
            "searchFiles", "grepSearch", "run_command", "web_search"
        ]
        
        for toolName in criticalTools {
            let methodName = "execute\(toolName.camelCase)"
            let selector = NSSelectorFromString(methodName)
            
            XCTAssertTrue(viewModel.responds(to: selector), 
                         "Missing critical tool executor: \(toolName)")
        }
    }
    
    func testGRumpDefaultsConstants() throws {
        // Test that GRumpDefaults contains expected constants
        XCTAssertFalse(GRumpDefaults.defaultSystemPrompt.isEmpty, 
                      "defaultSystemPrompt should not be empty")
        XCTAssertTrue(GRumpDefaults.defaultSystemPrompt.contains("G-Rump"), 
                     "defaultSystemPrompt should contain G-Rump name")
    }
    
    func testAgentModeProperties() throws {
        // Test that all AgentMode cases have required properties
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, 
                          "\(mode) should have non-empty displayName")
            XCTAssertFalse(mode.icon.isEmpty, 
                          "\(mode) should have non-empty icon")
            XCTAssertFalse(mode.description.isEmpty, 
                          "\(mode) should have non-empty description")
            XCTAssertFalse(mode.toastMessage.isEmpty, 
                          "\(mode) should have non-empty toastMessage")
        }
    }
}

// Helper extension for camelCase conversion
extension String {
    var camelCase: String {
        guard !isEmpty else { return self }
        
        let parts = components(separatedBy: "_")
        guard parts.count > 1 else { return self }
        
        return parts.enumerated().map { index, part in
            if index == 0 {
                return part
            } else {
                return part.prefix(1).uppercased() + part.dropFirst()
            }
        }.joined()
    }
}
