import Foundation
import GRumpCore

public struct ModelRequest: Codable, Sendable, Equatable {
    public let messages: [AgentMessage]
    public let tools: [ToolDefinition]
    public let metadata: [String: JSONValue]
    public init(messages: [AgentMessage], tools: [ToolDefinition], metadata: [String: JSONValue] = [:]) {
        self.messages = messages; self.tools = tools; self.metadata = metadata
    }
}

public enum ModelEvent: Codable, Sendable, Equatable {
    case text(String)
    case reasoning(String)
    case toolInvocation(ToolInvocation)
    case completed(AgentMessage)
}

public protocol ModelProvider: Sendable {
    func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error>
}
