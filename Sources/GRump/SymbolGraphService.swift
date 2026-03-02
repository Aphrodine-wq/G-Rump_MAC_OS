import Foundation

// MARK: - Symbol Graph Service
//
// Extracts and parses Swift symbol graphs from the user's project.
// Symbol graphs provide compiler-level understanding of every type,
// method, property, and protocol in the codebase — far deeper than
// what LSP diagnostics or grep can provide.
//
// Usage:
//   1. Run `swift symbolgraph-extract` on the project's module
//   2. Parse the resulting JSON into structured SymbolNode/SymbolRelation
//   3. Feed into the agent's system prompt for deep project awareness
//
// Also integrates with `swift package generate-documentation` for DocC.

// MARK: - Symbol Graph Models

struct SymbolGraph: Codable {
    let metadata: SymbolGraphMetadata?
    let module: SymbolGraphModule
    let symbols: [SymbolNode]
    let relationships: [SymbolRelation]
}

struct SymbolGraphMetadata: Codable {
    let formatVersion: FormatVersion?
    let generator: String?

    struct FormatVersion: Codable {
        let major: Int?
        let minor: Int?
        let patch: Int?
    }
}

struct SymbolGraphModule: Codable {
    let name: String
    let platform: SymbolPlatform?
}

struct SymbolPlatform: Codable {
    let operatingSystem: PlatformOS?
    let architecture: String?

    struct PlatformOS: Codable {
        let name: String?
        let minimumVersion: PlatformVersion?
    }

    struct PlatformVersion: Codable {
        let major: Int?
        let minor: Int?
        let patch: Int?
    }
}

struct SymbolNode: Codable, Identifiable {
    let identifier: SymbolIdentifier
    let kind: SymbolKind
    let pathComponents: [String]?
    let names: SymbolNames?
    let docComment: DocComment?
    let declarationFragments: [DeclarationFragment]?
    let accessLevel: String?
    let location: SymbolLocation?

    var id: String { identifier.precise }

    struct SymbolIdentifier: Codable {
        let precise: String
        let interfaceLanguage: String?
    }

    struct SymbolKind: Codable {
        let identifier: String
        let displayName: String?
    }

    struct SymbolNames: Codable {
        let title: String?
        let subHeading: [DeclarationFragment]?
    }

    struct DocComment: Codable {
        let lines: [DocLine]?

        struct DocLine: Codable {
            let text: String?
        }
    }

    struct DeclarationFragment: Codable {
        let kind: String?
        let spelling: String?
        let preciseIdentifier: String?
    }

    struct SymbolLocation: Codable {
        let uri: String?
        let position: Position?

        struct Position: Codable {
            let line: Int?
            let character: Int?
        }
    }

    var displayName: String {
        names?.title ?? pathComponents?.last ?? identifier.precise
    }

    var kindLabel: String {
        kind.displayName ?? kind.identifier
    }

    var documentation: String? {
        docComment?.lines?.compactMap { $0.text }.joined(separator: "\n")
    }

    var declaration: String? {
        declarationFragments?.compactMap { $0.spelling }.joined()
    }
}

struct SymbolRelation: Codable {
    let source: String
    let target: String
    let kind: String
    let targetFallback: String?
}

// MARK: - Symbol Graph Service

@MainActor
final class SymbolGraphService: ObservableObject {

    static let shared = SymbolGraphService()

    @Published private(set) var isExtracting: Bool = false
    @Published private(set) var lastExtractedModule: String?
    @Published private(set) var symbolCount: Int = 0
    @Published private(set) var lastError: String?

    private var cachedGraph: SymbolGraph?
    private var cachedSummary: String?

    private init() {}

    // MARK: - Extract Symbol Graph

    /// Run `swift symbolgraph-extract` on a module and parse the result.
    func extractSymbolGraph(
        moduleName: String,
        projectPath: String,
        target: String? = nil
    ) async -> SymbolGraph? {
        isExtracting = true
        lastError = nil
        defer { isExtracting = false }

        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grump-symbolgraph-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Build arguments
        var args = [
            "swift", "symbolgraph-extract",
            "-module-name", moduleName,
            "-output-dir", outputDir.path,
            "-pretty-print"
        ]

        // Add target triple if specified
        if let target = target {
            args += ["-target", target]
        }

        // Add SDK path
        let sdkPath = await getSDKPath()
        if let sdk = sdkPath {
            args += ["-sdk", sdk]
        }

        // Add include paths from the project build
        let buildPath = URL(fileURLWithPath: projectPath)
            .appendingPathComponent(".build/debug")
        args += ["-I", buildPath.path]
        args += ["-F", buildPath.path]

        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            lastError = "Failed to run symbolgraph-extract: \(error.localizedDescription)"
            return nil
        }

        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            lastError = "symbolgraph-extract failed: \(errStr.prefix(500))"
            return nil
        }
        #else
        lastError = "Symbol graph extraction is not available on iOS"
        return nil
        #endif

        // Find and parse the output JSON
        let expectedFile = outputDir.appendingPathComponent("\(moduleName).symbols.json")
        guard FileManager.default.fileExists(atPath: expectedFile.path) else {
            // Try to find any .symbols.json file
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: outputDir.path)) ?? []
            guard let symbolsFile = contents.first(where: { $0.hasSuffix(".symbols.json") }) else {
                lastError = "No symbol graph JSON produced"
                return nil
            }
            return await parseSymbolGraphFile(outputDir.appendingPathComponent(symbolsFile), moduleName: moduleName)
        }

        return await parseSymbolGraphFile(expectedFile, moduleName: moduleName)
    }

    private func parseSymbolGraphFile(_ url: URL, moduleName: String) async -> SymbolGraph? {
        do {
            let data = try Data(contentsOf: url)
            let graph = try JSONDecoder().decode(SymbolGraph.self, from: data)
            cachedGraph = graph
            cachedSummary = nil
            lastExtractedModule = moduleName
            symbolCount = graph.symbols.count
            GRumpLogger.general.info("Parsed \(graph.symbols.count) symbols, \(graph.relationships.count) relationships for \(moduleName)")
            return graph
        } catch {
            lastError = "Failed to parse symbol graph: \(error.localizedDescription)"
            return nil
        }
    }

    private func getSDKPath() async -> String? {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    // MARK: - Summary for Agent Prompt

    /// Generate a concise API summary suitable for injection into the system prompt.
    /// This gives the agent compiler-level understanding of the project.
    func apiSummary(maxTokens: Int = 4000) -> String {
        guard let graph = cachedGraph else {
            return "No symbol graph loaded. Run extractSymbolGraph() first."
        }

        if let cached = cachedSummary { return cached }

        var lines: [String] = []
        lines.append("## Project API Surface: \(graph.module.name)")
        lines.append("")

        // Group symbols by kind
        let grouped = Dictionary(grouping: graph.symbols) { $0.kind.identifier }

        // Structs/Classes
        for kind in ["swift.struct", "swift.class", "swift.enum", "swift.protocol"] {
            guard let symbols = grouped[kind], !symbols.isEmpty else { continue }
            let kindName = symbols.first?.kind.displayName ?? kind
            lines.append("### \(kindName)s (\(symbols.count))")
            for sym in symbols.prefix(30) {
                let access = sym.accessLevel ?? "internal"
                if access == "private" || access == "fileprivate" { continue }
                var line = "- `\(sym.displayName)`"
                if let doc = sym.documentation?.prefix(80) {
                    line += " — \(doc)"
                }
                lines.append(line)
            }
            lines.append("")
        }

        // Methods/Properties for public types
        for kind in ["swift.method", "swift.property", "swift.func"] {
            guard let symbols = grouped[kind], !symbols.isEmpty else { continue }
            let publicSymbols = symbols.filter {
                ($0.accessLevel ?? "internal") != "private" &&
                ($0.accessLevel ?? "internal") != "fileprivate"
            }
            if publicSymbols.isEmpty { continue }
            let kindName = symbols.first?.kind.displayName ?? kind
            lines.append("### \(kindName)s (\(publicSymbols.count) non-private)")
            for sym in publicSymbols.prefix(50) {
                let decl = sym.declaration ?? sym.displayName
                lines.append("- `\(String(decl.prefix(100)))`")
            }
            lines.append("")
        }

        // Relationships summary
        let conformances = graph.relationships.filter { $0.kind == "conformsTo" }
        let inherits = graph.relationships.filter { $0.kind == "inheritsFrom" }
        if !conformances.isEmpty || !inherits.isEmpty {
            lines.append("### Relationships")
            for rel in conformances.prefix(20) {
                let target = rel.targetFallback ?? rel.target
                lines.append("- conformsTo: \(target)")
            }
            for rel in inherits.prefix(10) {
                let target = rel.targetFallback ?? rel.target
                lines.append("- inheritsFrom: \(target)")
            }
        }

        // Truncate if too long
        var summary = lines.joined(separator: "\n")
        if summary.count > maxTokens * 4 { // rough char-to-token estimate
            summary = String(summary.prefix(maxTokens * 4)) + "\n\n... (truncated)"
        }

        cachedSummary = summary
        return summary
    }

    // MARK: - DocC Generation

    /// Run `swift package generate-documentation` for a project.
    func generateDocC(projectPath: String) async -> (success: Bool, output: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "package", "generate-documentation"]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)

        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, "Failed to run: \(error.localizedDescription)")
        }

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        let success = process.terminationStatus == 0
        return (success, success ? output : errOutput)
        #else
        return (false, "DocC generation is not available on iOS")
        #endif
    }

    // MARK: - Query Helpers

    /// Find symbols matching a query string.
    func search(query: String) -> [SymbolNode] {
        guard let graph = cachedGraph else { return [] }
        let lowered = query.lowercased()
        return graph.symbols.filter { sym in
            sym.displayName.lowercased().contains(lowered) ||
            (sym.documentation?.lowercased().contains(lowered) ?? false)
        }
    }

    /// Get all symbols of a specific kind (e.g., "swift.struct", "swift.class").
    func symbols(ofKind kind: String) -> [SymbolNode] {
        guard let graph = cachedGraph else { return [] }
        return graph.symbols.filter { $0.kind.identifier == kind }
    }

    /// Get conformances for a type.
    func conformances(of symbolId: String) -> [String] {
        guard let graph = cachedGraph else { return [] }
        return graph.relationships
            .filter { $0.source == symbolId && $0.kind == "conformsTo" }
            .map { $0.targetFallback ?? $0.target }
    }

    /// Get members of a type.
    func members(of symbolId: String) -> [SymbolNode] {
        guard let graph = cachedGraph else { return [] }
        let memberIds = Set(graph.relationships
            .filter { $0.target == symbolId && $0.kind == "memberOf" }
            .map { $0.source })
        return graph.symbols.filter { memberIds.contains($0.identifier.precise) }
    }
}
