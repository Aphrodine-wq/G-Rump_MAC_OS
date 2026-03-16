import SwiftUI

/// Smart follow-up suggestion chips that appear after an assistant response.
/// Analyzes the last message to generate contextually relevant next actions.
struct FollowUpChipsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let suggestions: [FollowUpSuggestion]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.lg) {
                ForEach(suggestions) { suggestion in
                    FollowUpChip(
                        suggestion: suggestion,
                        themeManager: themeManager,
                        onTap: { onSelect(suggestion.prompt) }
                    )
                }
            }
            .padding(.horizontal, Spacing.huge)
            .padding(.vertical, Spacing.md)
        }
    }
}

struct FollowUpChip: View {
    let suggestion: FollowUpSuggestion
    let themeManager: ThemeManager
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text(suggestion.label)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .fill(isHovered
                        ? themeManager.palette.effectiveAccent.opacity(0.12)
                        : themeManager.palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .stroke(
                        isHovered
                            ? themeManager.palette.effectiveAccent.opacity(0.4)
                            : themeManager.palette.borderCrisp.opacity(0.3),
                        lineWidth: Border.thin
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(suggestion.label)
    }
}

// MARK: - Model

struct FollowUpSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let prompt: String
    let icon: String
    let category: Category

    enum Category {
        case explain
        case expand
        case fix
        case test
        case refactor
        case deploy
    }
}

// MARK: - Suggestion Generator

enum FollowUpGenerator {
    /// Generate context-aware follow-up suggestions from the last assistant message.
    /// Returns at most 2 suggestions. Returns none in Build mode.
    static func generate(from lastMessage: String, agentMode: AgentMode) -> [FollowUpSuggestion] {
        // Suppress follow-ups entirely in Build mode — user wants action, not more questions
        if agentMode == .fullStack { return [] }

        var suggestions: [FollowUpSuggestion] = []
        let lower = lastMessage.lowercased()

        // Code-related suggestions
        if lower.contains("```") || lower.contains("function") || lower.contains("class") || lower.contains("struct") {
            suggestions.append(FollowUpSuggestion(
                label: "Write tests",
                prompt: "Write comprehensive tests for the code you just provided.",
                icon: "checkmark.diamond",
                category: .test
            ))
            suggestions.append(FollowUpSuggestion(
                label: "Explain this code",
                prompt: "Explain the code you just wrote step by step.",
                icon: "text.magnifyingglass",
                category: .explain
            ))
        }

        // Error-related suggestions
        if lower.contains("error") || lower.contains("fix") || lower.contains("bug") || lower.contains("issue") {
            suggestions.append(FollowUpSuggestion(
                label: "Show the fix",
                prompt: "Show me the complete fix with the full file contents.",
                icon: "wrench",
                category: .fix
            ))
            suggestions.append(FollowUpSuggestion(
                label: "Why did this happen?",
                prompt: "Explain the root cause of this error in detail.",
                icon: "questionmark.circle",
                category: .explain
            ))
        }

        // File modification suggestions
        if lower.contains("created") || lower.contains("modified") || lower.contains("updated") || lower.contains("wrote") {
            suggestions.append(FollowUpSuggestion(
                label: "Run the build",
                prompt: "Build the project and show me any errors.",
                icon: "hammer",
                category: .deploy
            ))
            suggestions.append(FollowUpSuggestion(
                label: "Review changes",
                prompt: "Show me a git diff of all changes made so far.",
                icon: "arrow.left.arrow.right",
                category: .expand
            ))
        }

        // Refactoring suggestions
        if lower.contains("refactor") || lower.contains("improve") || lower.contains("optimize") {
            suggestions.append(FollowUpSuggestion(
                label: "Apply changes",
                prompt: "Apply the refactoring changes to the actual files.",
                icon: "checkmark.circle",
                category: .refactor
            ))
        }

        // Plan-mode suggestions
        if agentMode == .plan || lower.contains("plan") || lower.contains("step") {
            suggestions.append(FollowUpSuggestion(
                label: "Execute the plan",
                prompt: "Execute this plan step by step. Start with step 1.",
                icon: "play.fill",
                category: .deploy
            ))
        }

        // Cap at 2 suggestions — keep the UI clean
        return Array(suggestions.prefix(2))
    }
}
