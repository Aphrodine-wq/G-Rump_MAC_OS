import Foundation
import GRumpCore

public typealias ToolHandler = @Sendable (ToolInvocation, ExecutionContext) async throws -> ToolResult

public struct RegisteredTool: Sendable {
    public let definition: ToolDefinition
    public let handler: ToolHandler
    public init(definition: ToolDefinition, handler: @escaping ToolHandler) {
        self.definition = definition; self.handler = handler
    }
}

public protocol ToolProvider: Sendable {
    var identifier: String { get }
    var tools: [RegisteredTool] { get }
}

public enum CatalogChange: Sendable, Equatable {
    case packsChanged(revision: UInt64, activePacks: [String])
}

public actor ToolRegistry {
    private var toolsByName: [String: RegisteredTool] = [:]
    private var activePacks: Set<String>
    private var revisionValue: UInt64
    private let revisionFile: URL?
    private var continuations: [UUID: AsyncStream<CatalogChange>.Continuation] = [:]

    public init(activePacks: Set<String> = ["gateway", "workspace"], revisionFile: URL? = nil) {
        self.activePacks = activePacks
        self.revisionFile = revisionFile
        if let revisionFile,
           let data = try? Data(contentsOf: revisionFile),
           let text = String(data: data, encoding: .utf8),
           let revision = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.revisionValue = revision
        } else { self.revisionValue = 1 }
    }

    public func register(_ provider: any ToolProvider) throws {
        for tool in provider.tools {
            if toolsByName[tool.definition.name] != nil {
                throw ToolError(code: .executionFailed, message: "Duplicate tool definition: \(tool.definition.name)")
            }
            toolsByName[tool.definition.name] = tool
        }
    }

    public func definition(named name: String) -> ToolDefinition? { toolsByName[name]?.definition }

    public func definitions(activeOnly: Bool = true) -> [ToolDefinition] {
        toolsByName.values.map(\.definition)
            .filter { !activeOnly || activePacks.contains($0.pack) }
            .sorted { $0.name < $1.name }
    }

    public func allPackNames() -> [String] { Array(Set(toolsByName.values.map { $0.definition.pack })).sorted() }
    public func enabledPackNames() -> [String] { activePacks.sorted() }
    public func revision() -> UInt64 { revisionValue }

    @discardableResult
    public func activate(pack: String) throws -> UInt64 {
        guard toolsByName.values.contains(where: { $0.definition.pack == pack }) else {
            throw ToolError(code: .invalidArguments, message: "Unknown tool pack: \(pack)")
        }
        guard activePacks.insert(pack).inserted else { return revisionValue }
        revisionValue &+= 1
        persistRevision()
        let change = CatalogChange.packsChanged(revision: revisionValue, activePacks: activePacks.sorted())
        for continuation in continuations.values { continuation.yield(change) }
        return revisionValue
    }

    public func changes() -> AsyncStream<CatalogChange> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { @Sendable _ in Task { await self.removeContinuation(id) } }
        }
    }

    public func registeredTool(named name: String, requireActive: Bool = true) throws -> RegisteredTool {
        guard let tool = toolsByName[name] else { throw ToolError(code: .unknownTool, message: "Unknown tool: \(name)") }
        if requireActive && !activePacks.contains(tool.definition.pack) {
            throw ToolError(code: .unavailable, message: "Tool pack '\(tool.definition.pack)' is not active",
                            details: ["pack": .string(tool.definition.pack)])
        }
        return tool
    }

    private func removeContinuation(_ id: UUID) { continuations.removeValue(forKey: id) }
    private func persistRevision() {
        guard let revisionFile else { return }
        try? FileManager.default.createDirectory(at: revisionFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("\(revisionValue)\n".utf8).write(to: revisionFile, options: .atomic)
    }
}

public actor ToolExecutor {
    private let registry: ToolRegistry
    private let policy: PolicyEngine

    public init(registry: ToolRegistry, policy: PolicyEngine) { self.registry = registry; self.policy = policy }

    public func execute(_ invocation: ToolInvocation, context: ExecutionContext, requireActive: Bool = true) async -> ToolResult {
        do {
            try await context.cancellation.checkCancellation()
            let registered = try await registry.registeredTool(named: invocation.name, requireActive: requireActive)
            try Self.validate(arguments: invocation.arguments, against: registered.definition.inputSchema)
            try await policy.authorize(definition: registered.definition, invocation: invocation, context: context)
            if case .unavailable(let code, let reason, let platform) = registered.definition.availability {
                throw ToolError(code: ToolError.Code(rawValue: code) ?? .unavailable, message: reason,
                                details: ["platform": platform.map(JSONValue.string) ?? .null])
            }
            try await context.cancellation.checkCancellation()
            let result = try await registered.handler(invocation, context)
            try Task.checkCancellation()
            try await context.cancellation.checkCancellation()
            return result
        } catch let error as ToolError {
            return Self.failure(invocation.id, error)
        } catch is CancellationError {
            return Self.failure(invocation.id, ToolError(code: .cancelled, message: "Tool invocation was cancelled"))
        } catch {
            return Self.failure(invocation.id, ToolError(code: .executionFailed, message: String(describing: error)))
        }
    }

    private static func failure(_ id: String, _ error: ToolError) -> ToolResult {
        let details: JSONValue = [
            "code": .string(error.code.rawValue), "message": .string(error.message),
            "details": error.details ?? .null, "grant_command": error.grantCommand.map(JSONValue.string) ?? .null
        ]
        return ToolResult(invocationID: id, content: [.text(error.description)], structuredContent: details, isError: true)
    }

    public static func validate(arguments: JSONValue, against schema: JSONValue) throws {
        guard case .object(let object) = arguments else {
            throw ToolError(code: .invalidArguments, message: "Tool arguments must be a JSON object")
        }
        guard case .object(let schemaObject) = schema else { return }
        if case .array(let required)? = schemaObject["required"] {
            let missing = required.compactMap(\.stringValue).filter { object[$0] == nil }
            if !missing.isEmpty {
                throw ToolError(code: .invalidArguments, message: "Missing required argument(s): \(missing.joined(separator: ", "))")
            }
        }
        if schemaObject["additionalProperties"]?.boolValue == false,
           case .object(let properties)? = schemaObject["properties"] {
            let unexpected = Set(object.keys).subtracting(properties.keys).sorted()
            if !unexpected.isEmpty {
                throw ToolError(code: .invalidArguments, message: "Unexpected argument(s): \(unexpected.joined(separator: ", "))")
            }
        }
        if case .object(let properties)? = schemaObject["properties"] {
            for (key, value) in object {
                guard case .object(let propertySchema)? = properties[key] else { continue }
                if let expected = propertySchema["type"]?.stringValue, !matches(value, type: expected) {
                    throw ToolError(code: .invalidArguments, message: "Argument '\(key)' must be \(expected)")
                }
                if case .array(let allowed)? = propertySchema["enum"], !allowed.contains(value) {
                    throw ToolError(code: .invalidArguments, message: "Argument '\(key)' is not an allowed value")
                }
            }
        }
    }

    private static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool),
             ("integer", .integer), ("number", .integer), ("number", .number), ("null", .null): true
        default: false
        }
    }
}
