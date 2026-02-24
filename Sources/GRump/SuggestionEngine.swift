import Foundation

struct Suggestion: Identifiable, Equatable {
    let id: String
    let title: String
    let prompt: String
    let icon: String
}

/// Produces contextual suggestions based on recent activity and project state.
enum SuggestionEngine {

    private static let maxSuggestions = 4

    /// Analyze recent activity and return up to `maxSuggestions` suggestions.
    static func suggest(activityEntries: [ActivityEntry], workingDirectory: String) -> [Suggestion] {
        var suggestions: [Suggestion] = []

        // --- Run tests? – after editing source or test files ---
        addIfRoom(&suggestions) {
            let testPatterns = ["test", "spec", "specs", "_test", ".test.", "tests/"]
            let recentEdits = activityEntries.prefix(30).filter { e in
                ["write_file", "edit_file", "create_file"].contains(e.toolName) && e.success
            }
            let touchedTestFile = recentEdits.contains { e in
                let path = (e.metadata?.filePath ?? "").lowercased()
                return testPatterns.contains { path.contains($0) }
            }
            let touchedSource = recentEdits.contains { e in
                let path = (e.metadata?.filePath ?? "").lowercased()
                return [".swift", ".ts", ".js", ".py", ".rs", ".go"].contains(where: { path.hasSuffix($0) })
                    && !testPatterns.contains(where: { path.contains($0) })
            }
            guard touchedTestFile || touchedSource else { return nil }
            return Suggestion(
                id: "run_tests",
                title: "Run tests",
                prompt: "Run the test suite to verify the recent changes.",
                icon: "checkmark.circle"
            )
        }

        // --- Build? – after multiple source edits without a build ---
        addIfRoom(&suggestions) {
            let recentEdits = activityEntries.prefix(20).filter { e in
                ["write_file", "edit_file", "create_file"].contains(e.toolName) && e.success
            }
            let hasBuild = activityEntries.prefix(10).contains { $0.toolName == "run_build" && $0.success }
            guard recentEdits.count >= 2, !hasBuild else { return nil }
            return Suggestion(
                id: "run_build",
                title: "Build project",
                prompt: "Build the project to check for compilation errors.",
                icon: "hammer"
            )
        }

        // --- Commit? – after file changes without a commit ---
        addIfRoom(&suggestions) {
            let hasRecentChanges = activityEntries.prefix(20).contains { e in
                ["write_file", "edit_file", "create_file", "delete_file", "find_and_replace"].contains(e.toolName) && e.success
            }
            let hasCommitted = activityEntries.prefix(20).contains { $0.toolName == "git_commit" && $0.success }
            guard hasRecentChanges, !hasCommitted else { return nil }
            return Suggestion(
                id: "commit",
                title: "Commit changes",
                prompt: "Stage and commit the changes with a descriptive message.",
                icon: "vault"
            )
        }

        // --- Fix errors? – after commands/builds that failed ---
        addIfRoom(&suggestions) {
            let recentFailures = activityEntries.prefix(10).filter { e in
                !e.success && ["run_command", "run_build", "run_tests", "run_linter"].contains(e.toolName)
            }
            guard !recentFailures.isEmpty else { return nil }
            let toolName = recentFailures.first?.toolName ?? "run_command"
            let verb = toolName == "run_tests" ? "test" : (toolName == "run_build" ? "build" : "command")
            return Suggestion(
                id: "fix_errors",
                title: "Fix \(verb) errors",
                prompt: "Diagnose and fix the errors from the most recent \(verb) failure.",
                icon: "exclamationmark.triangle"
            )
        }

        // --- Fix lint? – after lint tool reported issues ---
        addIfRoom(&suggestions) {
            let recentLint = activityEntries.prefix(15).filter { e in
                e.toolName == "run_linter" && e.success && !e.summary.isEmpty
            }
            let hasLintOutput = recentLint.contains { e in
                let s = e.summary.lowercased()
                return s.contains("warning") || s.contains("error") || s.contains("issue")
            }
            guard hasLintOutput else { return nil }
            return Suggestion(
                id: "fix_lint",
                title: "Fix lint issues",
                prompt: "Review and fix the lint errors or warnings reported.",
                icon: "paintbrush"
            )
        }

        // --- Review code? – after many edits in a session ---
        addIfRoom(&suggestions) {
            let editCount = activityEntries.prefix(40).filter { e in
                ["write_file", "edit_file", "create_file"].contains(e.toolName) && e.success
            }.count
            guard editCount >= 5 else { return nil }
            return Suggestion(
                id: "review_code",
                title: "Review changes",
                prompt: "Review all changes made in this session for correctness and code quality.",
                icon: "eye"
            )
        }

        return Array(suggestions.prefix(maxSuggestions))
    }

    // MARK: - Helpers

    /// Appends a suggestion if below the limit and the generator returns non-nil.
    private static func addIfRoom(_ suggestions: inout [Suggestion], _ generator: () -> Suggestion?) {
        guard suggestions.count < maxSuggestions,
              let s = generator(),
              !suggestions.contains(where: { $0.id == s.id }) else { return }
        suggestions.append(s)
    }
}
