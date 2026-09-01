import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import GRumpKit

@main
struct GRumpCLI {
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("grump: \(error)\n".utf8)); exit(1) }
    }

    private static func run() async throws {
        var args = Arguments(Array(CommandLine.arguments.dropFirst()))
        guard let command = args.pop() else { usage(); return }
        switch command {
        case "mcp": try await mcp(&args)
        case "tools": try await tools(&args)
        case "policy": try policy(&args)
        case "daemon": try daemon(&args)
        case "doctor": try await doctor(&args)
        case "run": try await runAgent(&args)
        case "help", "--help", "-h": usage()
        case "version", "--version": print("grump 0.1.0")
        default: throw CLIError("Unknown command: \(command)")
        }
    }

    private static func makeRuntime(_ args: inout Arguments, interactive: Bool = false) async throws -> HarnessRuntime {
        let workspace = URL(fileURLWithPath: args.option("--workspace") ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        let memoryEnabled = args.flag("--memory")
        guard FileManager.default.fileExists(atPath: workspace.path) else { throw CLIError("Workspace does not exist: \(workspace.path)") }
        let approvals: any ApprovalProvider = interactive ? ConsoleApprovalProvider() : DenyApprovalProvider()
        return try await HarnessRuntime.create(workspace: workspace, approvalProvider: approvals, memoryEnabled: memoryEnabled)
    }

    private static func mcp(_ args: inout Arguments) async throws {
        guard args.pop() == "serve" else { throw CLIError("Expected `mcp serve`") }
        let transport = args.option("--transport") ?? "stdio"
        let runtime = try await makeRuntime(&args)
        let server = GRumpMCPServer(registry: runtime.registry, executor: runtime.executor, context: runtime.context,
                                    memory: runtime.memory, skills: runtime.skills)
        if transport == "stdio" { try await StdioMCPTransport.serve(server); return }
        guard transport == "http" else { throw CLIError("Transport must be stdio or http") }
        let paths = GRumpPaths(), token = try mcpToken(args.option("--token"), paths)
        let port = Int(args.option("--port") ?? "18790") ?? 18_790
        FileHandle.standardError.write(Data("listening http://127.0.0.1:\(port)/mcp\nBearer token: \(token)\n".utf8))
        try await HTTPMCPTransport().serve(server, configuration: .init(port: port, bearerToken: token))
    }

    private static func runAgent(_ args: inout Arguments) async throws {
        guard let task = args.pop(), !task.isEmpty else { throw CLIError("Usage: grump run \"<task>\" --workspace <path>") }
        let providerName = args.option("--provider") ?? inferredProvider()
        let modelOverride = args.option("--model") ?? ProcessInfo.processInfo.environment["GRUMP_MODEL"]
        let baseURL = args.option("--base-url")
        let model = try makeModelProvider(provider: providerName, model: modelOverride, baseURL: baseURL)
        let runtime = try await makeRuntime(&args, interactive: true)
        let session = AgentSession(model: model, registry: runtime.registry, memory: runtime.memory,
                                   skills: runtime.skills, approvalProvider: ConsoleApprovalProvider(),
                                   context: runtime.context, policy: runtime.policy)
        var emittedText = false
        for await event in await session.run(task) {
            switch event {
            case .text(let delta):
                emittedText = true
                FileHandle.standardOutput.write(Data(delta.utf8))
            case .reasoning(let delta): FileHandle.standardError.write(Data("[agent] \(delta)\n".utf8))
            case .toolStarted(let invocation): FileHandle.standardError.write(Data("[tool] → \(invocation.name)\n".utf8))
            case .toolCompleted(let result): FileHandle.standardError.write(Data("[tool] ← \(result.invocationID) \(result.isError ? "error" : "ok")\n".utf8))
            case .approvalRequested(let request): FileHandle.standardError.write(Data("[approval] \(request.tool) (\(request.risk.rawValue))\n".utf8))
            case .plan(let plan): FileHandle.standardError.write(Data("[plan] \((try? String(decoding: plan.encoded(), as: UTF8.self)) ?? "")\n".utf8))
            case .completed:
                if emittedText { FileHandle.standardOutput.write(Data("\n".utf8)) }
                return
            case .cancelled: throw CLIError("Agent cancelled")
            case .failed(let message): throw CLIError(message)
            }
        }
    }

    private static func inferredProvider() -> String {
        let environment = ProcessInfo.processInfo.environment
        if environment["ANTHROPIC_API_KEY"]?.isEmpty == false { return "anthropic" }
        if environment["OPENAI_API_KEY"]?.isEmpty == false { return "openai" }
        if environment["OPENROUTER_API_KEY"]?.isEmpty == false { return "openrouter" }
        return "ollama"
    }

    private static func makeModelProvider(provider: String, model: String?, baseURL: String?) throws -> HTTPModelProvider {
        let environment = ProcessInfo.processInfo.environment
        let configuration: HTTPModelConfiguration
        switch provider.lowercased() {
        case "anthropic":
            configuration = .init(api: .anthropic,
                                  endpoint: try endpoint(baseURL ?? "https://api.anthropic.com/v1/messages"),
                                  model: model ?? "claude-opus-5", apiKey: environment["ANTHROPIC_API_KEY"])
        case "openai":
            guard let model else { throw CLIError("Set --model or GRUMP_MODEL for OpenAI") }
            configuration = .init(api: .openAICompatible,
                                  endpoint: try endpoint(baseURL ?? "https://api.openai.com/v1/chat/completions"),
                                  model: model, apiKey: environment["OPENAI_API_KEY"])
        case "openrouter":
            guard let model else { throw CLIError("Set --model or GRUMP_MODEL for OpenRouter") }
            configuration = .init(api: .openAICompatible,
                                  endpoint: try endpoint(baseURL ?? "https://openrouter.ai/api/v1/chat/completions"),
                                  model: model, apiKey: environment["OPENROUTER_API_KEY"],
                                  headers: ["HTTP-Referer": "https://g-rump.app", "X-Title": "G-Rump"])
        case "ollama":
            configuration = .init(api: .openAICompatible,
                                  endpoint: try endpoint(baseURL ?? "http://127.0.0.1:11434/v1/chat/completions"),
                                  model: model ?? "llama3.2:3b")
        default: throw CLIError("Provider must be anthropic, openai, openrouter, or ollama")
        }
        return HTTPModelProvider(configuration: configuration)
    }

    private static func endpoint(_ value: String) throws -> URL {
        guard let url = URL(string: value), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw CLIError("Invalid model endpoint: \(value)")
        }
        return url
    }

    private static func tools(_ args: inout Arguments) async throws {
        guard let action = args.pop() else { throw CLIError("Expected tools list, search, describe, or call") }
        let runtime = try await makeRuntime(&args, interactive: action == "call")
        switch action {
        case "list": try output(await runtime.registry.definitions(activeOnly: !args.flag("--all")))
        case "search":
            let query = (args.pop() ?? "").lowercased()
            try output(await runtime.registry.definitions(activeOnly: false).filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query) })
        case "describe":
            guard let name = args.pop(), let definition = await runtime.registry.definition(named: name) else { throw CLIError("Unknown tool") }
            try output(definition)
        case "call":
            guard let name = args.pop() else { throw CLIError("Missing tool name") }
            let json = args.option("--arguments") ?? args.pop() ?? "{}"
            let result = await runtime.executor.execute(.init(name: name, arguments: try JSONValue.decode(data: Data(json.utf8))), context: runtime.context, requireActive: false)
            try output(result); if result.isError { exit(2) }
        default: throw CLIError("Unknown tools action: \(action)")
        }
    }

    private static func policy(_ args: inout Arguments) throws {
        guard let action = args.pop() else { throw CLIError("Expected policy list, grant, or revoke") }
        let file = GRumpPaths().configDirectory.appendingPathComponent("policy-grants.json")
        var grants = PolicyGrantStore.load(from: file)
        switch action {
        case "list": try output(grants)
        case "grant":
            guard let workspace = args.option("--workspace") else { throw CLIError("--workspace is required") }
            let tool = args.option("--tool"), risk = args.option("--risk").flatMap(ToolRiskLevel.init(rawValue:))
            guard tool != nil || risk != nil else { throw CLIError("Specify --tool or --risk") }
            let duration = args.option("--duration").flatMap(Double.init)
            let grant = PolicyGrant(workspace: URL(fileURLWithPath: workspace).standardizedFileURL.path, tool: tool, risk: risk,
                                    expiresAt: duration.map { Date().addingTimeInterval($0) }, argumentsDigest: args.option("--arguments-digest"))
            grants.append(grant); try PolicyGrantStore.save(grants, to: file); try output(grant)
        case "revoke":
            guard let id = args.pop() ?? args.option("--id") else { throw CLIError("Grant id is required") }
            let count = grants.count; grants.removeAll { $0.id == id }
            guard count != grants.count else { throw CLIError("Grant not found") }
            try PolicyGrantStore.save(grants, to: file); print("revoked \(id)")
        default: throw CLIError("Unknown policy action: \(action)")
        }
    }

    private static func daemon(_ args: inout Arguments) throws {
        guard let action = args.pop() else { throw CLIError("Expected daemon start, stop, or status") }
        let paths = GRumpPaths(), pidFile = paths.dataDirectory.appendingPathComponent("daemon.pid")
        switch action {
        case "start":
            if let pid = pid(pidFile), alive(pid) { print("running pid \(pid)"); return }
            try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
            let workspace = args.option("--workspace") ?? FileManager.default.currentDirectoryPath
            let token = try mcpToken(args.option("--token"), paths)
            let logURL = paths.dataDirectory.appendingPathComponent("daemon.log")
            if !FileManager.default.fileExists(atPath: logURL.path) { _ = FileManager.default.createFile(atPath: logURL.path, contents: nil) }
            let log = try FileHandle(forWritingTo: logURL); try log.seekToEnd()
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["mcp", "serve", "--transport", "http", "--workspace", workspace, "--token", token]
            process.standardOutput = log; process.standardError = log; try process.run()
            try Data("\(process.processIdentifier)\n".utf8).write(to: pidFile, options: .atomic)
            print("started pid \(process.processIdentifier) on http://127.0.0.1:18790/mcp")
        case "status": if let value = pid(pidFile), alive(value) { print("running pid \(value)") } else { print("stopped"); exit(3) }
        case "stop":
            guard let value = pid(pidFile), alive(value) else { print("already stopped"); return }
            guard kill(value, SIGTERM) == 0 else { throw CLIError("Unable to stop pid \(value)") }
            try? FileManager.default.removeItem(at: pidFile); print("stopped pid \(value)")
        default: throw CLIError("Unknown daemon action: \(action)")
        }
    }

    private static func doctor(_ args: inout Arguments) async throws {
        let runtime = try await makeRuntime(&args), tools = await runtime.registry.definitions(activeOnly: false).filter { !$0.name.hasPrefix("grump_") }
        let duplicates = tools.count - Set(tools.map(\.name)).count
        let report: JSONValue = ["status": tools.count == 161 && duplicates == 0 ? "ok" : "error", "tool_count": .integer(Int64(tools.count)),
                                 "duplicate_tool_names": .integer(Int64(duplicates)), "official_mcp_sdk": "0.12.x", "stdio": true,
                                 "streamable_http": true, "catalog_digest": .string(BuiltinToolCatalog.snapshotDigest),
                                 "workspace": .string(runtime.context.workspaceRoots.first?.path ?? "")]
        print(String(decoding: try report.encoded(prettyPrinted: true), as: UTF8.self))
        if tools.count != 161 || duplicates != 0 { exit(2) }
    }

    private static func mcpToken(_ supplied: String?, _ paths: GRumpPaths) throws -> String {
        if let supplied, !supplied.isEmpty { return supplied }
        if let value = ProcessInfo.processInfo.environment["GRUMP_MCP_TOKEN"], !value.isEmpty { return value }
        let file = paths.configDirectory.appendingPathComponent("mcp-token")
        if let value = try? String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let value = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try Data((value + "\n").utf8).write(to: file, options: .atomic); return value
    }
    private static func pid(_ file: URL) -> pid_t? { (try? String(contentsOf: file, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } }
    private static func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }
    private static func output<T: Encodable>(_ value: T) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601; print(String(decoding: try encoder.encode(value), as: UTF8.self)) }
    private static func usage() { print("grump 0.1.0\n  grump mcp serve --transport stdio|http --workspace <path> [--memory]\n  grump daemon start|stop|status\n  grump run \"<task>\" --workspace <path> [--provider anthropic|openai|openrouter|ollama] [--model <id>] [--memory]\n  grump tools list|search|describe|call\n  grump policy list|grant|revoke\n  grump doctor") }
}

private struct Arguments {
    var values: [String]
    init(_ values: [String]) { self.values = values }
    mutating func pop() -> String? { values.isEmpty ? nil : values.removeFirst() }
    mutating func option(_ name: String) -> String? { guard let index = values.firstIndex(of: name), index + 1 < values.count else { return nil }; values.remove(at: index); return values.remove(at: index) }
    mutating func flag(_ name: String) -> Bool { guard let index = values.firstIndex(of: name) else { return false }; values.remove(at: index); return true }
}

private struct CLIError: Error, CustomStringConvertible { let description: String; init(_ value: String) { description = value } }
private actor ConsoleApprovalProvider: ApprovalProvider {
    func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision {
        guard ProcessInfo.processInfo.environment["GRUMP_NONINTERACTIVE"] == nil else { return .denied(reason: "Non-interactive mode denied approval") }
        FileHandle.standardError.write(Data("Approve \(request.risk.rawValue) access for \(request.tool) in \(request.workspace)? [y/N] ".utf8))
        return readLine()?.lowercased().hasPrefix("y") == true ? .approved : .denied(reason: "User denied approval")
    }
}
