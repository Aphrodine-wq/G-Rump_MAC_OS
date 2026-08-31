import Foundation

public struct ProcessRequest: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: [String: String]
    public let timeout: Duration?
    public let standardInput: Data?

    public init(executable: String, arguments: [String] = [], workingDirectory: URL? = nil,
                environment: [String: String] = [:], timeout: Duration? = nil, standardInput: Data? = nil) {
        self.executable = executable; self.arguments = arguments; self.workingDirectory = workingDirectory
        self.environment = environment; self.timeout = timeout; self.standardInput = standardInput
    }
}

public struct ProcessResult: Codable, Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode; self.standardOutput = standardOutput; self.standardError = standardError
    }
}

public protocol ProcessRunner: Sendable { func run(_ request: ProcessRequest) async throws -> ProcessResult }
public protocol BackgroundProcessRunner: ProcessRunner { func start(_ request: ProcessRequest) async throws -> Int32 }
public protocol CredentialStore: Sendable {
    func value(for key: String) async throws -> String?
    func setValue(_ value: String, for key: String) async throws
}
public protocol GRumpLogger: Sendable { func log(level: LogLevel, message: String, metadata: [String: String]) }
public enum LogLevel: String, Sendable { case debug, info, warning, error }

public actor CancellationHandle {
    private var cancelled = false
    public init() {}
    public func cancel() { cancelled = true }
    public func checkCancellation() throws {
        if cancelled || Task.isCancelled { throw CancellationError() }
    }
}

public struct ExecutionContext: Sendable {
    public let workspaceRoots: [URL]
    public let environment: [String: String]
    public let processRunner: any ProcessRunner
    public let credentialStore: any CredentialStore
    public let logger: any GRumpLogger
    public let approvalProvider: any ApprovalProvider
    public let cancellation: CancellationHandle

    public init(workspaceRoots: [URL], environment: [String: String] = [:], processRunner: any ProcessRunner,
                credentialStore: any CredentialStore, logger: any GRumpLogger,
                approvalProvider: any ApprovalProvider, cancellation: CancellationHandle = .init()) {
        self.workspaceRoots = workspaceRoots.map { $0.standardizedFileURL }
        self.environment = environment; self.processRunner = processRunner; self.credentialStore = credentialStore
        self.logger = logger; self.approvalProvider = approvalProvider; self.cancellation = cancellation
    }

    public func resolveWorkspacePath(_ path: String, mustExist: Bool = false) throws -> URL {
        guard let root = workspaceRoots.first else {
            throw ToolError(code: .policyDenied, message: "No workspace root is configured")
        }
        let candidate = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        let allowed = workspaceRoots.contains { workspace in
            let base = workspace.resolvingSymlinksInPath().path
            return resolved.path == base || resolved.path.hasPrefix(base + "/")
        }
        guard allowed else {
            throw ToolError(code: .policyDenied, message: "Path escapes the configured workspace", details: ["path": .string(path)])
        }
        if mustExist && !FileManager.default.fileExists(atPath: resolved.path) {
            throw ToolError(code: .invalidArguments, message: "Path does not exist: \(path)")
        }
        return resolved
    }

    public func replacingApprovalProvider(_ provider: any ApprovalProvider) -> ExecutionContext {
        ExecutionContext(workspaceRoots: workspaceRoots, environment: environment, processRunner: processRunner,
                         credentialStore: credentialStore, logger: logger, approvalProvider: provider,
                         cancellation: cancellation)
    }
}

public struct NullCredentialStore: CredentialStore {
    public init() {}
    public func value(for key: String) async throws -> String? { ProcessInfo.processInfo.environment[key] }
    public func setValue(_ value: String, for key: String) async throws { throw ToolError(code: .unavailable, message: "Credential storage is unavailable") }
}

public struct StderrLogger: GRumpLogger {
    public init() {}
    public func log(level: LogLevel, message: String, metadata: [String: String] = [:]) {
        let suffix = metadata.isEmpty ? "" : " " + metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        FileHandle.standardError.write(Data("[\(level.rawValue)] \(message)\(suffix)\n".utf8))
    }
}

public struct DenyApprovalProvider: ApprovalProvider {
    public init() {}
    public func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision { .denied(reason: "No interactive approval provider is available") }
}
