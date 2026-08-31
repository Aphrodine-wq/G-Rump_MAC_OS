import Foundation
import GRumpCore

public struct WorkspaceToolProvider: ToolProvider {
    public let identifier = "workspace"
    public static let names: Set<String> = [
        "read_file", "batch_read_files", "write_file", "edit_file", "create_file", "delete_file", "move_file",
        "copy_file", "file_info", "path_exists", "count_lines", "list_directory", "tree_view", "search_files",
        "grep_search", "find_and_replace", "append_file", "create_directory", "compress_files", "extract_archive"
    ]

    public init() {}

    public var tools: [RegisteredTool] {
        Self.names.sorted().compactMap { name in
            guard let definition = BuiltinToolCatalog.definition(named: name) else { return nil }
            return RegisteredTool(definition: definition) { invocation, context in
                try await Self.execute(invocation, context: context)
            }
        }
    }

    private static func execute(_ invocation: ToolInvocation, context: ExecutionContext) async throws -> ToolResult {
        let arguments = try ToolArguments.object(invocation)
        switch invocation.name {
        case "read_file": return try readFile(invocation, arguments, context)
        case "batch_read_files": return try batchRead(invocation, arguments, context)
        case "write_file": return try writeFile(invocation, arguments, context, mustBeNew: false)
        case "create_file": return try writeFile(invocation, arguments, context, mustBeNew: true)
        case "edit_file": return try editFile(invocation, arguments, context)
        case "append_file": return try appendFile(invocation, arguments, context)
        case "delete_file": return try deleteFile(invocation, arguments, context)
        case "move_file": return try moveOrCopy(invocation, arguments, context, copy: false)
        case "copy_file": return try moveOrCopy(invocation, arguments, context, copy: true)
        case "file_info": return try fileInfo(invocation, arguments, context)
        case "path_exists": return try pathExists(invocation, arguments, context)
        case "count_lines": return try countLines(invocation, arguments, context)
        case "list_directory": return try listDirectory(invocation, arguments, context)
        case "tree_view": return try treeView(invocation, arguments, context)
        case "search_files": return try searchFiles(invocation, arguments, context)
        case "grep_search": return try grepSearch(invocation, arguments, context)
        case "find_and_replace": return try findAndReplace(invocation, arguments, context)
        case "create_directory": return try createDirectory(invocation, arguments, context)
        case "compress_files": return try await archive(invocation, arguments, context, extract: false)
        case "extract_archive": return try await archive(invocation, arguments, context, extract: true)
        default: throw ToolError(code: .unknownTool, message: invocation.name)
        }
    }

    private static func path(_ arguments: [String: JSONValue], _ context: ExecutionContext, key: String = "path", exists: Bool = false) throws -> URL {
        try context.resolveWorkspacePath(try ToolArguments.string(key, in: arguments)!, mustExist: exists)
    }

    private static func readFile(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let start = max(1, ToolArguments.int("start_line", in: arguments) ?? 1)
        let end = min(lines.count, ToolArguments.int("end_line", in: arguments) ?? lines.count)
        guard start <= end else { throw ToolError(code: .invalidArguments, message: "start_line must not exceed end_line") }
        let numbered = lines[(start - 1)..<end].enumerated().map { "\(start + $0.offset)\t\($0.element)" }.joined(separator: "\n")
        return .success(invocation, text: numbered, json: ["path": .string(url.path), "start_line": .integer(Int64(start)), "end_line": .integer(Int64(end))])
    }

    private static func batchRead(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let paths = Array(try ToolArguments.strings("paths", in: arguments).prefix(10))
        var results: [JSONValue] = []
        for item in paths {
            do {
                let url = try context.resolveWorkspacePath(item, mustExist: true)
                results.append(["path": .string(item), "content": .string(try String(contentsOf: url, encoding: .utf8))])
            } catch { results.append(["path": .string(item), "error": .string(String(describing: error))]) }
        }
        return .success(invocation, text: results.compactMap { value in
            guard let object = value.objectValue else { return nil }
            return "--- \(object["path"]?.stringValue ?? "") ---\n\(object["content"]?.stringValue ?? object["error"]?.stringValue ?? "")"
        }.joined(separator: "\n"), json: .array(results))
    }

    private static func writeFile(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext, mustBeNew: Bool) throws -> ToolResult {
        let url = try path(arguments, context)
        if mustBeNew && FileManager.default.fileExists(atPath: url.path) {
            throw ToolError(code: .executionFailed, message: "Path already exists: \(url.path)")
        }
        let content = try ToolArguments.string("content", in: arguments)!
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url, options: .atomic)
        return .success(invocation, text: "Wrote \(content.utf8.count) bytes to \(url.path)", json: ["path": .string(url.path), "bytes": .integer(Int64(content.utf8.count))])
    }

    private static func editFile(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        let old = try ToolArguments.string("old_content", in: arguments)!
        let new = try ToolArguments.string("new_content", in: arguments)!
        let original = try String(contentsOf: url, encoding: .utf8)
        let count = original.components(separatedBy: old).count - 1
        guard count > 0 else { throw ToolError(code: .executionFailed, message: "old_content was not found") }
        guard count == 1 || ToolArguments.bool("replace_all", in: arguments) else {
            throw ToolError(code: .invalidArguments, message: "old_content matches \(count) locations; use more context or replace_all")
        }
        let updated = ToolArguments.bool("replace_all", in: arguments) ? original.replacingOccurrences(of: old, with: new) : original.replacingOccurrences(of: old, with: new, options: [], range: original.range(of: old))
        try Data(updated.utf8).write(to: url, options: .atomic)
        return .success(invocation, text: "Edited \(url.path)", json: ["replacements": .integer(Int64(ToolArguments.bool("replace_all", in: arguments) ? count : 1))])
    }

    private static func appendFile(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context)
        let content = try ToolArguments.string("content", in: arguments)!
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { try Data().write(to: url) }
        let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
        try handle.seekToEnd(); try handle.write(contentsOf: Data(content.utf8))
        return .success(invocation, text: "Appended \(content.utf8.count) bytes to \(url.path)")
    }

    private static func deleteFile(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            if !contents.isEmpty { throw ToolError(code: .policyDenied, message: "delete_file only removes empty directories") }
        }
        try FileManager.default.removeItem(at: url)
        return .success(invocation, text: "Deleted \(url.path)")
    }

    private static func moveOrCopy(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext, copy: Bool) throws -> ToolResult {
        let source = try context.resolveWorkspacePath(try ToolArguments.string("source", in: arguments)!, mustExist: true)
        let destination = try context.resolveWorkspacePath(try ToolArguments.string("destination", in: arguments)!)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard copy && ToolArguments.bool("overwrite", in: arguments) else { throw ToolError(code: .executionFailed, message: "Destination exists") }
            try FileManager.default.removeItem(at: destination)
        }
        if copy { try FileManager.default.copyItem(at: source, to: destination) } else { try FileManager.default.moveItem(at: source, to: destination) }
        return .success(invocation, text: "\(copy ? "Copied" : "Moved") \(source.path) to \(destination.path)")
    }

    private static func fileInfo(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let value: JSONValue = ["path": .string(url.path), "is_directory": .bool(isDirectory), "size": .integer(size), "modified_unix": .number(modified), "extension": .string(url.pathExtension)]
        return .success(invocation, text: try String(decoding: value.encoded(prettyPrinted: true), as: UTF8.self), json: value)
    }

    private static func pathExists(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let value: JSONValue = ["exists": .bool(exists), "is_directory": .bool(exists && isDirectory.boolValue)]
        return .success(invocation, text: exists ? (isDirectory.boolValue ? "directory" : "file") : "missing", json: value)
    }

    private static func countLines(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        let data = try Data(contentsOf: url)
        let count = data.reduce(0) { $1 == 10 ? $0 + 1 : $0 } + (data.isEmpty || data.last == 10 ? 0 : 1)
        return .success(invocation, text: "\(count)", json: ["lines": .integer(Int64(count))])
    }

    private static func listDirectory(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context, exists: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey]
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let values: [JSONValue] = try entries.map { entry in
            let resource = try entry.resourceValues(forKeys: Set(keys))
            return ["name": .string(entry.lastPathComponent), "is_directory": .bool(resource.isDirectory ?? false), "is_symlink": .bool(resource.isSymbolicLink ?? false), "size": .integer(Int64(resource.fileSize ?? 0))]
        }
        return .success(invocation, text: values.compactMap { $0.objectValue?["name"]?.stringValue }.joined(separator: "\n"), json: .array(values))
    }

    private static func treeView(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try path(arguments, context, exists: true)
        let maxDepth = min(10, max(1, ToolArguments.int("depth", in: arguments) ?? ToolArguments.int("max_depth", in: arguments) ?? 3))
        var lines = [root.lastPathComponent + "/"]
        func walk(_ directory: URL, depth: Int) throws {
            guard depth <= maxDepth else { return }
            for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                lines.append(String(repeating: "  ", count: depth) + child.lastPathComponent + ((values.isDirectory ?? false) ? "/" : ""))
                if values.isDirectory == true && values.isSymbolicLink != true { try walk(child, depth: depth + 1) }
            }
        }
        try walk(root, depth: 1)
        return .success(invocation, text: lines.joined(separator: "\n"))
    }

    private static func searchFiles(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("directory", in: arguments)!, mustExist: true)
        let pattern = try ToolArguments.string("pattern", in: arguments)!
        let limit = min(1000, ToolArguments.int("max_results", in: arguments) ?? 200)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var matches: [String] = []
        while let url = enumerator?.nextObject() as? URL, matches.count < limit {
            if glob(pattern, matches: url.lastPathComponent) { matches.append(url.path) }
        }
        return .success(invocation, text: matches.joined(separator: "\n"), json: .array(matches.map(JSONValue.string)))
    }

    private static func grepSearch(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try path(arguments, context, exists: true)
        let query = try ToolArguments.string("query", in: arguments)!
        let caseSensitive = ToolArguments.bool("case_sensitive", in: arguments)
        let needle = caseSensitive ? query : query.lowercased()
        let regex = ToolArguments.bool("is_regex", in: arguments) ? try NSRegularExpression(pattern: query, options: caseSensitive ? [] : [.caseInsensitive]) : nil
        let include = try ToolArguments.string("include", in: arguments, required: false)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var output: [String] = []
        while let url = enumerator?.nextObject() as? URL, output.count < 500 {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) < 5_000_000,
                  include.map({ glob($0, matches: url.lastPathComponent) }) ?? true,
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let haystack = caseSensitive ? line : line.lowercased()
                let match = regex.map { $0.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil } ?? haystack.contains(needle)
                if match { output.append("\(url.path):\(index + 1):\(line)") }
                if output.count >= 500 { break }
            }
        }
        return .success(invocation, text: output.joined(separator: "\n"), json: .array(output.map(JSONValue.string)))
    }

    private static func findAndReplace(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let root = try context.resolveWorkspacePath(try ToolArguments.string("directory", in: arguments)!, mustExist: true)
        let find = try ToolArguments.string("find", in: arguments)!
        let replacement = try ToolArguments.string("replace", in: arguments)!
        let include = try ToolArguments.string("include", in: arguments, required: false)
        let dryRun = ToolArguments.bool("dry_run", in: arguments)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])
        var changed: [JSONValue] = []; var total = 0
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) < 5_000_000,
                  include.map({ glob($0, matches: url.lastPathComponent) }) ?? true,
                  let original = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let count = original.components(separatedBy: find).count - 1
            guard count > 0 else { continue }
            total += count; changed.append(["path": .string(url.path), "replacements": .integer(Int64(count))])
            if !dryRun { try Data(original.replacingOccurrences(of: find, with: replacement).utf8).write(to: url, options: .atomic) }
        }
        return .success(invocation, text: "\(dryRun ? "Would replace" : "Replaced") \(total) occurrence(s) in \(changed.count) file(s)", json: ["dry_run": .bool(dryRun), "replacements": .integer(Int64(total)), "files": .array(changed)])
    }

    private static func createDirectory(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext) throws -> ToolResult {
        let url = try path(arguments, context)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return .success(invocation, text: "Created \(url.path)")
    }

    private static func archive(_ invocation: ToolInvocation, _ arguments: [String: JSONValue], _ context: ExecutionContext, extract: Bool) async throws -> ToolResult {
        if extract {
            let source = try path(arguments, context, exists: true)
            let destinationValue = try ToolArguments.string("destination", in: arguments)!
            let destination = try context.resolveWorkspacePath(destinationValue)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let request: ProcessRequest
            if source.pathExtension.lowercased() == "zip" {
                request = ProcessRequest(executable: "/usr/bin/unzip", arguments: ["-q", source.path, "-d", destination.path], workingDirectory: context.workspaceRoots.first)
            } else {
                request = ProcessRequest(executable: "/usr/bin/tar", arguments: ["-xf", source.path, "-C", destination.path], workingDirectory: context.workspaceRoots.first)
            }
            let result = try await context.processRunner.run(request)
            guard result.exitCode == 0 else { throw ToolError(code: .executionFailed, message: result.standardError) }
            return .success(invocation, text: "Extracted to \(destination.path)")
        }
        let sources = try ToolArguments.strings("paths", in: arguments)
        let destinationText = try ToolArguments.string("output", in: arguments)!
        let destination = try context.resolveWorkspacePath(destinationText)
        let resolvedSources = try sources.map { try context.resolveWorkspacePath($0, mustExist: true).path }
        let request = ProcessRequest(executable: "/usr/bin/zip", arguments: ["-rq", destination.path] + resolvedSources, workingDirectory: context.workspaceRoots.first)
        let result = try await context.processRunner.run(request)
        guard result.exitCode == 0 else { throw ToolError(code: .executionFailed, message: result.standardError) }
        return .success(invocation, text: "Created \(destination.path)")
    }

    private static func glob(_ pattern: String, matches value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        return value.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil
    }
}
