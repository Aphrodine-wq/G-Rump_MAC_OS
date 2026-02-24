import Foundation

/// Minimal MCP client (Swift 5.9 compatible). Connects to MCP servers via stdio or HTTP,
/// lists tools, and calls tools. Converts MCP tool schema to OpenRouter function format.
final class MCPService {
    struct MCPTool: Codable {
        let name: String
        let description: String?
        let inputSchema: InputSchema?

        struct InputSchema: Codable {
            let type: String?
            let properties: [String: Property]?
            let required: [String]?
        }

        struct Property: Codable {
            let type: String?
            let description: String?
            let `default`: String?
        }
    }

    struct ListToolsResult: Codable {
        let tools: [MCPTool]
    }

    /// Fetch tools from an MCP server. Returns OpenRouter-format tool definitions ([[String: Any]]).
    /// Prefix is applied to tool names (e.g. "mcp_fs" for server id "fs").
    static func fetchTools(
        serverId: String,
        transport: MCPServerConfig.Transport
    ) async -> [[String: Any]] {
        do {
            let mcpTools = try await listTools(serverId: serverId, transport: transport)
            let prefix = "mcp_\(serverId)_"
            return mcpTools.map { tool in
                convertToOpenRouter(tool: tool, prefix: prefix)
            }
        } catch {
            return []
        }
    }

    /// Call an MCP tool. Tool name should include prefix (e.g. mcp_fs_read_file).
    /// Returns the tool result as a string.
    static func callTool(
        serverId: String,
        transport: MCPServerConfig.Transport,
        toolNameWithPrefix: String,
        arguments: [String: Any]
    ) async -> String {
        let prefix = "mcp_\(serverId)_"
        let bareName = toolNameWithPrefix.hasPrefix(prefix)
            ? String(toolNameWithPrefix.dropFirst(prefix.count))
            : toolNameWithPrefix

        do {
            let result = try await performCall(serverId: serverId, transport: transport, name: bareName, arguments: arguments)
            return result
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    private static func listTools(serverId: String, transport: MCPServerConfig.Transport) async throws -> [MCPTool] {
        switch transport {
        case .stdio(let command, let args):
            return try await stdioListTools(command: command, args: args, serverId: serverId)
        case .http(let urlStr):
            return try await httpListTools(url: urlStr)
        }
    }

    private static func performCall(
        serverId: String,
        transport: MCPServerConfig.Transport,
        name: String,
        arguments: [String: Any]
    ) async throws -> String {
        switch transport {
        case .stdio(let command, let args):
            return try await stdioCallTool(command: command, args: args, name: name, arguments: arguments, serverId: serverId)
        case .http(let urlStr):
            return try await httpCallTool(url: urlStr, name: name, arguments: arguments)
        }
    }

    // MARK: - Stdio Transport

    private static func stdioListTools(command: String, args: [String], serverId: String) async throws -> [MCPTool] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.environment = MCPCredentialVault.processEnvironment(for: serverId)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading

        defer {
            writer.closeFile()
            process.terminate()
        }

        // Initialize
        try sendJSONRPC(writer: writer, method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: String](),
            "clientInfo": [
                "name": "G-Rump",
                "version": "1.0.0"
            ] as [String: Any]
        ])
        _ = try readJSONRPCResponse(reader: reader)

        // Initialized notification
        try sendJSONRPCNotification(writer: writer, method: "notifications/initialized")

        // tools/list
        try sendJSONRPC(writer: writer, method: "tools/list", params: nil)
        let listResp = try readJSONRPCResponse(reader: reader)
        if let result = listResp["result"] as? [String: Any],
           let list = result["tools"] as? [[String: Any]] {
            return list.compactMap { dict -> MCPTool? in
                guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
                return try? JSONDecoder().decode(MCPTool.self, from: data)
            }
        }
        return []
    }

    private static func stdioCallTool(
        command: String,
        args: [String],
        name: String,
        arguments: [String: Any],
        serverId: String
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + args
        process.environment = MCPCredentialVault.processEnvironment(for: serverId)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading

        defer {
            writer.closeFile()
            process.terminate()
        }

        try sendJSONRPC(writer: writer, method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [String: String](),
            "clientInfo": ["name": "G-Rump", "version": "1.0.0"] as [String: Any]
        ])
        _ = try readJSONRPCResponse(reader: reader)
        try sendJSONRPCNotification(writer: writer, method: "notifications/initialized")

        try sendJSONRPC(writer: writer, method: "tools/call", params: [
            "name": name,
            "arguments": arguments
        ])
        let resp = try readJSONRPCResponse(reader: reader)
        return parseToolCallResponse(resp)
    }

    private static func sendJSONRPC(writer: FileHandle, method: String, params: [String: Any]?) throws {
        var req: [String: Any] = ["jsonrpc": "2.0", "id": Int64(Date().timeIntervalSince1970 * 1000), "method": method]
        if let p = params { req["params"] = p }
        let data = try JSONSerialization.data(withJSONObject: req)
        var line = data
        line.append(0x0a)
        writer.write(line)
    }

    private static func sendJSONRPCNotification(writer: FileHandle, method: String) throws {
        let req: [String: Any] = ["jsonrpc": "2.0", "method": method]
        let data = try JSONSerialization.data(withJSONObject: req)
        var line = data
        line.append(0x0a)
        writer.write(line)
    }

    private static func readJSONRPCResponse(reader: FileHandle) throws -> [String: Any] {
        var buffer = Data()
        let chunkSize = 4096
        while true {
            let chunk = reader.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)
            if let idx = buffer.firstIndex(of: 0x0a) {
                let line = buffer.prefix(upTo: idx)
                buffer = buffer.dropFirst(idx + 1)
                if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   json["result"] != nil || json["error"] != nil {
                    return json
                }
            }
        }
        throw NSError(domain: "MCPService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No JSON-RPC response"])
    }

    private static func parseToolCallResponse(_ resp: [String: Any]) -> String {
        if let err = resp["error"] as? [String: Any],
           let msg = err["message"] as? String {
            return "Error: \(msg)"
        }
        guard let result = resp["result"] as? [String: Any] else {
            return "Error: invalid tool response"
        }
        if let content = result["content"] as? [[String: Any]] {
            var parts: [String] = []
            for item in content {
                if let textVal = item["text"] as? String {
                    parts.append(textVal)
                } else if let textObj = item["text"] as? [String: Any], let t = textObj["text"] as? String {
                    parts.append(t)
                }
            }
            if !parts.isEmpty { return parts.joined(separator: "\n") }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "No content returned"
    }

    // MARK: - HTTP Transport (SSE)

    private static func httpListTools(url: String) async throws -> [MCPTool] {
        guard let baseURL = URL(string: url.hasSuffix("/") ? String(url.dropLast()) : url) else {
            throw NSError(domain: "MCPService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        // MCP HTTP uses POST to sse endpoint for messages - simplified: use messages endpoint
        let messagesURL = baseURL.appendingPathComponent("mcp")
        var req = URLRequest(url: messagesURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2024-11-05", forHTTPHeaderField: "MCP-Protocol-Version")

        let initBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [String: String](),
                "clientInfo": ["name": "G-Rump", "version": "1.0.0"] as [String: Any]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: initBody)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error"] == nil else {
            return []
        }

        let listBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": [String: Any]()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: listBody)
        let (listData, _) = try await URLSession.shared.data(for: req)
        guard let listJson = try JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let result = listJson["result"] as? [String: Any],
              let toolsList = result["tools"] as? [[String: Any]] else {
            return []
        }
        return toolsList.compactMap { dict -> MCPTool? in
            guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? JSONDecoder().decode(MCPTool.self, from: data)
        }
    }

    private static func httpCallTool(url: String, name: String, arguments: [String: Any]) async throws -> String {
        guard let baseURL = URL(string: url.hasSuffix("/") ? String(url.dropLast()) : url) else {
            throw NSError(domain: "MCPService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        let messagesURL = baseURL.appendingPathComponent("mcp")
        var req = URLRequest(url: messagesURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2024-11-05", forHTTPHeaderField: "MCP-Protocol-Version")

        let initBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [String: String](),
                "clientInfo": ["name": "G-Rump", "version": "1.0.0"] as [String: Any]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: initBody)
        _ = try await URLSession.shared.data(for: req)

        let callBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": ["name": name, "arguments": arguments]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: callBody)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Error: invalid response"
        }
        return parseToolCallResponse(json)
    }

    // MARK: - OpenRouter Conversion

    private static func convertToOpenRouter(tool: MCPTool, prefix: String) -> [String: Any] {
        let name = prefix + tool.name
        var params: [String: Any] = ["type": "object", "properties": [String: Any](), "required": [String]()]
        if let schema = tool.inputSchema {
            if let props = schema.properties {
                var propDict = [String: Any]()
                for (k, v) in props {
                    var p: [String: Any] = [:]
                    if let t = v.type { p["type"] = t }
                    if let d = v.description { p["description"] = d }
                    propDict[k] = p
                }
                params["properties"] = propDict
            }
            if let r = schema.required {
                params["required"] = r
            }
        }
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": tool.description ?? "",
                "parameters": params
            ] as [String: Any]
        ]
    }
}
