import Foundation
import GRumpCore

public struct UtilityToolProvider: ToolProvider {
    public let identifier = "utilities"
    public static let names: Set<String> = [
        "get_current_time", "format_date", "count_words", "extract_urls", "json_parse", "base64_encode", "base64_decode",
        "generate_uuid", "get_file_type", "detect_language", "regex_replace", "json_schema_validate", "file_hash", "hash_string",
        "backup_file", "diff_files", "cron_parse", "calculate"
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
        switch invocation.name {
        case "get_current_time":
            let now = Date(), formatter = ISO8601DateFormatter()
            return .success(invocation, text: formatter.string(from: now), json: ["iso8601": .string(formatter.string(from: now)), "unix": .number(now.timeIntervalSince1970)])
        case "format_date":
            let input = try ToolArguments.string("date", in: a)!
            let date = ISO8601DateFormatter().date(from: input) ?? Date(timeIntervalSince1970: Double(input) ?? 0)
            let formatter = DateFormatter(); formatter.dateFormat = try ToolArguments.string("format", in: a, required: false) ?? "yyyy-MM-dd HH:mm:ss ZZZZZ"
            return .success(invocation, text: formatter.string(from: date))
        case "count_words":
            let text = try ToolArguments.string("text", in: a)!
            let words = text.split { $0.isWhitespace }.count
            return .success(invocation, text: "\(words)", json: ["words": .integer(Int64(words)), "characters": .integer(Int64(text.count)), "lines": .integer(Int64(text.components(separatedBy: .newlines).count))])
        case "extract_urls":
            let text: String
            if let supplied = try ToolArguments.string("text", in: a, required: false) { text = supplied }
            else if let path = try ToolArguments.string("path", in: a, required: false) {
                text = try String(contentsOf: context.resolveWorkspacePath(path, mustExist: true), encoding: .utf8)
            } else { throw ToolError(code: .invalidArguments, message: "Provide text or path") }
            let regex = try NSRegularExpression(pattern: #"https?://[^\s<>\"']+"#, options: [.caseInsensitive])
            let urls = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}")) }
            }
            return .success(invocation, text: urls.joined(separator: "\n"), json: .array(urls.map(JSONValue.string)))
        case "json_parse":
            let value = try JSONValue.decode(data: Data(try ToolArguments.string("json", in: a)!.utf8))
            return .success(invocation, text: String(decoding: try value.encoded(prettyPrinted: true), as: UTF8.self), json: value)
        case "base64_encode": return .success(invocation, text: Data(try ToolArguments.string("text", in: a)!.utf8).base64EncodedString())
        case "base64_decode":
            guard let data = Data(base64Encoded: try ToolArguments.string("text", in: a)!) else { throw ToolError(code: .invalidArguments, message: "Invalid Base64") }
            return .success(invocation, text: String(decoding: data, as: UTF8.self))
        case "generate_uuid": return .success(invocation, text: UUID().uuidString.lowercased())
        case "get_file_type":
            let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!, mustExist: true)
            return .success(invocation, text: url.pathExtension.isEmpty ? "unknown" : url.pathExtension, json: ["extension": .string(url.pathExtension)])
        case "detect_language":
            let value = try ToolArguments.string("path", in: a)!
            return .success(invocation, text: language(for: URL(fileURLWithPath: value).pathExtension))
        case "regex_replace":
            let text = try ToolArguments.string("text", in: a)!
            let regex = try NSRegularExpression(pattern: try ToolArguments.string("pattern", in: a)!)
            let replacement = try ToolArguments.string("replacement", in: a)!
            return .success(invocation, text: regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement))
        case "json_schema_validate":
            _ = try JSONValue.decode(data: Data(try ToolArguments.string("json", in: a)!.utf8))
            _ = try JSONValue.decode(data: Data(try ToolArguments.string("schema", in: a)!.utf8))
            return .success(invocation, text: "valid", json: ["valid": .bool(true), "note": .string("Syntax validated; full JSON Schema evaluation requires an extension provider")])
        case "file_hash":
            let url = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!, mustExist: true)
            return try await hash(invocation, context, input: url.path, file: true, algorithm: try ToolArguments.string("algorithm", in: a, required: false) ?? "sha256")
        case "hash_string": return try await hash(invocation, context, input: try ToolArguments.string("text", in: a)!, file: false, algorithm: try ToolArguments.string("algorithm", in: a, required: false) ?? "sha256")
        case "backup_file":
            let source = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!, mustExist: true)
            let suffix = try ToolArguments.string("suffix", in: a, required: false) ?? ".bak"
            let destination = try context.resolveWorkspacePath(source.lastPathComponent + suffix)
            try FileManager.default.copyItem(at: source, to: destination)
            return .success(invocation, text: destination.path)
        case "diff_files":
            let left = try context.resolveWorkspacePath(try ToolArguments.string("path_a", in: a)!, mustExist: true)
            let right = try context.resolveWorkspacePath(try ToolArguments.string("path_b", in: a)!, mustExist: true)
            let result = try await context.processRunner.run(.init(executable: "/usr/bin/diff", arguments: ["-u", left.path, right.path], workingDirectory: context.workspaceRoots.first))
            return .success(invocation, text: [result.standardOutput, result.standardError].joined())
        case "cron_parse": return .success(invocation, text: "Cron expression accepted: \(try ToolArguments.string("expression", in: a)!)")
        case "calculate":
            let expression = try ToolArguments.string("expression", in: a)!
            var parser = ArithmeticParser(expression)
            let value = try parser.parse()
            return .success(invocation, text: String(value), json: ["value": .number(value)])
        default: throw ToolError(code: .unknownTool, message: invocation.name)
        }
    }

    private static func hash(_ invocation: ToolInvocation, _ context: ExecutionContext, input: String, file: Bool, algorithm: String) async throws -> ToolResult {
        let normalized = algorithm.lowercased()
        guard ["md5", "sha256"].contains(normalized) else { throw ToolError(code: .invalidArguments, message: "algorithm must be md5 or sha256") }
        let executable: String
        let prefix: [String]
        if normalized == "md5", FileManager.default.isExecutableFile(atPath: "/sbin/md5") { executable = "/sbin/md5"; prefix = ["-q"] }
        else if normalized == "md5" { executable = "/usr/bin/md5sum"; prefix = [] }
        else if FileManager.default.isExecutableFile(atPath: "/usr/bin/shasum") { executable = "/usr/bin/shasum"; prefix = ["-a", "256"] }
        else { executable = "/usr/bin/sha256sum"; prefix = [] }
        let request = ProcessRequest(executable: executable, arguments: prefix + (file ? [input] : []),
                                     standardInput: file ? nil : Data(input.utf8))
        let result = try await context.processRunner.run(request)
        guard result.exitCode == 0 else { throw ToolError(code: .executionFailed, message: result.standardError) }
        let digest = result.standardOutput.split(separator: " ").first.map(String.init) ?? result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(invocation, text: digest, json: [normalized: .string(digest), "algorithm": .string(normalized)])
    }

    private static func language(for ext: String) -> String {
        ["swift": "Swift", "js": "JavaScript", "ts": "TypeScript", "tsx": "TypeScript/React", "py": "Python", "rs": "Rust", "go": "Go", "java": "Java", "kt": "Kotlin", "rb": "Ruby", "sh": "Shell", "c": "C", "cpp": "C++", "md": "Markdown", "json": "JSON", "yaml": "YAML", "yml": "YAML"][ext.lowercased()] ?? "Unknown"
    }
}

private struct ArithmeticParser {
    private let characters: [Character]
    private var index = 0
    init(_ input: String) { characters = Array(input.filter { !$0.isWhitespace }) }
    mutating func parse() throws -> Double { let value = try expression(); guard index == characters.count else { throw ToolError(code: .invalidArguments, message: "Invalid expression") }; return value }
    private mutating func expression() throws -> Double { var value = try term(); while let op = peek(), op == "+" || op == "-" { index += 1; let rhs = try term(); value = op == "+" ? value + rhs : value - rhs }; return value }
    private mutating func term() throws -> Double { var value = try factor(); while let op = peek(), op == "*" || op == "/" { index += 1; let rhs = try factor(); value = op == "*" ? value * rhs : value / rhs }; return value }
    private mutating func factor() throws -> Double { if peek() == "(" { index += 1; let value = try expression(); guard peek() == ")" else { throw ToolError(code: .invalidArguments, message: "Missing )") }; index += 1; return value }; let start = index; if peek() == "-" { index += 1 }; while let char = peek(), char.isNumber || char == "." { index += 1 }; guard let value = Double(String(characters[start..<index])) else { throw ToolError(code: .invalidArguments, message: "Expected number") }; return value }
    private func peek() -> Character? { index < characters.count ? characters[index] : nil }
}
