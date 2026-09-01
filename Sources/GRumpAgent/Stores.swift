import Foundation
import GRumpCore

public protocol MemoryStore: Sendable {
    var isEnabled: Bool { get async }
    func context(for workspace: URL) async throws -> [AgentMessage]
    func append(_ message: AgentMessage, workspace: URL) async throws
}

public protocol SkillStore: Sendable {
    func enabledSkills(for workspace: URL) async throws -> [Skill]
}

public struct Skill: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let instructions: String
    public init(id: String = UUID().uuidString, name: String, instructions: String) {
        self.id = id; self.name = name; self.instructions = instructions
    }
}

public actor DisabledMemoryStore: MemoryStore {
    public init() {}
    public var isEnabled: Bool { false }
    public func context(for workspace: URL) async throws -> [AgentMessage] { [] }
    public func append(_ message: AgentMessage, workspace: URL) async throws {}
}

public struct EmptySkillStore: SkillStore {
    public init() {}
    public func enabledSkills(for workspace: URL) async throws -> [Skill] { [] }
}
