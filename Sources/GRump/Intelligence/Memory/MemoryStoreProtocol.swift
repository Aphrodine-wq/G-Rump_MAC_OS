import Foundation

// MARK: - Unified Memory Store Protocol
//
// Both MemoryStore (plain-text) and SemanticMemoryStore (vector RAG) conform
// to this protocol, allowing ChatViewModel to work against a single interface.

/// A unified entry returned by any memory store implementation.
struct UnifiedMemoryEntry {
    let id: UUID
    let conversationId: String
    let timestamp: String
    let content: String
}

/// Protocol that all project memory backends conform to.
protocol ProjectMemoryStore {
    var baseDirectory: String { get }

    /// Persist a new memory entry from a conversation turn.
    func addEntry(conversationId: String, userMessage: String, assistantContent: String, toolCallSummary: String)

    /// Retrieve recent/relevant entries for prompt injection.
    func retrieveEntries(query: String, limit: Int) -> [UnifiedMemoryEntry]

    /// Build a formatted block suitable for appending to the system prompt.
    /// Returns nil when no entries are available.
    func memoryBlock(for query: String, limit: Int) -> String?

    /// Total number of stored entries.
    func count() -> Int

    /// Remove all stored entries.
    func clear()
}

// MARK: - Default implementation for memoryBlock

extension ProjectMemoryStore {
    func memoryBlock(for query: String, limit: Int = 5) -> String? {
        let entries = retrieveEntries(query: query, limit: limit)
        guard !entries.isEmpty else { return nil }
        var block = "\n\n## Project Memory\nRelevant context from past conversations:\n"
        for e in entries {
            block += "\n---\n[\(e.timestamp)]\n\(e.content)"
        }
        return block
    }
}
