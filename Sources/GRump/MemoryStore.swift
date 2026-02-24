import Foundation

/// Persistent project memory: conversation summaries for retrieval-augmented context.
/// Phase 1: No embeddings; stores plain text entries and injects recent ones into the system prompt.
struct MemoryStore: ProjectMemoryStore {
    let baseDirectory: String

    private static let memoryDirName = "memory"
    private static let summariesFileName = "summaries.json"
    private static let maxContentLength = 800
    private static let defaultMaxEntries = 15

    init(baseDirectory: String) {
        self.baseDirectory = (baseDirectory as NSString).standardizingPath
    }

    private var memoryDir: String {
        URL(fileURLWithPath: baseDirectory)
            .appendingPathComponent(".grump")
            .appendingPathComponent(Self.memoryDirName)
            .path
    }

    private var summariesURL: URL {
        URL(fileURLWithPath: memoryDir).appendingPathComponent(Self.summariesFileName)
    }

    /// Add an entry (e.g. after an agent turn completes).
    func addEntry(conversationId: String, userMessage: String, assistantContent: String, toolCallSummary: String = "") {
        guard !baseDirectory.isEmpty else { return }
        let actionPart: String
        if !toolCallSummary.isEmpty {
            actionPart = "Actions: \(String(toolCallSummary.prefix(Self.maxContentLength)))"
        } else {
            actionPart = "Assistant: \(String(assistantContent.prefix(Self.maxContentLength)))"
        }
        let entry = MemoryEntry(
            id: UUID(),
            conversationId: conversationId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            content: "User: \(String(userMessage.prefix(200)))\n\(actionPart)"
        )
        var entries = loadEntries()
        entries.append(entry)
        saveEntries(entries)
    }

    /// Load recent entries for prompt augmentation (most recent first, limited count).
    func recentEntries(limit: Int = defaultMaxEntries) -> [MemoryEntry] {
        let entries = loadEntries()
        return Array(entries.suffix(limit).reversed())
    }

    func retrieveEntries(query: String, limit: Int) -> [UnifiedMemoryEntry] {
        recentEntries(limit: limit).map {
            UnifiedMemoryEntry(id: $0.id, conversationId: $0.conversationId, timestamp: $0.timestamp, content: $0.content)
        }
    }

    /// Count of stored entries.
    func count() -> Int {
        loadEntries().count
    }

    /// Remove all entries.
    func clear() {
        saveEntries([])
    }

    private func loadEntries() -> [MemoryEntry] {
        let url = summariesURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(MemoryStoreFile.self, from: data) else {
            return []
        }
        return decoded.entries
    }

    private func saveEntries(_ entries: [MemoryEntry]) {
        let fm = FileManager.default
        let dir = memoryDir
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        let file = MemoryStoreFile(entries: entries)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: summariesURL)
        }
    }
}

struct MemoryEntry: Codable {
    let id: UUID
    let conversationId: String
    let timestamp: String
    let content: String
}

private struct MemoryStoreFile: Codable {
    var entries: [MemoryEntry]
}
