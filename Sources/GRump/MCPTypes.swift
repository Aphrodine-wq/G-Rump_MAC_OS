import Foundation

// MARK: - MCP Protocol Types
// Spec-compliant types for Model Context Protocol (2024-11-05)

// MARK: Connection State

enum MCPConnectionState: Equatable {
    case disconnected
    case connecting
    case initializing
    case ready
    case error(String)

    var isConnected: Bool {
        if case .ready = self { return true }
        return false
    }

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .initializing: return "Initializing"
        case .ready: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.clockwise"
        case .initializing: return "gearshape"
        case .ready: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Server Capabilities

struct MCPServerCapabilities: Codable, Equatable {
    var tools: ToolsCapability?
    var resources: ResourcesCapability?
    var prompts: PromptsCapability?
    var logging: LoggingCapability?

    struct ToolsCapability: Codable, Equatable {
        var listChanged: Bool?
    }

    struct ResourcesCapability: Codable, Equatable {
        var subscribe: Bool?
        var listChanged: Bool?
    }

    struct PromptsCapability: Codable, Equatable {
        var listChanged: Bool?
    }

    struct LoggingCapability: Codable, Equatable {}
}

struct MCPClientCapabilities: Codable {
    var roots: RootsCapability?
    var sampling: SamplingCapability?

    struct RootsCapability: Codable {
        var listChanged: Bool?
    }

    struct SamplingCapability: Codable {}
}

// MARK: - Server Info

struct MCPServerInfo: Codable, Equatable {
    let name: String
    let version: String
}

struct MCPClientInfo: Codable {
    let name: String
    let version: String
}

// MARK: - Initialize

struct MCPInitializeParams: Codable {
    let protocolVersion: String
    let capabilities: MCPClientCapabilities
    let clientInfo: MCPClientInfo
}

struct MCPInitializeResult: Codable {
    let protocolVersion: String
    let capabilities: MCPServerCapabilities
    let serverInfo: MCPServerInfo
}

// MARK: - Tools

struct MCPToolDefinition: Codable, Equatable, Identifiable {
    let name: String
    let description: String?
    let inputSchema: JSONSchema?

    var id: String { name }
}

struct JSONSchema: Codable, Equatable {
    let type: String?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?
    let items: JSONSchemaProperty?
    let description: String?
    let additionalProperties: Bool?

    init(type: String? = nil, properties: [String: JSONSchemaProperty]? = nil, required: [String]? = nil, items: JSONSchemaProperty? = nil, description: String? = nil, additionalProperties: Bool? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
        self.items = items
        self.description = description
        self.additionalProperties = additionalProperties
    }
}

struct JSONSchemaProperty: Codable, Equatable {
    let type: String?
    let description: String?
    let `enum`: [String]?
    let `default`: AnyCodableValue?
    let items: JSONSchemaPropertyRef?
    let properties: [String: JSONSchemaProperty]?
    let required: [String]?

    init(type: String? = nil, description: String? = nil, `enum`: [String]? = nil, `default`: AnyCodableValue? = nil, items: JSONSchemaPropertyRef? = nil, properties: [String: JSONSchemaProperty]? = nil, required: [String]? = nil) {
        self.type = type
        self.description = description
        self.enum = `enum`
        self.default = `default`
        self.items = items
        self.properties = properties
        self.required = required
    }
}

/// Indirect wrapper for recursive JSON schema references.
final class JSONSchemaPropertyRef: Codable, Equatable {
    let value: JSONSchemaProperty

    init(_ value: JSONSchemaProperty) { self.value = value }

    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    init(from decoder: Decoder) throws { value = try JSONSchemaProperty(from: decoder) }
    static func == (lhs: JSONSchemaPropertyRef, rhs: JSONSchemaPropertyRef) -> Bool { lhs.value == rhs.value }
}

struct MCPToolCallParams: Codable {
    let name: String
    let arguments: [String: AnyCodableValue]?
}

// MARK: - Content Blocks

enum MCPContentBlock: Codable, Equatable {
    case text(String)
    case image(data: String, mimeType: String)
    case resource(MCPResourceContent)

    enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, resource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try c.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try c.decode(String.self, forKey: .data)
            let mime = try c.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mime)
        case "resource":
            let res = try c.decode(MCPResourceContent.self, forKey: .resource)
            self = .resource(res)
        default:
            self = .text("[unknown content type: \(type)]")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type)
            try c.encode(text, forKey: .text)
        case .image(let data, let mime):
            try c.encode("image", forKey: .type)
            try c.encode(data, forKey: .data)
            try c.encode(mime, forKey: .mimeType)
        case .resource(let res):
            try c.encode("resource", forKey: .type)
            try c.encode(res, forKey: .resource)
        }
    }

    var textValue: String? {
        if case .text(let t) = self { return t }
        return nil
    }
}

struct MCPToolResult: Codable, Equatable {
    let content: [MCPContentBlock]
    let isError: Bool?

    var textContent: String {
        content.compactMap(\.textValue).joined(separator: "\n")
    }
}

// MARK: - Resources

struct MCPResource: Codable, Equatable, Identifiable {
    let uri: String
    let name: String
    let description: String?
    let mimeType: String?

    var id: String { uri }
}

struct MCPResourceContent: Codable, Equatable {
    let uri: String
    let mimeType: String?
    let text: String?
    let blob: String? // base64-encoded
}

struct MCPResourceTemplate: Codable, Equatable, Identifiable {
    let uriTemplate: String
    let name: String
    let description: String?
    let mimeType: String?

    var id: String { uriTemplate }
}

// MARK: - Prompts

struct MCPPrompt: Codable, Equatable, Identifiable {
    let name: String
    let description: String?
    let arguments: [MCPPromptArgument]?

    var id: String { name }
}

struct MCPPromptArgument: Codable, Equatable {
    let name: String
    let description: String?
    let required: Bool?
}

struct MCPPromptMessage: Codable, Equatable {
    let role: String // "user" or "assistant"
    let content: MCPContentBlock
}

struct MCPGetPromptResult: Codable, Equatable {
    let description: String?
    let messages: [MCPPromptMessage]
}

// MARK: - Sampling (server → client)

struct MCPSamplingRequest: Codable {
    let messages: [MCPSamplingMessage]
    let modelPreferences: MCPModelPreferences?
    let systemPrompt: String?
    let includeContext: String? // "none", "thisServer", "allServers"
    let temperature: Double?
    let maxTokens: Int
}

struct MCPSamplingMessage: Codable {
    let role: String
    let content: MCPContentBlock
}

struct MCPModelPreferences: Codable {
    let hints: [MCPModelHint]?
    let costPriority: Double?
    let speedPriority: Double?
    let intelligencePriority: Double?
}

struct MCPModelHint: Codable {
    let name: String?
}

struct MCPSamplingResult: Codable {
    let role: String
    let content: MCPContentBlock
    let model: String
    let stopReason: String?
}

// MARK: - Logging

struct MCPLogEntry: Codable {
    let level: String // "debug", "info", "warning", "error", "critical"
    let logger: String?
    let data: AnyCodableValue?
}

// MARK: - JSON-RPC

struct JSONRPCRequest: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let method: String
    let params: AnyCodableValue?

    init(method: String, params: AnyCodableValue? = nil, id: JSONRPCId? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// Create a request with a numeric id.
    static func request(id: Int64, method: String, params: [String: Any]? = nil) -> JSONRPCRequest {
        let p: AnyCodableValue? = params.flatMap { AnyCodableValue.from($0) }
        return JSONRPCRequest(method: method, params: p, id: .int(id))
    }

    /// Create a notification (no id).
    static func notification(method: String, params: [String: Any]? = nil) -> JSONRPCRequest {
        let p: AnyCodableValue? = params.flatMap { AnyCodableValue.from($0) }
        return JSONRPCRequest(method: method, params: p, id: nil)
    }
}

enum JSONRPCId: Codable, Equatable {
    case int(Int64)
    case string(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(JSONRPCId.self, .init(codingPath: decoder.codingPath, debugDescription: "Expected int or string"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String
    let id: JSONRPCId?
    let result: AnyCodableValue?
    let error: JSONRPCError?
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: AnyCodableValue?
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for arbitrary JSON.
enum AnyCodableValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int64.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyCodableValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyCodableValue].self) { self = .object(o); return }
        throw DecodingError.typeMismatch(AnyCodableValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Convert from untyped [String: Any] dictionary.
    static func from(_ value: Any) -> AnyCodableValue? {
        if value is NSNull { return .null }
        if let b = value as? Bool { return .bool(b) }
        if let i = value as? Int { return .int(Int64(i)) }
        if let i = value as? Int64 { return .int(i) }
        if let d = value as? Double { return .double(d) }
        if let s = value as? String { return .string(s) }
        if let a = value as? [Any] { return .array(a.compactMap { from($0) }) }
        if let o = value as? [String: Any] {
            return .object(o.compactMapValues { from($0) })
        }
        return nil
    }

    /// Convert to untyped Any for JSONSerialization compatibility.
    var toAny: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.toAny)
        case .object(let o): return o.mapValues(\.toAny)
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case .int(let i) = self { return Int(i) }
        return nil
    }

    var objectValue: [String: AnyCodableValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [AnyCodableValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
}

// MARK: - Connection Summary (for UI)

struct MCPConnectionSummary: Identifiable, Equatable {
    let serverId: String
    var state: MCPConnectionState
    var serverInfo: MCPServerInfo?
    var capabilities: MCPServerCapabilities?
    var toolCount: Int
    var resourceCount: Int
    var promptCount: Int

    var id: String { serverId }
}
