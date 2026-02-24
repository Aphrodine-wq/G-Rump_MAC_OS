import Foundation

#if os(macOS)

// MARK: - Security Level

enum ExecSecurityLevel: String, Codable, CaseIterable {
    case deny
    case ask
    case allowlist
    case allow
}

// MARK: - Allowlist Entry

struct ExecAllowlistEntry: Codable, Identifiable {
    var id: String { pattern }
    let pattern: String
    let source: String // e.g. "user", "always-allow"
}

// MARK: - Exec Approvals Config

struct ExecApprovalsConfig: Codable {
    var version: Int
    var security: ExecSecurityLevel
    var askOnMiss: Bool
    var allowlist: [ExecAllowlistEntry]

    static let currentVersion = 1

    static var `default`: ExecApprovalsConfig {
        ExecApprovalsConfig(
            version: currentVersion,
            security: .deny,
            askOnMiss: true,
            allowlist: []
        )
    }
}

// MARK: - Storage

enum ExecApprovalsStorage {
    private static let fileName = "exec-approvals.json"

    static var fileURL: URL {
        let dir: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let grump = appSupport.appendingPathComponent("GRump", isDirectory: true)
            if !FileManager.default.fileExists(atPath: grump.path) {
                try? FileManager.default.createDirectory(at: grump, withIntermediateDirectories: true)
            }
            dir = grump
        } else {
            dir = FileManager.default.temporaryDirectory
        }
        return dir.appendingPathComponent(fileName)
    }

    static func load() -> ExecApprovalsConfig {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ExecApprovalsConfig.self, from: data) else {
            return .default
        }
        return decoded
    }

    static func save(_ config: ExecApprovalsConfig) {
        let url = fileURL
        var toSave = config
        toSave.version = ExecApprovalsConfig.currentVersion
        guard let data = try? JSONEncoder().encode(toSave) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns true if the resolved binary path matches the glob pattern.
    /// Pattern may be a full path or a glob (e.g. "/opt/homebrew/bin/*").
    static func path(_ resolvedPath: String, matchesPattern pattern: String) -> Bool {
        let path = (resolvedPath as NSString).standardizingPath
        let patternNorm = (pattern as NSString).standardizingPath
        if !patternNorm.contains("*") {
            return path == patternNorm
        }
        let parts = patternNorm.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var idx = path.startIndex
        for (i, part) in parts.enumerated() {
            if part.isEmpty {
                if i == parts.count - 1 { return true }
                continue
            }
            guard let range = path.range(of: part, range: idx..<path.endIndex) else { return false }
            idx = range.upperBound
        }
        return idx == path.endIndex
    }
}

#endif
