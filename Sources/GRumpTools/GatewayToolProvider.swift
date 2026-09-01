import Foundation
import GRumpCore

public struct GatewayToolProvider: ToolProvider {
    public let identifier = "gateway"
    private let registry: ToolRegistry
    private let executor: ToolExecutor

    public init(registry: ToolRegistry, executor: ToolExecutor) { self.registry = registry; self.executor = executor }

    public var tools: [RegisteredTool] {
        [
            tool("grump_tools_search", "Search the complete G-Rump tool catalog, including inactive packs.", required: [], properties: ["query": stringSchema("Text matched against tool names and descriptions"), "pack": stringSchema("Optional pack filter")]),
            tool("grump_tools_describe", "Return the exact input schema, annotations, pack, and platform availability for one tool.", required: ["name"], properties: ["name": stringSchema("Tool name")]),
            tool("grump_tools_activate_pack", "Activate a tool pack and advance the deterministic catalog revision.", required: ["pack"], properties: ["pack": stringSchema("Pack identifier")], risk: .write),
            tool("grump_tools_call", "Invoke any catalog tool by name, even when its pack is not active in tools/list.", required: ["name", "arguments"], properties: ["name": stringSchema("Tool name"), "arguments": ["type": "object", "description": "Arguments matching the target tool schema"]]),
            tool("grump_context_snapshot", "Return workspace roots, environment keys, active packs, and catalog revision.", required: [], properties: [:])
        ].map { definition in
            RegisteredTool(definition: definition) { invocation, context in try await execute(invocation, context) }
        }
    }

    private func execute(_ invocation: ToolInvocation, _ context: ExecutionContext) async throws -> ToolResult {
        let arguments = try ToolArguments.object(invocation)
        switch invocation.name {
        case "grump_tools_search":
            let query = (try ToolArguments.string("query", in: arguments, required: false) ?? "").lowercased()
            let pack = try ToolArguments.string("pack", in: arguments, required: false)
            let matches = await registry.definitions(activeOnly: false).filter {
                (pack == nil || $0.pack == pack) && (query.isEmpty || $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query))
            }
            return try encoded(invocation, .array(matches.map { definitionJSON($0) }))
        case "grump_tools_describe":
            let name = try ToolArguments.string("name", in: arguments)!
            guard let definition = await registry.definition(named: name) else { throw ToolError(code: .unknownTool, message: name) }
            return try encoded(invocation, definitionJSON(definition))
        case "grump_tools_activate_pack":
            let revision = try await registry.activate(pack: ToolArguments.string("pack", in: arguments)!)
            return .success(invocation, text: "Catalog revision \(revision)", json: ["revision": .integer(Int64(revision)), "active_packs": .array(await registry.enabledPackNames().map(JSONValue.string))])
        case "grump_tools_call":
            let name = try ToolArguments.string("name", in: arguments)!
            guard !name.hasPrefix("grump_tools_") else { throw ToolError(code: .invalidArguments, message: "Gateway tools cannot recursively invoke gateway tools") }
            let nested = ToolInvocation(id: invocation.id, name: name, arguments: arguments["arguments"] ?? .object([:]), metadata: invocation.metadata)
            return await executor.execute(nested, context: context, requireActive: false)
        case "grump_context_snapshot":
            let value: JSONValue = [
                "workspace_roots": .array(context.workspaceRoots.map { .string($0.path) }),
                "environment_keys": .array(context.environment.keys.sorted().map(JSONValue.string)),
                "active_packs": .array(await registry.enabledPackNames().map(JSONValue.string)),
                "catalog_revision": .integer(Int64(await registry.revision()))
            ]
            return try encoded(invocation, value)
        default: throw ToolError(code: .unknownTool, message: invocation.name)
        }
    }

    private func encoded(_ invocation: ToolInvocation, _ value: JSONValue) throws -> ToolResult {
        .success(invocation, text: String(decoding: try value.encoded(prettyPrinted: true), as: UTF8.self), json: value)
    }

    private func definitionJSON(_ definition: ToolDefinition) -> JSONValue {
        let availability: JSONValue
        switch definition.availability {
        case .available: availability = ["available": true]
        case .unavailable(let code, let reason, let platform): availability = ["available": false, "code": .string(code), "reason": .string(reason), "platform": platform.map(JSONValue.string) ?? .null]
        }
        return [
            "name": .string(definition.name), "description": .string(definition.description), "inputSchema": definition.inputSchema,
            "pack": .string(definition.pack), "risk": .string(definition.annotations.riskLevel.rawValue), "availability": availability
        ]
    }

    private func tool(_ name: String, _ description: String, required: [String], properties: [String: JSONValue], risk: ToolRiskLevel = .read) -> ToolDefinition {
        ToolDefinition(name: name, description: description,
                       inputSchema: ["type": "object", "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": false],
                       annotations: .init(readOnlyHint: risk == .read, riskLevel: risk), pack: "gateway")
    }
    private func stringSchema(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
}
