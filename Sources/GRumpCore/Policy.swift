import Foundation

public enum ApprovalDecision: Codable, Sendable, Equatable {
    case approved
    case denied(reason: String)
}

public struct ApprovalRequest: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspace: String
    public let tool: String
    public let risk: ToolRiskLevel
    public let argumentsDigest: String?
    public let rationale: String

    public init(id: String = UUID().uuidString, workspace: String, tool: String, risk: ToolRiskLevel,
                argumentsDigest: String? = nil, rationale: String) {
        self.id = id; self.workspace = workspace; self.tool = tool; self.risk = risk
        self.argumentsDigest = argumentsDigest; self.rationale = rationale
    }
}

public protocol ApprovalProvider: Sendable {
    func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision
}

public struct PolicyGrant: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let workspace: String
    public let tool: String?
    public let risk: ToolRiskLevel?
    public let expiresAt: Date?
    public let argumentsDigest: String?

    public init(id: String = UUID().uuidString, workspace: String, tool: String? = nil,
                risk: ToolRiskLevel? = nil, expiresAt: Date? = nil, argumentsDigest: String? = nil) {
        self.id = id; self.workspace = workspace; self.tool = tool; self.risk = risk
        self.expiresAt = expiresAt; self.argumentsDigest = argumentsDigest
    }

    public func matches(_ request: ApprovalRequest, now: Date = Date()) -> Bool {
        guard expiresAt.map({ $0 > now }) ?? true, workspace == request.workspace else { return false }
        if let tool, tool != request.tool { return false }
        if let risk, risk != request.risk { return false }
        if let argumentsDigest, argumentsDigest != request.argumentsDigest { return false }
        return true
    }
}

public actor PolicyEngine {
    private var grants: [PolicyGrant]
    private var hardDeniedTools: Set<String>

    public init(grants: [PolicyGrant] = [], hardDeniedTools: Set<String> = []) {
        self.grants = grants; self.hardDeniedTools = hardDeniedTools
    }

    public func listGrants() -> [PolicyGrant] { grants.sorted { $0.id < $1.id } }
    public func grant(_ grant: PolicyGrant) { grants.removeAll { $0.id == grant.id }; grants.append(grant) }
    public func revoke(id: String) { grants.removeAll { $0.id == id } }
    public func hardDeny(tool: String) { hardDeniedTools.insert(tool) }

    public func authorize(definition: ToolDefinition, invocation: ToolInvocation, context: ExecutionContext) async throws {
        if hardDeniedTools.contains(definition.name) {
            throw ToolError(code: .policyDenied, message: "Tool is denied by host policy: \(definition.name)")
        }
        let effectiveRisk = Self.effectiveRisk(definition: definition, invocation: invocation)
        if effectiveRisk == .read { return }

        let workspace = context.workspaceRoots.first?.path ?? "<none>"
        let digest = Self.stableDigest(invocation.arguments)
        let request = ApprovalRequest(workspace: workspace, tool: definition.name,
                                      risk: effectiveRisk, argumentsDigest: digest,
                                      rationale: "\(definition.name) requests \(effectiveRisk.rawValue) access")
        grants.removeAll { $0.expiresAt.map { $0 <= Date() } ?? false }
        if grants.contains(where: { $0.matches(request) }) { return }

        switch await context.approvalProvider.requestApproval(request) {
        case .approved: return
        case .denied(let reason):
            let command = "grump policy grant --workspace \"\(workspace)\" --tool \(definition.name)"
            throw ToolError(code: .approvalRequired, message: reason, grantCommand: command)
        }
    }

    private static func stableDigest(_ value: JSONValue) -> String? {
        guard let data = try? value.encoded() else { return nil }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    private static func effectiveRisk(definition: ToolDefinition, invocation: ToolInvocation) -> ToolRiskLevel {
        guard case .object(let arguments) = invocation.arguments else { return definition.annotations.riskLevel }
        let pathKeys = ["path", "paths", "source", "destination", "directory", "cwd", "file"]
        let pathValues = pathKeys.flatMap { key -> [String] in
            guard let value = arguments[key] else { return [] }
            if let string = value.stringValue { return [string] }
            if case .array(let values) = value { return values.compactMap(\.stringValue) }
            return []
        }
        if pathValues.contains(where: isSecretPath) { return .credentials }
        if let command = arguments["command"]?.stringValue?.lowercased(),
           ["rm -rf", "git reset --hard", "mkfs", "diskutil erase", "dd if=", "shutdown", "reboot", "sudo "].contains(where: command.contains) {
            return .destructive
        }
        return definition.annotations.riskLevel
    }

    private static func isSecretPath(_ path: String) -> Bool {
        let normalized = "/" + path.lowercased().replacingOccurrences(of: "\\", with: "/")
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".pem") || name.hasSuffix(".p12")
            || name == "id_rsa" || name == "id_ed25519" || normalized.contains("/.ssh/")
            || normalized.contains("/.aws/") || normalized.contains("/.config/gcloud/")
    }
}

public enum PolicyGrantStore {
    public static func load(from url: URL) -> [PolicyGrant] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([PolicyGrant].self, from: data)) ?? []
    }

    public static func save(_ grants: [PolicyGrant], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(grants).write(to: url, options: .atomic)
    }
}
