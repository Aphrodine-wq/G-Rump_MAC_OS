import Foundation

public struct GRumpPaths: Sendable {
    public let configDirectory: URL
    public let dataDirectory: URL

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appendingPathComponent(".grump", isDirectory: true)
        dataDirectory = home.appendingPathComponent(".grump", isDirectory: true)
        #else
        let home = URL(fileURLWithPath: environment["HOME"] ?? FileManager.default.currentDirectoryPath)
        configDirectory = URL(fileURLWithPath: environment["XDG_CONFIG_HOME"] ?? home.appendingPathComponent(".config").path).appendingPathComponent("grump")
        dataDirectory = URL(fileURLWithPath: environment["XDG_DATA_HOME"] ?? home.appendingPathComponent(".local/share").path).appendingPathComponent("grump")
        #endif
    }
}

public struct HarnessRuntime: Sendable {
    public let registry: ToolRegistry
    public let executor: ToolExecutor
    public let policy: PolicyEngine
    public let context: ExecutionContext
    public let memory: any MemoryStore
    public let skills: any SkillStore

    public static func create(workspace: URL, approvalProvider: any ApprovalProvider = DenyApprovalProvider(),
                              processRunner: any ProcessRunner = FoundationProcessRunner(),
                              credentialStore: (any CredentialStore)? = nil,
                              logger: any GRumpLogger = StderrLogger(), paths: GRumpPaths = .init(),
                              memoryEnabled: Bool = false) async throws -> HarnessRuntime {
        let registry = ToolRegistry(revisionFile: paths.dataDirectory.appendingPathComponent("catalog-revision"))
        let policy = PolicyEngine(grants: PolicyGrantStore.load(from: paths.configDirectory.appendingPathComponent("policy-grants.json")))
        #if os(macOS)
        let resolvedCredentials: any CredentialStore = credentialStore ?? KeychainCredentialStore()
        #else
        let resolvedCredentials: any CredentialStore = credentialStore ?? NullCredentialStore()
        #endif
        let context = ExecutionContext(workspaceRoots: [workspace], environment: [:], processRunner: processRunner,
                                       credentialStore: resolvedCredentials, logger: logger, approvalProvider: approvalProvider)
        let memory: any MemoryStore = ProjectMemoryStore(workspace: workspace, enabled: memoryEnabled)
        let skills: any SkillStore = DirectorySkillStore(directories: [
            paths.configDirectory.appendingPathComponent("skills", isDirectory: true),
            workspace.appendingPathComponent(".grump/skills", isDirectory: true)
        ])
        let executor = ToolExecutor(registry: registry, policy: policy)
        let implementations = WorkspaceToolProvider.names.union(CommandToolProvider.names).union(UtilityToolProvider.names)
            .union(WebToolProvider.names).union(ExtendedToolProvider.names).union(AppleToolProvider.names)
        try await registry.register(WorkspaceToolProvider())
        try await registry.register(CommandToolProvider())
        try await registry.register(UtilityToolProvider())
        try await registry.register(WebToolProvider())
        try await registry.register(ExtendedToolProvider())
        try await registry.register(AppleToolProvider())
        try await registry.register(CatalogPlaceholderProvider(excluding: implementations))
        try await registry.register(GatewayToolProvider(registry: registry, executor: executor))
        return HarnessRuntime(registry: registry, executor: executor, policy: policy, context: context,
                              memory: memory, skills: skills)
    }
}
