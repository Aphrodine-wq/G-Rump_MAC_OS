import Foundation

// MARK: - Tool Progress Helpers
//
// Provides estimated step counts and initial step labels for tool calls,
// used by the tool timeline UI and agent loop.
// Extracted from ChatViewModel+AgentLoop.swift for reusability.

enum ToolProgressHelpers {

    /// Human-readable initial step label for a given tool name.
    static func initialStep(for toolName: String) -> String {
        switch toolName {
        case "read_file", "batch_read_files":
            return "Reading file..."
        case "write_file", "edit_file", "create_file":
            return "Writing file..."
        case "run_command", "system_run":
            return "Executing command..."
        case "search_files", "grep_search":
            return "Searching..."
        case "web_search":
            return "Searching web..."
        case "list_directory", "tree_view":
            return "Listing directory..."
        default:
            return "Processing..."
        }
    }

    /// Estimated total steps for a given tool name (used for progress indicators).
    static func estimatedSteps(for toolName: String) -> Int {
        switch toolName {
        case "read_file", "write_file", "edit_file":
            return 3 // Read -> Process -> Write
        case "run_command", "system_run":
            return 2 // Execute -> Process result
        case "search_files", "grep_search":
            return 2 // Search -> Process results
        case "web_search":
            return 3 // Search -> Fetch -> Process
        case "batch_read_files":
            return 4 // Discover -> Read multiple -> Process -> Format
        default:
            return 2
        }
    }
}
