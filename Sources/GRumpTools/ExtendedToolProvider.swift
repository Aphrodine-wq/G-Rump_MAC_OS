import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import GRumpCore

public struct ExtendedToolProvider: ToolProvider {
    public let identifier = "extended-portable"
    public static let names: Set<String> = [
        "add_goal", "ask_user", "ast_parse", "browser_evaluate", "browser_open", "browser_screenshot",
        "code_complexity", "dependency_graph", "find_references", "generate_embeddings", "get_process_info",
        "image_convert", "image_info", "image_resize", "kill_process", "port_scan", "propose_skill",
        "read_env_file", "record_lesson", "reflect", "remember", "run_background", "semantic_search",
        "ssl_check", "summarize_text", "system_run", "update_plan", "view_code_outline", "websocket_send",
        "write_env_file", "yaml_parse"
    ]

    public init() {}
    public var tools: [RegisteredTool] {
        Self.names.sorted().compactMap { name in
            guard let definition = BuiltinToolCatalog.definition(named: name) else { return nil }
            return RegisteredTool(definition: definition) { invocation, context in try await Self.execute(invocation, context) }
        }
    }

    private static func execute(_ invocation: ToolInvocation, _ context: ExecutionContext) async throws -> ToolResult {
        let arguments = try ToolArguments.object(invocation)
        switch invocation.name {
        case "ask_user":
            return try encoded(invocation, ["status": "interaction_required", "question": arguments["question"] ?? .null,
                                            "options": arguments["options"] ?? .array([])])
        case "get_process_info":
            return try await process(invocation, context, executable: "/bin/ps",
                                     arguments: ["-p", String(ToolArguments.int("pid", in: arguments)!), "-o", "pid=,ppid=,user=,state=,%cpu=,%mem=,command="])
        case "kill_process":
            let pid = ToolArguments.int("pid", in: arguments)!, signal = ToolArguments.int("signal", in: arguments) ?? 15
            guard pid > 1, (1...31).contains(signal) else { throw ToolError(code: .invalidArguments, message: "Invalid pid or signal") }
            #if canImport(Darwin)
            guard Darwin.kill(Int32(pid), Int32(signal)) == 0 else { throw ToolError(code: .executionFailed, message: String(cString: strerror(errno))) }
            #else
            guard Glibc.kill(Int32(pid), Int32(signal)) == 0 else { throw ToolError(code: .executionFailed, message: String(cString: strerror(errno))) }
            #endif
            return .success(invocation, text: "Sent signal \(signal) to pid \(pid)", json: ["pid": .integer(Int64(pid)), "signal": .integer(Int64(signal))])
        case "system_run":
            let request = try shellRequest(arguments, context, timeoutKey: "timeout_seconds")
            return try await process(invocation, context, request: request)
        case "run_background":
            guard let runner = context.processRunner as? any BackgroundProcessRunner else {
                throw ToolError(code: .unavailable, message: "The injected process runner does not support background processes")
            }
            let pid = try await runner.start(shellRequest(arguments, context, timeoutKey: nil))
            return .success(invocation, text: "Started pid \(pid)", json: ["pid": .integer(Int64(pid))])
        case "read_env_file": return try readEnvironment(invocation, arguments, context)
        case "write_env_file": return try writeEnvironment(invocation, arguments, context)
        case "add_goal": return try appendRecord(invocation, arguments, context, file: ".grump/goals.json", limit: 500)
        case "record_lesson": return try appendRecord(invocation, arguments, context, file: ".grump/lessons.json", limit: 500)
        case "remember": return try appendRecord(invocation, arguments, context, file: ".grump/memory-records.json", limit: 500)
        case "propose_skill":
            guard case .array(let lessons)? = arguments["lesson_ids"], lessons.count >= 3 else {
                throw ToolError(code: .invalidArguments, message: "propose_skill requires at least three lesson_ids")
            }
            return try appendRecord(invocation, arguments, context, file: ".grump/skill-proposals.json", limit: 50)
        case "reflect":
            return .success(invocation, text: "Reflection requested", json: ["status": "reflection_requested", "focus": arguments["focus"] ?? .null])
        case "update_plan":
            guard case .array(let steps)? = arguments["steps"], steps.count <= 25 else {
                throw ToolError(code: .invalidArguments, message: "steps must contain at most 25 entries")
            }
            let active = steps.filter { $0["status"]?.stringValue == "in_progress" }
            guard active.count <= 1 else { throw ToolError(code: .invalidArguments, message: "Only one step may be in_progress") }
            let file = try context.resolveWorkspacePath(".grump/plan.json")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try arguments["steps"]!.encoded(prettyPrinted: true).write(to: file, options: .atomic)
            return try encoded(invocation, ["status": "updated", "path": .string(file.path), "steps": arguments["steps"]!])
        case "ast_parse": return try await ast(invocation, arguments, context)
        case "view_code_outline": return try outline(invocation, arguments, context)
        case "find_references": return try references(invocation, arguments, context)
        case "code_complexity": return try complexity(invocation, arguments, context)
        case "dependency_graph": return try dependencyGraph(invocation, arguments, context)
        case "semantic_search": return try semanticSearch(invocation, arguments, context)
        case "summarize_text": return try summarize(invocation, arguments, context)
        case "yaml_parse": return try yaml(invocation, arguments, context)
        case "browser_open": return try await browserOpen(invocation, arguments, context)
        case "browser_evaluate", "browser_screenshot":
            throw ToolError(code: .unavailable, message: "Browser automation requires an injected external browser MCP provider (for example Playwright)")
        case "websocket_send": return try await websocket(invocation, arguments)
        case "port_scan": return try await portScan(invocation, arguments, context)
        case "ssl_check": return try await sslCheck(invocation, arguments, context)
        case "image_info", "image_resize", "image_convert": return try await image(invocation, arguments, context)
        case "generate_embeddings":
            throw ToolError(code: .unavailable, message: "Embedding generation requires an injected embedding provider")
        default: throw ToolError(code: .unknownTool, message: invocation.name)
        }
    }

    private static func shellRequest(_ arguments: [String: JSONValue], _ context: ExecutionContext, timeoutKey: String?) throws -> ProcessRequest {
        let cwd: URL
        if let value = try ToolArguments.string("cwd", in: arguments, required: false) { cwd = try context.resolveWorkspacePath(value, mustExist: true) }
        else { cwd = context.workspaceRoots.first! }
        let timeout = timeoutKey.flatMap { ToolArguments.int($0, in: arguments) }.map { Duration.seconds($0) }
        return .init(executable: "/bin/sh", arguments: ["-lc", try ToolArguments.string("command", in: arguments)!],
                     workingDirectory: cwd, environment: context.environment, timeout: timeout)
    }

    private static func process(_ invocation: ToolInvocation, _ context: ExecutionContext,
                                executable: String, arguments: [String]) async throws -> ToolResult {
        try await process(invocation, context, request: .init(executable: executable, arguments: arguments, workingDirectory: context.workspaceRoots.first))
    }

    private static func process(_ invocation: ToolInvocation, _ context: ExecutionContext, request: ProcessRequest) async throws -> ToolResult {
        let result = try await context.processRunner.run(request)
        let text = [result.standardOutput, result.standardError].filter { !$0.isEmpty }.joined(separator: "\n")
        guard result.exitCode == 0 else { throw ToolError(code: .executionFailed, message: text, details: ["exit_code": .integer(Int64(result.exitCode))]) }
        return .success(invocation, text: text.isEmpty ? "(no output)" : text,
                        json: ["exit_code": .integer(Int64(result.exitCode)), "stdout": .string(result.standardOutput), "stderr": .string(result.standardError)])
    }

    private static func readEnvironment(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments, required: false) ?? ".env", mustExist: true)
        let pairs = parseEnvironment(try String(contentsOf: url, encoding: .utf8))
        return .success(invocation, text: pairs.keys.sorted().map { "\($0)=\(pairs[$0]!)" }.joined(separator: "\n"),
                        json: .object(pairs.mapValues(JSONValue.string)))
    }

    private static func writeEnvironment(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!)
        guard case .object(let values)? = arguments["vars"] else { throw ToolError(code: .invalidArguments, message: "vars must be an object") }
        for key in values.keys where key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) == nil {
            throw ToolError(code: .invalidArguments, message: "Invalid environment variable name: \(key)")
        }
        let content = values.keys.sorted().map { key in "\(key)=\(quoteEnvironment(values[key]?.stringValue ?? ""))" }.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        return .success(invocation, text: "Wrote \(values.count) variable(s) to \(url.path)")
    }

    private static func parseEnvironment(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) { value.removeFirst(); value.removeLast() }
            result[key] = value
        }
        return result
    }

    private static func quoteEnvironment(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func appendRecord(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext,
                                     file: String, limit: Int) throws -> ToolResult {
        let url = try context.resolveWorkspacePath(file)
        var values: [JSONValue] = []
        if let data = try? Data(contentsOf: url), case .array(let existing) = try? JSONValue.decode(data: data) { values = existing }
        var record = arguments
        record["id"] = record["id"] ?? .string(UUID().uuidString)
        record["created_at"] = .string(ISO8601DateFormatter().string(from: Date()))
        values.append(.object(record)); if values.count > limit { values.removeFirst(values.count - limit) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONValue.array(values).encoded(prettyPrinted: true).write(to: url, options: .atomic)
        return try encoded(invocation, .object(record))
    }

    private static func ast(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) async throws -> ToolResult {
        let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!, mustExist: true)
        let language = (try ToolArguments.string("language", in: arguments, required: false) ?? url.pathExtension).lowercased()
        guard language == "swift", let swiftc = executable(["/usr/bin/swiftc", "/usr/local/bin/swiftc"]) else { return try outline(invocation, arguments, context) }
        return try await process(invocation, context, executable: swiftc, arguments: ["-dump-parse", url.path])
    }

    private static func outline(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!, mustExist: true)
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = #"(?m)^\s*(?:public\s+|private\s+|internal\s+|open\s+|static\s+|final\s+)*(class|struct|enum|protocol|actor|func|def|interface|type|extension)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let values: [JSONValue] = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let kindRange = Range(match.range(at: 1), in: text), let nameRange = Range(match.range(at: 2), in: text) else { return nil }
            let line = text[..<kindRange.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            return ["kind": .string(String(text[kindRange])), "name": .string(String(text[nameRange])), "line": .integer(Int64(line))]
        }
        return try encoded(invocation, .array(values))
    }

    private static func references(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments, required: false) ?? ".", mustExist: true)
        let symbol = try ToolArguments.string("symbol", in: arguments)!
        let pattern = try NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: symbol) + "\\b")
        let extensions = languageExtensions(try ToolArguments.string("language", in: arguments, required: false))
        var results: [JSONValue] = []
        for url in sourceFiles(root, extensions: extensions) where results.count < 500 {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                results.append(["path": .string(url.path), "line": .integer(Int64(index + 1)), "text": .string(line)])
            }
        }
        return try encoded(invocation, .array(results))
    }

    private static func complexity(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!, mustExist: true)
        let extensions = languageExtensions(try ToolArguments.string("language", in: arguments, required: false))
        let threshold = ToolArguments.int("threshold", in: arguments) ?? 10
        let branch = try NSRegularExpression(pattern: #"\b(if|else if|for|while|switch|case|catch|guard)\b|&&|\|\||\?"#)
        var results: [JSONValue] = []
        for url in sourceFiles(root, extensions: extensions) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let score = 1 + branch.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            if score >= threshold { results.append(["path": .string(url.path), "approximate_complexity": .integer(Int64(score))]) }
        }
        return try encoded(invocation, ["threshold": .integer(Int64(threshold)), "files": .array(results),
                                        "note": "Approximate branch-count metric; use a language-specific extension provider for function-level cyclomatic complexity."])
    }

    private static func dependencyGraph(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!, mustExist: true)
        let manifests = ["Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "requirements.txt"]
        var found: [JSONValue] = []
        for manifest in manifests {
            let url = root.appendingPathComponent(manifest)
            if let content = try? String(contentsOf: url, encoding: .utf8) { found.append(["manifest": .string(manifest), "content": .string(content)]) }
        }
        return try encoded(invocation, ["root": .string(root.path), "manifests": .array(found),
                                        "format": arguments["format"] ?? "json"])
    }

    private static func semanticSearch(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("directory", in: arguments)!, mustExist: true)
        let query = try ToolArguments.string("query", in: arguments)!.lowercased()
        let terms = Set(query.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let requested = (try ToolArguments.string("extensions", in: arguments, required: false) ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        var scores: [(Int, URL, String)] = []
        for url in sourceFiles(root, extensions: Set(requested)) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = text.lowercased(), score = terms.reduce(0) { $0 + lower.components(separatedBy: $1).count - 1 }
            if score > 0 { scores.append((score, url, String(text.prefix(800)))) }
        }
        let values: [JSONValue] = scores.sorted { $0.0 > $1.0 }.prefix(ToolArguments.int("top_k", in: arguments) ?? 10).map {
            ["score": .integer(Int64($0.0)), "path": .string($0.1.path), "preview": .string($0.2)]
        }
        return try encoded(invocation, .array(values))
    }

    private static func summarize(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let supplied = try ToolArguments.string("text", in: arguments)!
        let text: String
        if let url = try? context.resolveWorkspacePath(supplied, mustExist: true), let fileText = try? String(contentsOf: url, encoding: .utf8) { text = fileText }
        else { text = supplied }
        let limit = max(1, ToolArguments.int("max_length", in: arguments) ?? 200)
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var words = 0, selected: [String] = []
        for sentence in sentences {
            let count = sentence.split { $0.isWhitespace }.count
            if words + count > limit && !selected.isEmpty { break }
            selected.append(sentence); words += count
        }
        let style = try ToolArguments.string("style", in: arguments, required: false) ?? "brief"
        let summary = style == "bullet_points" ? selected.map { "- \($0)" }.joined(separator: "\n") : selected.joined(separator: ". ") + (selected.isEmpty ? "" : ".")
        return .success(invocation, text: summary, json: ["summary": .string(summary), "words": .integer(Int64(words)), "method": "extractive"])
    }

    private static func yaml(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let text: String
        if let supplied = try ToolArguments.string("yaml", in: arguments, required: false) { text = supplied }
        else if let path = try ToolArguments.string("path", in: arguments, required: false) { text = try String(contentsOf: context.resolveWorkspacePath(path, mustExist: true), encoding: .utf8) }
        else { throw ToolError(code: .invalidArguments, message: "Provide yaml or path") }
        var object: [String: JSONValue] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let raw = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            object[key] = scalar(raw)
        }
        return try encoded(invocation, ["value": .object(object), "note": "Portable flat-YAML parser; nested YAML requires an extension provider"])
    }

    private static func browserOpen(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) async throws -> ToolResult {
        let url = try ToolArguments.string("url", in: arguments)!
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else { throw ToolError(code: .invalidArguments, message: "A valid http(s) URL is required") }
        #if os(macOS)
        return try await process(invocation, context, executable: "/usr/bin/open", arguments: [url])
        #else
        return try await process(invocation, context, executable: "/usr/bin/xdg-open", arguments: [url])
        #endif
    }

    private static func websocket(_ invocation: ToolInvocation, _ arguments: [String: JSONValue]) async throws -> ToolResult {
        guard let url = URL(string: try ToolArguments.string("url", in: arguments)!), ["ws", "wss"].contains(url.scheme?.lowercased() ?? "") else {
            throw ToolError(code: .invalidArguments, message: "A valid ws(s) URL is required")
        }
        let task = URLSession.shared.webSocketTask(with: url); task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }
        try await task.send(.string(try ToolArguments.string("message", in: arguments)!))
        let reply = try await task.receive()
        let text: String
        switch reply { case .string(let value): text = value; case .data(let data): text = data.base64EncodedString(); @unknown default: text = "" }
        return .success(invocation, text: text)
    }

    private static func portScan(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) async throws -> ToolResult {
        let host = try ToolArguments.string("host", in: arguments)!, port = ToolArguments.int("port", in: arguments)!, timeout = ToolArguments.int("timeout", in: arguments) ?? 5
        guard (1...65_535).contains(port) else { throw ToolError(code: .invalidArguments, message: "port must be 1...65535") }
        guard let nc = executable(["/usr/bin/nc", "/bin/nc"]) else { throw ToolError(code: .unavailable, message: "netcat (nc) is not installed") }
        let result = try await context.processRunner.run(.init(executable: nc, arguments: ["-z", "-w", String(timeout), host, String(port)]))
        let open = result.exitCode == 0
        return .success(invocation, text: open ? "open" : "closed", json: ["host": .string(host), "port": .integer(Int64(port)), "open": .bool(open)])
    }

    private static func sslCheck(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) async throws -> ToolResult {
        let host = try ToolArguments.string("hostname", in: arguments)!, port = ToolArguments.int("port", in: arguments) ?? 443
        guard let openssl = executable(["/usr/bin/openssl", "/usr/local/bin/openssl"]) else { throw ToolError(code: .unavailable, message: "openssl is not installed") }
        let result = try await context.processRunner.run(.init(executable: openssl, arguments: ["s_client", "-connect", "\(host):\(port)", "-servername", host, "-brief"], standardInput: Data()))
        let text = [result.standardOutput, result.standardError].joined(separator: "\n")
        guard result.exitCode == 0 else { throw ToolError(code: .executionFailed, message: text) }
        return .success(invocation, text: text)
    }

    private static func image(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) async throws -> ToolResult {
        let source = try context.resolveWorkspacePath(try ToolArguments.string("path", in: arguments)!, mustExist: true)
        #if os(macOS)
        let sips = "/usr/bin/sips"
        if invocation.name == "image_info" { return try await process(invocation, context, executable: sips, arguments: ["-g", "pixelWidth", "-g", "pixelHeight", "-g", "format", source.path]) }
        let output = try context.resolveWorkspacePath(try ToolArguments.string("output_path", in: arguments, required: false) ?? source.path)
        var args: [String] = []
        if invocation.name == "image_convert" {
            let format = output.pathExtension.lowercased(); guard !format.isEmpty else { throw ToolError(code: .invalidArguments, message: "output_path needs an extension") }
            args = ["-s", "format", format, source.path, "--out", output.path]
        } else if let width = ToolArguments.int("width", in: arguments), let height = ToolArguments.int("height", in: arguments) { args = ["-z", String(height), String(width), source.path, "--out", output.path] }
        else if let width = ToolArguments.int("max_width", in: arguments) { args = ["-Z", String(width), source.path, "--out", output.path] }
        else if let height = ToolArguments.int("max_height", in: arguments) { args = ["-Z", String(height), source.path, "--out", output.path] }
        else { throw ToolError(code: .invalidArguments, message: "Provide resize dimensions") }
        return try await process(invocation, context, executable: sips, arguments: args)
        #else
        guard let identify = executable(["/usr/bin/identify", "/usr/local/bin/identify"]), invocation.name == "image_info" else {
            throw ToolError(code: .unavailable, message: "ImageMagick is required for this image operation on Linux")
        }
        return try await process(invocation, context, executable: identify, arguments: [source.path])
        #endif
    }

    private static func sourceFiles(_ root: URL, extensions: Set<String>) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue { return [root] }
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL, files.count < 10_000 {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, (values?.fileSize ?? 0) < 2_000_000,
               extensions.isEmpty || extensions.contains(url.pathExtension.lowercased()) { files.append(url) }
        }
        return files
    }

    private static func languageExtensions(_ language: String?) -> Set<String> {
        guard let language = language?.lowercased() else { return ["swift", "js", "jsx", "ts", "tsx", "py", "go", "rs", "java", "kt", "rb", "c", "h", "cpp", "hpp"] }
        return ["typescript": ["ts", "tsx"], "javascript": ["js", "jsx"], "python": ["py"], "swift": ["swift"], "go": ["go"], "rust": ["rs"]][language].map(Set.init) ?? [language]
    }

    private static func scalar(_ raw: String) -> JSONValue {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value == "null" || value == "~" { return .null }
        if ["true", "yes"].contains(value.lowercased()) { return true }
        if ["false", "no"].contains(value.lowercased()) { return false }
        if let integer = Int64(value) { return .integer(integer) }
        if let number = Double(value) { return .number(number) }
        return .string(value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
    }

    private static func executable(_ choices: [String]) -> String? { choices.first { FileManager.default.isExecutableFile(atPath: $0) } }
    private static func encoded(_ invocation: ToolInvocation, _ value: JSONValue) throws -> ToolResult {
        .success(invocation, text: String(decoding: try value.encoded(prettyPrinted: true), as: UTF8.self), json: value)
    }
}
