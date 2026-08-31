import Foundation

public enum CapabilityAvailability: Codable, Sendable, Equatable {
    case available
    case unavailable(code: String, reason: String, platform: String?)

    private enum CodingKeys: String, CodingKey { case available, code, reason, platform }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if try values.decode(Bool.self, forKey: .available) { self = .available }
        else {
            self = .unavailable(
                code: try values.decode(String.self, forKey: .code),
                reason: try values.decode(String.self, forKey: .reason),
                platform: try values.decodeIfPresent(String.self, forKey: .platform)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available:
            try values.encode(true, forKey: .available)
        case .unavailable(let code, let reason, let platform):
            try values.encode(false, forKey: .available)
            try values.encode(code, forKey: .code)
            try values.encode(reason, forKey: .reason)
            try values.encodeIfPresent(platform, forKey: .platform)
        }
    }
}

public enum ToolRiskLevel: String, Codable, Sendable, CaseIterable {
    case read, write, shell, network, credentials, destructive
}

public struct ToolAnnotations: Codable, Sendable, Equatable {
    public var title: String?
    public var readOnlyHint: Bool
    public var destructiveHint: Bool
    public var idempotentHint: Bool
    public var openWorldHint: Bool
    public var riskLevel: ToolRiskLevel

    public init(title: String? = nil, readOnlyHint: Bool = false, destructiveHint: Bool = false,
                idempotentHint: Bool = false, openWorldHint: Bool = false, riskLevel: ToolRiskLevel = .read) {
        self.title = title
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
        self.riskLevel = riskLevel
    }
}

public struct ToolDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchema: JSONValue
    public let outputSchema: JSONValue?
    public let annotations: ToolAnnotations
    public let pack: String
    public let availability: CapabilityAvailability

    public init(name: String, description: String, inputSchema: JSONValue,
                outputSchema: JSONValue? = nil, annotations: ToolAnnotations = .init(),
                pack: String, availability: CapabilityAvailability = .available) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.pack = pack
        self.availability = availability
    }
}

public struct ToolInvocation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: JSONValue
    public let metadata: [String: JSONValue]

    public init(id: String = UUID().uuidString, name: String, arguments: JSONValue = .object([:]), metadata: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.metadata = metadata
    }
}

public struct ToolContent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case text, json, image, resource }
    public let kind: Kind
    public let text: String?
    public let value: JSONValue?
    public let mimeType: String?
    public let uri: String?

    public init(kind: Kind, text: String? = nil, value: JSONValue? = nil, mimeType: String? = nil, uri: String? = nil) {
        self.kind = kind; self.text = text; self.value = value; self.mimeType = mimeType; self.uri = uri
    }

    public static func text(_ value: String) -> ToolContent { .init(kind: .text, text: value) }
    public static func json(_ value: JSONValue) -> ToolContent { .init(kind: .json, value: value) }
}

public struct ToolResult: Codable, Sendable, Equatable {
    public let invocationID: String
    public let content: [ToolContent]
    public let structuredContent: JSONValue?
    public let isError: Bool
    public let metadata: [String: JSONValue]

    public init(invocationID: String, content: [ToolContent], structuredContent: JSONValue? = nil,
                isError: Bool = false, metadata: [String: JSONValue] = [:]) {
        self.invocationID = invocationID; self.content = content; self.structuredContent = structuredContent
        self.isError = isError; self.metadata = metadata
    }
}

public struct ToolError: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Codable, Sendable {
        case unknownTool = "unknown_tool"
        case invalidArguments = "invalid_arguments"
        case unavailable = "capability_unavailable"
        case unsupportedPlatform = "unsupported_platform"
        case providerNotInstalled = "provider_not_installed"
        case policyDenied = "policy_denied"
        case approvalRequired = "approval_required"
        case executionFailed = "execution_failed"
        case cancelled
    }

    public let code: Code
    public let message: String
    public let details: JSONValue?
    public let grantCommand: String?
    public var description: String { "\(code.rawValue): \(message)" }

    public init(code: Code, message: String, details: JSONValue? = nil, grantCommand: String? = nil) {
        self.code = code; self.message = message; self.details = details; self.grantCommand = grantCommand
    }
}
