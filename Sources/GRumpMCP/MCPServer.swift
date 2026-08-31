import Foundation
import GRumpCore
import GRumpTools
import GRumpAgent

public actor GRumpMCPServer {
    public let registry: ToolRegistry
    public let executor: ToolExecutor
    public let context: ExecutionContext
    private let memory: any MemoryStore
    private let skills: any SkillStore
    private var pendingRequests: [String: Task<JSONValue, Never>] = [:]

    public init(registry: ToolRegistry, executor: ToolExecutor, context: ExecutionContext,
                memory: any MemoryStore = DisabledMemoryStore(), skills: any SkillStore = EmptySkillStore()) {
        self.registry = registry; self.executor = executor; self.context = context
        self.memory = memory; self.skills = skills
    }

    public func handle(_ message: JSONValue, protocolHint: String? = nil) async -> JSONValue? {
        guard case .object(let object) = message,
              let method = object["method"]?.stringValue else {
            return error(id: message.objectValue?["id"] ?? .null, code: -32600, message: "Invalid JSON-RPC request")
        }
        let id = object["id"]
        let params = object["params"]?.objectValue ?? [:]
        if method == "notifications/cancelled" || method == "notifications/cancel" {
            if let requestID = params["requestId"] ?? params["id"] { cancel(requestID) }
            return nil
        }
        do {
            let result: JSONValue
            switch method {
            case "initialize": result = try await initialize(params, protocolHint: protocolHint)
            case "ping": result = .object([:])
            case "tools/list": result = await toolsList(params)
            case "tools/call":
                let task = Task { await self.toolsCall(params) }
                if let id { pendingRequests[key(for: id)] = task }
                result = await task.value
                if let id { pendingRequests.removeValue(forKey: key(for: id)) }
            case "resources/list": result = resourcesList()
            case "resources/read": result = try await resourceRead(params)
            case "resources/subscribe", "resources/unsubscribe": result = .object([:])
            case "prompts/list": result = promptsList()
            case "prompts/get": result = try promptGet(params)
            case "notifications/initialized": return nil
            default: throw RPCError(code: -32601, message: "Method not found: \(method)")
            }
            guard let id else { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": result]
        } catch let rpc as RPCError {
            return error(id: id ?? .null, code: rpc.code, message: rpc.message)
        } catch let caught {
            return self.error(id: id ?? .null, code: -32603, message: String(describing: caught))
        }
    }

    private func cancel(_ id: JSONValue) {
        pendingRequests.removeValue(forKey: key(for: id))?.cancel()
    }

    private func key(for id: JSONValue) -> String {
        (try? id.encoded()).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: id)
    }

    private func initialize(_ params: [String: JSONValue], protocolHint: String?) async throws -> JSONValue {
        let requested = protocolHint ?? params["protocolVersion"]?.stringValue
        let version = MCPVersionAdapter.negotiate(requested).rawValue
        return [
            "protocolVersion": .string(version),
            "serverInfo": ["name": "grump", "version": "0.1.0"],
            "capabilities": [
                "tools": ["listChanged": true],
                "resources": ["subscribe": true, "listChanged": true],
                "prompts": ["listChanged": false],
                "logging": .object([:])
            ],
            "instructions": "Use grump_tools_search and grump_tools_describe to discover packs. grump_tools_call reaches inactive-pack tools without requiring a list refresh."
        ]
    }

    private func toolsList(_ params: [String: JSONValue]) async -> JSONValue {
        let definitions = await registry.definitions()
        return ["tools": .array(definitions.map(toolJSON)), "catalogRevision": .integer(Int64(await registry.revision()))]
    }

    private func toolsCall(_ params: [String: JSONValue]) async -> JSONValue {
        guard let name = params["name"]?.stringValue else {
            return mcpError(ToolError(code: .invalidArguments, message: "Missing tool name"))
        }
        let invocation = ToolInvocation(name: name, arguments: params["arguments"] ?? .object([:]))
        let result = await executor.execute(invocation, context: context)
        var content: [JSONValue] = result.content.map { item in
            switch item.kind {
            case .text: return ["type": "text", "text": .string(item.text ?? "")]
            case .json: return ["type": "text", "text": .string((try? item.value?.encoded(prettyPrinted: true)).map { String(decoding: $0, as: UTF8.self) } ?? "null")]
            case .image: return ["type": "image", "data": .string(item.text ?? ""), "mimeType": .string(item.mimeType ?? "application/octet-stream")]
            case .resource: return ["type": "resource_link", "uri": .string(item.uri ?? "")]
            }
        }
        if content.isEmpty { content = [["type": "text", "text": ""]] }
        return ["content": .array(content), "structuredContent": result.structuredContent ?? .null, "isError": .bool(result.isError)]
    }

    private func resourcesList() -> JSONValue {
        ["resources": [
            ["uri": "grump://catalog", "name": "Tool catalog", "mimeType": "application/json"],
            ["uri": "grump://context", "name": "Workspace context", "mimeType": "application/json"],
            ["uri": "grump://skills/enabled", "name": "Enabled skills", "mimeType": "application/json"],
            ["uri": "grump://memory/project", "name": "Opt-in project memory", "mimeType": "application/json"]
        ]]
    }

    private func resourceRead(_ params: [String: JSONValue]) async throws -> JSONValue {
        guard let uri = params["uri"]?.stringValue else { throw RPCError(code: -32602, message: "Missing resource URI") }
        let value: JSONValue
        switch uri {
        case "grump://catalog": value = .array(await registry.definitions(activeOnly: false).map(toolJSON))
        case "grump://context": value = ["workspaceRoots": .array(context.workspaceRoots.map { .string($0.path) }), "activePacks": .array(await registry.enabledPackNames().map(JSONValue.string)), "catalogRevision": .integer(Int64(await registry.revision()))]
        case "grump://skills/enabled":
            let root = context.workspaceRoots.first ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let values = try await skills.enabledSkills(for: root).map { skill -> JSONValue in
                ["id": .string(skill.id), "name": .string(skill.name), "instructions": .string(skill.instructions)]
            }
            value = ["skills": .array(values)]
        case "grump://memory/project":
            let root = context.workspaceRoots.first ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let enabled = await memory.isEnabled
            let messages = enabled ? try await memory.context(for: root) : []
            let encoded = try JSONEncoder().encode(messages)
            value = ["enabled": .bool(enabled), "entries": try JSONValue.decode(data: encoded),
                     "message": .string(enabled ? "Project memory is enabled" : "Project memory is opt-in and disabled for this workspace")]
        default: throw RPCError(code: -32002, message: "Resource not found: \(uri)")
        }
        return ["contents": [["uri": .string(uri), "mimeType": "application/json", "text": .string(String(decoding: try value.encoded(prettyPrinted: true), as: UTF8.self))]]]
    }

    private func promptsList() -> JSONValue {
        ["prompts": [
            ["name": "plan", "description": "Inspect a repository and produce a verifiable implementation plan.", "arguments": [["name": "task", "required": true]]],
            ["name": "build", "description": "Implement a task with scoped tools, tests, and verification.", "arguments": [["name": "task", "required": true]]],
            ["name": "spec", "description": "Turn a product request into an implementation-ready technical specification.", "arguments": [["name": "request", "required": true]]]
        ]]
    }

    private func promptGet(_ params: [String: JSONValue]) throws -> JSONValue {
        guard let name = params["name"]?.stringValue, ["plan", "build", "spec"].contains(name) else { throw RPCError(code: -32602, message: "Unknown prompt") }
        let arguments = params["arguments"]?.objectValue ?? [:]
        let input = arguments["task"]?.stringValue ?? arguments["request"]?.stringValue ?? ""
        let instruction: String
        switch name {
        case "plan": instruction = "Inspect the workspace, identify constraints and risks, then write a sequenced plan with verification checkpoints. Task: \(input)"
        case "build": instruction = "Implement the task in the workspace. Use discovery before mutation, request scoped approval, and verify the result. Task: \(input)"
        default: instruction = "Create an implementation-ready technical specification with public interfaces, data flow, failure behavior, and acceptance tests. Request: \(input)"
        }
        return ["description": .string(name.capitalized + " workflow"), "messages": [["role": "user", "content": ["type": "text", "text": .string(instruction)]]]]
    }

    private func toolJSON(_ definition: ToolDefinition) -> JSONValue {
        let availability: JSONValue
        switch definition.availability {
        case .available: availability = ["available": true]
        case .unavailable(let code, let reason, let platform): availability = ["available": false, "code": .string(code), "reason": .string(reason), "platform": platform.map(JSONValue.string) ?? .null]
        }
        return [
            "name": .string(definition.name), "description": .string(definition.description), "inputSchema": definition.inputSchema,
            "annotations": ["readOnlyHint": .bool(definition.annotations.readOnlyHint), "destructiveHint": .bool(definition.annotations.destructiveHint), "idempotentHint": .bool(definition.annotations.idempotentHint), "openWorldHint": .bool(definition.annotations.openWorldHint)],
            "_meta": ["grump/pack": .string(definition.pack), "grump/risk": .string(definition.annotations.riskLevel.rawValue), "grump/availability": availability]
        ]
    }

    private func mcpError(_ error: ToolError) -> JSONValue { ["content": [["type": "text", "text": .string(error.description)]], "isError": true] }
    private func error(id: JSONValue, code: Int64, message: String) -> JSONValue { ["jsonrpc": "2.0", "id": id, "error": ["code": .integer(code), "message": .string(message)]] }
}

private struct RPCError: Error { let code: Int64; let message: String }
