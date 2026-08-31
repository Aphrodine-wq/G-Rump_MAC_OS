import Foundation

public struct AgentMessage: Codable, Sendable, Equatable, Identifiable {
    public enum Role: String, Codable, Sendable { case system, user, assistant, tool }
    public let id: String
    public let role: Role
    public let content: String
    public let toolInvocation: ToolInvocation?
    public let toolResult: ToolResult?

    public init(id: String = UUID().uuidString, role: Role, content: String,
                toolInvocation: ToolInvocation? = nil, toolResult: ToolResult? = nil) {
        self.id = id; self.role = role; self.content = content
        self.toolInvocation = toolInvocation; self.toolResult = toolResult
    }
}

public enum AgentEvent: Codable, Sendable, Equatable {
    case text(delta: String)
    case reasoning(delta: String)
    case toolStarted(ToolInvocation)
    case toolCompleted(ToolResult)
    case approvalRequested(ApprovalRequest)
    case plan(JSONValue)
    case completed(AgentMessage)
    case cancelled
    case failed(String)
}
