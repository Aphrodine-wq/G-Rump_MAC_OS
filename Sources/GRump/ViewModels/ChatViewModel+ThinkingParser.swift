import Foundation

// MARK: - Thinking Block Parser
//
// Extracts `<thinking>...</thinking>` blocks from streaming text.
// Models like Claude may emit reasoning traces wrapped in these tags.
// The reasoning text is routed to `thinkingContent` for a collapsible
// "Thinking..." UI, while the visible (non-thinking) text is returned
// for normal rendering.

extension ChatViewModel {

    /// Extracts `<thinking>` blocks from raw streaming text.
    /// - Parameters:
    ///   - rawText: The full text buffer including any thinking blocks.
    ///   - thinkingContent: Inout binding to accumulate thinking text.
    /// - Returns: The visible text with thinking blocks removed.
    static func extractThinkingBlocks(from rawText: String, thinkingContent: inout String) -> String {
        // Fast path: no thinking tags at all
        guard rawText.contains("<thinking>") else { return rawText }

        var visible = ""
        var thinking = ""
        var remaining = rawText[rawText.startIndex...]

        while let openRange = remaining.range(of: "<thinking>") {
            // Everything before the tag is visible
            visible += remaining[remaining.startIndex..<openRange.lowerBound]

            let afterOpen = remaining[openRange.upperBound...]
            if let closeRange = afterOpen.range(of: "</thinking>") {
                // Complete thinking block — extract content
                thinking += afterOpen[afterOpen.startIndex..<closeRange.lowerBound]
                remaining = afterOpen[closeRange.upperBound...]
            } else {
                // Incomplete block (still streaming) — everything after <thinking> is thinking
                thinking += afterOpen
                remaining = afterOpen[afterOpen.endIndex...]
            }
        }

        // Anything after the last block is visible
        visible += remaining
        thinkingContent = thinking
        return visible
    }
}
