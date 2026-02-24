import Foundation

// MARK: - Activity Entry

struct ActivityEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let toolName: String
    let summary: String
    let success: Bool
    let conversationId: UUID?
    let metadata: Metadata?

    struct Metadata: Codable, Equatable {
        var filePath: String?
        var command: String?
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        toolName: String,
        summary: String,
        success: Bool,
        conversationId: UUID? = nil,
        metadata: Metadata? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.toolName = toolName
        self.summary = summary
        self.success = success
        self.conversationId = conversationId
        self.metadata = metadata
    }
}

// MARK: - Activity Store

/// In-memory activity feed with optional persistence to project `.grump/activity.json`.
final class ActivityStore: ObservableObject {
    @Published private(set) var entries: [ActivityEntry] = []
    private let maxInMemory = 200
    private var persistencePath: String?

    init() {}

    /// Configure persistence path (e.g. workingDirectory + "/.grump/activity.json").
    func setPersistencePath(_ path: String?) {
        persistencePath = path
        if let p = path {
            load(from: p)
        }
    }

    func append(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxInMemory {
            entries = Array(entries.prefix(maxInMemory))
        }
        if let p = persistencePath {
            save(to: p)
        }
    }

    func clear() {
        entries = []
        if let p = persistencePath {
            save(to: p)
        }
    }

    private func load(from path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data) else {
            return
        }
        entries = Array(decoded.prefix(maxInMemory))
    }

    private func save(to path: String) {
        let url = URL(fileURLWithPath: path)
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let data = (try? JSONEncoder().encode(entries)) ?? Data()
        try? data.write(to: url)
    }
}
