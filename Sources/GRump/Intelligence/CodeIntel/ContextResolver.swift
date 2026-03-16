import Foundation

/// Multi-file context awareness service.
/// Scans the working directory for related files, detects project structure,
/// and provides relevant file context to the AI without manual user selection.
@MainActor
final class ContextResolver: ObservableObject {

    @Published private(set) var resolvedFiles: [ResolvedFile] = []
    @Published private(set) var projectType: ProjectType = .unknown
    @Published private(set) var isScanning: Bool = false

    struct ResolvedFile: Identifiable, Equatable {
        let id = UUID()
        let path: String
        let relativePath: String
        let language: String
        let relevanceScore: Double
        let reason: String
    }

    enum ProjectType: String {
        case swift
        case node
        case python
        case rust
        case go
        case mixed
        case unknown
    }

    // MARK: - Resolve

    /// Resolve relevant files for the current conversation context.
    /// Analyzes the user's message and recent tool calls to find related files.
    func resolve(
        userMessage: String,
        recentMessages: [Message],
        workingDirectory: String
    ) async {
        guard !workingDirectory.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }

        let dir = workingDirectory

        // Detect project type
        projectType = await detectProjectType(dir)

        // Extract file references from messages
        let mentionedFiles = extractFileReferences(from: userMessage, recentMessages: recentMessages)

        // Find related files
        var candidates: [ResolvedFile] = []

        // 1. Directly mentioned files (highest relevance)
        for file in mentionedFiles {
            let fullPath = file.hasPrefix("/") ? file : "\(dir)/\(file)"
            if FileManager.default.fileExists(atPath: fullPath) {
                let lang = languageForExtension(URL(fileURLWithPath: fullPath).pathExtension)
                candidates.append(ResolvedFile(
                    path: fullPath,
                    relativePath: file.hasPrefix("/") ? makeRelative(fullPath, to: dir) : file,
                    language: lang,
                    relevanceScore: 1.0,
                    reason: "Mentioned in conversation"
                ))
            }
        }

        // 2. Recently modified files from tool calls
        let recentToolFiles = extractToolCallFiles(from: recentMessages)
        for file in recentToolFiles where !candidates.contains(where: { $0.path == file }) {
            let fullPath = file.hasPrefix("/") ? file : "\(dir)/\(file)"
            if FileManager.default.fileExists(atPath: fullPath) {
                let lang = languageForExtension(URL(fileURLWithPath: fullPath).pathExtension)
                candidates.append(ResolvedFile(
                    path: fullPath,
                    relativePath: makeRelative(fullPath, to: dir),
                    language: lang,
                    relevanceScore: 0.8,
                    reason: "Recently modified by tools"
                ))
            }
        }

        // 3. Project config files (Package.swift, package.json, etc.)
        let configFiles = projectConfigFiles(for: projectType)
        for config in configFiles {
            let fullPath = "\(dir)/\(config)"
            if FileManager.default.fileExists(atPath: fullPath),
               !candidates.contains(where: { $0.path == fullPath }) {
                candidates.append(ResolvedFile(
                    path: fullPath,
                    relativePath: config,
                    language: languageForExtension(URL(fileURLWithPath: fullPath).pathExtension),
                    relevanceScore: 0.5,
                    reason: "Project configuration"
                ))
            }
        }

        // Sort by relevance and cap
        resolvedFiles = candidates
            .sorted { $0.relevanceScore > $1.relevanceScore }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - File Reference Extraction

    private func extractFileReferences(from message: String, recentMessages: [Message]) -> [String] {
        var files: [String] = []
        let allText = ([message] + recentMessages.suffix(5).map(\.content)).joined(separator: "\n")

        // Pattern: backticked paths like `path/to/file.ext`
        let backtickPattern = #"`([^`\s]+\.[a-zA-Z]{1,10})`"#
        if let regex = try? NSRegularExpression(pattern: backtickPattern) {
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            for match in matches {
                if let range = Range(match.range(at: 1), in: allText) {
                    let path = String(allText[range])
                    if path.contains("/") || path.contains(".") {
                        files.append(path)
                    }
                }
            }
        }

        // Pattern: quoted paths "path/to/file.ext"
        let quotedPattern = #""([^"\s]+\.[a-zA-Z]{1,10})""#
        if let regex = try? NSRegularExpression(pattern: quotedPattern) {
            let matches = regex.matches(in: allText, range: NSRange(allText.startIndex..., in: allText))
            for match in matches {
                if let range = Range(match.range(at: 1), in: allText) {
                    let path = String(allText[range])
                    if path.contains("/") {
                        files.append(path)
                    }
                }
            }
        }

        return Array(Set(files))
    }

    private func extractToolCallFiles(from messages: [Message]) -> [String] {
        var files: [String] = []
        for msg in messages.suffix(10) {
            guard let toolCalls = msg.toolCalls else { continue }
            for call in toolCalls {
                if let data = call.arguments.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let path = args["path"] as? String { files.append(path) }
                    if let paths = args["paths"] as? [String] { files.append(contentsOf: paths) }
                    if let file = args["file_path"] as? String { files.append(file) }
                }
            }
        }
        return Array(Set(files))
    }

    // MARK: - Project Detection

    private func detectProjectType(_ dir: String) async -> ProjectType {
        let fm = FileManager.default
        if fm.fileExists(atPath: "\(dir)/Package.swift") { return .swift }
        if fm.fileExists(atPath: "\(dir)/package.json") { return .node }
        if fm.fileExists(atPath: "\(dir)/requirements.txt") || fm.fileExists(atPath: "\(dir)/pyproject.toml") { return .python }
        if fm.fileExists(atPath: "\(dir)/Cargo.toml") { return .rust }
        if fm.fileExists(atPath: "\(dir)/go.mod") { return .go }
        return .unknown
    }

    private func projectConfigFiles(for type: ProjectType) -> [String] {
        switch type {
        case .swift: return ["Package.swift", "CLAUDE.md", ".grump/config.json"]
        case .node: return ["package.json", "tsconfig.json", ".env"]
        case .python: return ["requirements.txt", "pyproject.toml", "setup.py"]
        case .rust: return ["Cargo.toml"]
        case .go: return ["go.mod", "go.sum"]
        case .mixed, .unknown: return []
        }
    }

    // MARK: - Helpers

    private func makeRelative(_ path: String, to base: String) -> String {
        if path.hasPrefix(base) {
            let relative = String(path.dropFirst(base.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return path
    }

    private func languageForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "swift": return "swift"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "py": return "python"
        case "rs": return "rust"
        case "go": return "go"
        case "rb": return "ruby"
        case "java": return "java"
        case "kt": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "toml": return "toml"
        case "md": return "markdown"
        case "html": return "html"
        case "css": return "css"
        case "sh", "bash", "zsh": return "shell"
        case "sql": return "sql"
        default: return ext
        }
    }
}
