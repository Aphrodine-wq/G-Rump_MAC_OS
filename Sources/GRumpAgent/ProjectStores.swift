import Foundation
import GRumpCore

/// Project-scoped memory. Construction requires an explicit enabled flag;
/// disabled stores never read or write the workspace memory file.
public actor ProjectMemoryStore: MemoryStore {
    private let enabled: Bool
    private let file: URL
    public init(workspace: URL, enabled: Bool) {
        self.enabled = enabled
        self.file = workspace.appendingPathComponent(".grump/memory.json")
    }
    public var isEnabled: Bool { enabled }
    public func context(for workspace: URL) async throws -> [AgentMessage] {
        guard enabled, let data = try? Data(contentsOf: file) else { return [] }
        return try JSONDecoder().decode([AgentMessage].self, from: data)
    }
    public func append(_ message: AgentMessage, workspace: URL) async throws {
        guard enabled else { return }
        var messages = try await context(for: workspace); messages.append(message)
        if messages.count > 500 { messages.removeFirst(messages.count - 500) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(messages).write(to: file, options: .atomic)
    }
}

public struct DirectorySkillStore: SkillStore {
    private let directories: [URL]
    public init(directories: [URL]) { self.directories = directories }
    public func enabledSkills(for workspace: URL) async throws -> [Skill] {
        var results: [Skill] = []
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let instructionURL = isDirectory ? url.appendingPathComponent("SKILL.md") : url
                guard ["md", "txt"].contains(instructionURL.pathExtension.lowercased()),
                      FileManager.default.fileExists(atPath: instructionURL.path) else { continue }
                results.append(Skill(id: instructionURL.path,
                                     name: isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent,
                                     instructions: try String(contentsOf: instructionURL, encoding: .utf8)))
            }
        }
        return results.sorted { $0.name < $1.name }
    }
}
