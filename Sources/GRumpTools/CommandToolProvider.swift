import Foundation
import GRumpCore

public struct CommandToolProvider: ToolProvider {
    public let identifier = "commands"
    public static let names: Set<String> = [
        "run_command", "which", "get_cwd", "get_env", "list_env", "list_processes", "disk_usage", "get_system_info",
        "list_network_interfaces", "git_status", "git_log", "git_diff", "git_branch", "git_show", "git_add", "git_commit",
        "git_stash", "git_checkout", "git_push", "git_pull", "git_remote", "git_tag", "git_reset", "run_build", "run_format",
        "get_package_deps", "npm_install", "pip_install", "cargo_add", "run_linter", "run_tests", "sqlite_query", "sqlite_schema",
        "sqlite_tables", "docker_ps", "docker_images", "docker_run", "docker_build", "docker_logs", "docker_compose_up",
        "docker_compose_down", "kubectl_get", "kubectl_apply", "vercel_deploy", "vercel_logs", "netlify_deploy", "fly_deploy",
        "ping_host", "resolve_dns", "spm_resolve", "type_check"
    ]

    public init() {}
    public var tools: [RegisteredTool] {
        Self.names.sorted().compactMap { name in
            guard let definition = BuiltinToolCatalog.definition(named: name) else { return nil }
            return RegisteredTool(definition: definition) { invocation, context in try await Self.execute(invocation, context) }
        }
    }

    private static func execute(_ invocation: ToolInvocation, _ context: ExecutionContext) async throws -> ToolResult {
        let a = try ToolArguments.object(invocation)
        let root = context.workspaceRoots.first
        let request: ProcessRequest
        switch invocation.name {
        case "run_command":
            let command = try ToolArguments.string("command", in: a)!
            let cwd = try workingDirectory(a, context)
            request = .init(executable: "/bin/sh", arguments: ["-lc", command], workingDirectory: cwd, environment: context.environment)
        case "which": request = .init(executable: "/usr/bin/which", arguments: [try ToolArguments.string("command", in: a)!], workingDirectory: root)
        case "get_cwd": return .success(invocation, text: root?.path ?? FileManager.default.currentDirectoryPath, json: ["path": .string(root?.path ?? FileManager.default.currentDirectoryPath)])
        case "get_env":
            guard let key = try ToolArguments.string("name", in: a, required: false) else {
                let allowed = ProcessInfo.processInfo.environment.merging(context.environment) { _, new in new }.filter { !isSecretName($0.key) }
                return .success(invocation, text: allowed.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"),
                                json: .object(allowed.mapValues(JSONValue.string)))
            }
            let value = context.environment[key] ?? ProcessInfo.processInfo.environment[key]
            return .success(invocation, text: value ?? "", json: ["name": .string(key), "value": value.map(JSONValue.string) ?? .null])
        case "list_env":
            let allowed = ProcessInfo.processInfo.environment.merging(context.environment) { _, new in new }.filter { !isSecretName($0.key) }
            return .success(invocation, text: allowed.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n"),
                            json: .object(allowed.mapValues(JSONValue.string)))
        case "list_processes": request = .init(executable: "/bin/ps", arguments: ["-axo", "pid,ppid,user,%cpu,%mem,command"], workingDirectory: root)
        case "disk_usage": request = .init(executable: "/bin/df", arguments: ["-h", root?.path ?? "."], workingDirectory: root)
        case "get_system_info": request = .init(executable: "/usr/bin/uname", arguments: ["-a"], workingDirectory: root)
        case "list_network_interfaces": request = .init(executable: executable(["/sbin/ifconfig", "/usr/sbin/ifconfig"]), arguments: [], workingDirectory: root)
        case let name where name.hasPrefix("git_"): request = try gitRequest(name, a, context)
        case "run_build": request = try detectedCommand(a, context, explicitKey: "command", choices: [("Package.swift", "swift build"), ("package.json", "npm run build"), ("Cargo.toml", "cargo build"), ("Makefile", "make")])
        case "run_tests": request = try detectedCommand(a, context, explicitKey: "command", choices: [("Package.swift", "swift test"), ("package.json", "npm test"), ("Cargo.toml", "cargo test"), ("pytest.ini", "python -m pytest")])
        case "run_linter": request = try detectedCommand(a, context, explicitKey: "command", choices: [("Package.swift", "swiftlint"), ("package.json", "npx eslint ."), ("Cargo.toml", "cargo clippy --no-deps"), ("pyproject.toml", "ruff check .")])
        case "run_format": request = try detectedCommand(a, context, explicitKey: "command", choices: [("Package.swift", "swiftformat ."), ("package.json", "npx prettier --write ."), ("Cargo.toml", "cargo fmt"), ("pyproject.toml", "ruff format .")])
        case "get_package_deps": return try packageDependencies(invocation, a, context)
        case "npm_install": request = packageInstall("npm", a, context)
        case "pip_install": request = packageInstall("pip", a, context)
        case "cargo_add": request = packageInstall("cargo", a, context)
        case let name where name.hasPrefix("sqlite_"): request = try sqliteRequest(name, a, context)
        case let name where name.hasPrefix("docker_"): request = try dockerRequest(name, a, context)
        case let name where name.hasPrefix("kubectl_"): request = try kubectlRequest(name, a, context)
        case "vercel_deploy": request = .init(executable: "/usr/bin/env", arguments: ["vercel", ToolArguments.bool("production", in: a) ? "--prod" : ""].filter { !$0.isEmpty }, workingDirectory: root)
        case "vercel_logs": request = .init(executable: "/usr/bin/env", arguments: ["vercel", "logs"], workingDirectory: root)
        case "netlify_deploy": request = .init(executable: "/usr/bin/env", arguments: ["netlify", "deploy"] + (ToolArguments.bool("production", in: a) ? ["--prod"] : []), workingDirectory: root)
        case "fly_deploy": request = .init(executable: "/usr/bin/env", arguments: ["flyctl", "deploy"], workingDirectory: root)
        case "ping_host": request = .init(executable: executable(["/sbin/ping", "/bin/ping", "/usr/bin/ping"]), arguments: ["-c", String(ToolArguments.int("count", in: a) ?? 3), try ToolArguments.string("host", in: a)!], workingDirectory: root)
        case "resolve_dns": request = .init(executable: "/usr/bin/env", arguments: ["nslookup", try ToolArguments.string("host", in: a)!], workingDirectory: root)
        case "spm_resolve": request = .init(executable: "/usr/bin/env", arguments: ["swift", "package", "resolve"], workingDirectory: root)
        case "type_check": request = try detectedCommand(a, context, explicitKey: "command", choices: [("Package.swift", "swift build"), ("tsconfig.json", "npx tsc --noEmit"), ("Cargo.toml", "cargo check"), ("pyproject.toml", "python -m mypy .")])
        default: throw ToolError(code: .unknownTool, message: invocation.name)
        }
        let result = try await context.processRunner.run(request)
        let text = merged(result)
        guard result.exitCode == 0 else {
            throw ToolError(code: .executionFailed, message: text, details: ["exit_code": .integer(Int64(result.exitCode))])
        }
        return .success(invocation, text: text, json: ["exit_code": .integer(Int64(result.exitCode)), "stdout": .string(result.standardOutput), "stderr": .string(result.standardError)])
    }

    private static func workingDirectory(_ a: [String: JSONValue], _ context: ExecutionContext) throws -> URL? {
        if let value = try ToolArguments.string("cwd", in: a, required: false) ?? ToolArguments.string("path", in: a, required: false) {
            let url = try context.resolveWorkspacePath(value, mustExist: true)
            var directory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            return directory.boolValue ? url : url.deletingLastPathComponent()
        }
        return context.workspaceRoots.first
    }

    private static func gitRequest(_ name: String, _ a: [String: JSONValue], _ context: ExecutionContext) throws -> ProcessRequest {
        var args: [String]
        switch name {
        case "git_status": args = ["status", "--short", "--branch"]
        case "git_log": args = ["log", "-n", String(ToolArguments.int("limit", in: a) ?? 20)] + (ToolArguments.bool("oneline", in: a, default: true) ? ["--oneline"] : [])
        case "git_diff": args = ["diff"] + (ToolArguments.bool("staged", in: a) ? ["--staged"] : []) + (try optional("ref", a)) + separatorPath(a)
        case "git_branch": args = ["branch"] + (ToolArguments.bool("all", in: a) ? ["--all"] : [])
        case "git_show": args = ["show", try safeToken("ref", a) + ":" + (try ToolArguments.string("path", in: a)!)]
        case "git_add": args = ["add", "--"] + (try ToolArguments.strings("paths", in: a))
        case "git_commit": args = ["commit", "-m", try ToolArguments.string("message", in: a)!]
        case "git_stash":
            let action = try safeToken("action", a)
            guard ["push", "pop"].contains(action) else { throw ToolError(code: .invalidArguments, message: "action must be push or pop") }
            args = ["stash", action] + ((action == "push" ? try ToolArguments.string("message", in: a, required: false) : nil).map { ["-m", $0] } ?? [])
        case "git_checkout":
            let target = try safeToken("target", a)
            let paths = (try? ToolArguments.strings("paths", in: a)) ?? []
            args = target == "--" ? ["checkout", "--"] + paths : ["checkout", target] + (paths.isEmpty ? [] : ["--"] + paths)
        case "git_push": args = ["push", try ToolArguments.string("remote", in: a, required: false) ?? "origin"] + (try optional("branch", a))
        case "git_pull": args = ["pull", try ToolArguments.string("remote", in: a, required: false) ?? "origin"]
        case "git_remote": args = ["remote", "-v"]
        case "git_tag": args = ["tag"] + (try optional("name", a))
        case "git_reset":
            let mode = try safeToken("mode", a)
            guard ["soft", "mixed", "hard"].contains(mode) else { throw ToolError(code: .invalidArguments, message: "mode must be soft, mixed, or hard") }
            args = ["reset", "--" + mode] + (try optional("target", a))
        default: throw ToolError(code: .unknownTool, message: name)
        }
        return .init(executable: "/usr/bin/git", arguments: args, workingDirectory: try workingDirectory(a, context))
    }

    private static func detectedCommand(_ a: [String: JSONValue], _ context: ExecutionContext, explicitKey: String, choices: [(String, String)]) throws -> ProcessRequest {
        let cwd = try workingDirectory(a, context) ?? context.workspaceRoots.first
        if let explicit = try ToolArguments.string(explicitKey, in: a, required: false), !explicit.isEmpty {
            return .init(executable: "/bin/sh", arguments: ["-lc", explicit], workingDirectory: cwd)
        }
        for (marker, command) in choices where FileManager.default.fileExists(atPath: cwd!.appendingPathComponent(marker).path) {
            return .init(executable: "/bin/sh", arguments: ["-lc", command], workingDirectory: cwd)
        }
        throw ToolError(code: .executionFailed, message: "No supported project marker was found")
    }

    private static func packageDependencies(_ invocation: ToolInvocation, _ a: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let cwd = try workingDirectory(a, context) ?? context.workspaceRoots.first!
        for name in ["Package.swift", "package.json", "requirements.txt", "pyproject.toml", "Cargo.toml"] {
            let url = cwd.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return .success(invocation, text: try String(contentsOf: url, encoding: .utf8), json: ["manifest": .string(name)]) }
        }
        throw ToolError(code: .executionFailed, message: "No supported package manifest was found")
    }

    private static func packageInstall(_ tool: String, _ a: [String: JSONValue], _ context: ExecutionContext) -> ProcessRequest {
        let package = a["package"]?.stringValue
        var args: [String]
        switch tool {
        case "npm": args = ["npm", "install"] + (package.map { [$0] } ?? []) + (ToolArguments.bool("dev", in: a) ? ["--save-dev"] : [])
        case "pip": args = ["python3", "-m", "pip", "install"] + (package.map { [$0] } ?? ["-r", "requirements.txt"])
        default: args = ["cargo", "add"] + (package.map { [$0] } ?? []) + (ToolArguments.bool("dev", in: a) ? ["--dev"] : [])
        }
        return .init(executable: "/usr/bin/env", arguments: args, workingDirectory: context.workspaceRoots.first)
    }

    private static func sqliteRequest(_ name: String, _ a: [String: JSONValue], _ context: ExecutionContext) throws -> ProcessRequest {
        let db = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!, mustExist: true)
        let sql: String
        switch name {
        case "sqlite_query":
            sql = try ToolArguments.string("query", in: a)!
            let normalized = sql.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard normalized.hasPrefix("select") || normalized.hasPrefix("pragma") || normalized.hasPrefix("with") else {
                throw ToolError(code: .policyDenied, message: "sqlite_query only permits read-only SELECT, WITH, or PRAGMA statements")
            }
        case "sqlite_schema": sql = ".schema " + (try ToolArguments.string("table", in: a, required: false) ?? "")
        default: sql = ".tables"
        }
        return .init(executable: "/usr/bin/sqlite3", arguments: ["-json", db.path, sql], workingDirectory: context.workspaceRoots.first)
    }

    private static func dockerRequest(_ name: String, _ a: [String: JSONValue], _ context: ExecutionContext) throws -> ProcessRequest {
        var args: [String]
        switch name {
        case "docker_ps": args = ["docker", "ps"] + (ToolArguments.bool("all", in: a) ? ["--all"] : [])
        case "docker_images": args = ["docker", "images"]
        case "docker_run":
            args = ["docker", "run"]
            if ToolArguments.bool("detach", in: a, default: true) { args.append("-d") }
            if let ports = try ToolArguments.string("ports", in: a, required: false) { args += ["-p", ports] }
            if let containerName = try ToolArguments.string("name", in: a, required: false) { args += ["--name", containerName] }
            if case .object(let environment)? = a["env"] {
                for key in environment.keys.sorted() where environment[key]?.stringValue != nil { args += ["-e", "\(key)=\(environment[key]!.stringValue!)"] }
            }
            args.append(try ToolArguments.string("image", in: a)!)
            if let command = try ToolArguments.string("command", in: a, required: false) { args += ["/bin/sh", "-lc", command] }
        case "docker_build":
            args = ["docker", "build", "-t", try ToolArguments.string("tag", in: a)!]
            if let dockerfile = try ToolArguments.string("dockerfile", in: a, required: false) { args += ["-f", dockerfile] }
            args.append(try ToolArguments.string("path", in: a)!)
        case "docker_logs":
            args = ["docker", "logs", "--tail", String(ToolArguments.int("tail", in: a) ?? 100)]
            if ToolArguments.bool("follow", in: a) { args.append("--follow") }
            args.append(try ToolArguments.string("container", in: a)!)
        case "docker_compose_up": args = ["docker", "compose", "up"] + (ToolArguments.bool("detach", in: a, default: true) ? ["-d"] : []) + (ToolArguments.bool("build", in: a) ? ["--build"] : [])
        case "docker_compose_down": args = ["docker", "compose", "down"]
        default: throw ToolError(code: .unknownTool, message: name)
        }
        return .init(executable: "/usr/bin/env", arguments: args, workingDirectory: context.workspaceRoots.first)
    }

    private static func kubectlRequest(_ name: String, _ a: [String: JSONValue], _ context: ExecutionContext) throws -> ProcessRequest {
        var args: [String]
        if name == "kubectl_apply" {
            let file = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!, mustExist: true)
            args = ["kubectl", "apply", "-f", file.path]
            if let namespace = try ToolArguments.string("namespace", in: a, required: false) { args += ["-n", namespace] }
            if ToolArguments.bool("dry_run", in: a) { args += ["--dry-run=server"] }
        } else {
            args = ["kubectl", "get", try ToolArguments.string("resource", in: a)!]
            if let name = try ToolArguments.string("name", in: a, required: false) { args.append(name) }
            if let namespace = try ToolArguments.string("namespace", in: a, required: false) { args += ["-n", namespace] }
            if let output = try ToolArguments.string("output", in: a, required: false) { args += ["-o", output] }
        }
        return .init(executable: "/usr/bin/env", arguments: args, workingDirectory: context.workspaceRoots.first)
    }

    private static func optional(_ key: String, _ a: [String: JSONValue]) throws -> [String] { (try ToolArguments.string(key, in: a, required: false)).map { [$0] } ?? [] }
    private static func separatorPath(_ a: [String: JSONValue]) -> [String] { a["path"]?.stringValue.map { ["--", $0] } ?? [] }
    private static func safeToken(_ key: String, _ a: [String: JSONValue]) throws -> String {
        let value = try ToolArguments.string(key, in: a)!
        guard !value.hasPrefix("-") || ["--soft", "--mixed", "--hard"].contains(value) else { throw ToolError(code: .invalidArguments, message: "Unsafe option in \(key)") }
        return value
    }
    private static func executable(_ choices: [String]) -> String { choices.first { FileManager.default.isExecutableFile(atPath: $0) } ?? choices[0] }
    private static func merged(_ result: ProcessResult) -> String {
        let value = [result.standardOutput, result.standardError].filter { !$0.isEmpty }.joined(separator: result.standardOutput.isEmpty || result.standardError.isEmpty ? "" : "\n")
        return value.isEmpty ? "(no output)" : String(value.prefix(100_000))
    }
    private static func isSecretName(_ key: String) -> Bool {
        let upper = key.uppercased(); return ["TOKEN", "SECRET", "PASSWORD", "API_KEY", "PRIVATE_KEY", "CREDENTIAL"].contains { upper.contains($0) }
    }
}
