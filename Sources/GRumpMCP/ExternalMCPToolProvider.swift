import Foundation
import GRumpCore
import GRumpTools

public protocol ExternalMCPClient: Sendable {
    func callTool(name: String, arguments: JSONValue) async throws -> ToolResult
}

public struct ExternalMCPTool: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let annotations: ToolAnnotations
    public init(name: String, description: String, inputSchema: JSONValue, annotations: ToolAnnotations = .init()) {
        self.name = name; self.description = description; self.inputSchema = inputSchema; self.annotations = annotations
    }
}

/// Re-exports language-neutral MCP extensions under stable namespaced IDs.
/// External processes never load into G-Rump's address space.
public struct ExternalMCPToolProvider: ToolProvider {
    public let identifier: String
    private let namespace: String
    private let externalTools: [ExternalMCPTool]
    private let client: any ExternalMCPClient

    public init(namespace: String, tools: [ExternalMCPTool], client: any ExternalMCPClient) throws {
        let valid = namespace.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard valid, !namespace.isEmpty else { throw ToolError(code: .invalidArguments, message: "Invalid MCP namespace") }
        self.namespace = namespace; self.identifier = "mcp:\(namespace)"; self.externalTools = tools; self.client = client
    }

    public var tools: [RegisteredTool] {
        externalTools.map { external in
            let definition = ToolDefinition(name: "\(namespace).\(external.name)", description: external.description,
                                            inputSchema: external.inputSchema, annotations: external.annotations,
                                            pack: "mcp:\(namespace)")
            return RegisteredTool(definition: definition) { invocation, _ in
                let result = try await client.callTool(name: external.name, arguments: invocation.arguments)
                return ToolResult(invocationID: invocation.id, content: result.content, structuredContent: result.structuredContent,
                                  isError: result.isError, metadata: result.metadata)
            }
        }
    }
}
