import Foundation
import OSLog

// MARK: - Temporal Code Intelligence
//
// Gives the agent a time dimension for understanding code:
//   - File volatility: Which files change most frequently (hotspots)
//   - Change velocity: Is a module accelerating in changes (instability signal)
//   - Correlation: Files that always change together (hidden coupling)
//   - Decay detection: Files untouched for months but still imported (tech debt)
//   - Authorship: Who owns which files (for context)
//
// No AI coding tool understands code over time. They all see a snapshot.
// This gives the agent historical awareness so it makes better decisions.

// MARK: - File Temporal Profile

struct FileTemporalProfile: Identifiable, Codable {
    var id: String { filePath }
    let filePath: String
    var changeCount: Int
    var lastChanged: Date
    var firstSeen: Date
    var recentVelocity: Double      // Changes per week in last 30 days
    var authors: [String]
    var coupledFiles: [String]      // Files that always change with this one
    var classification: Classification

    enum Classification: String, Codable, CaseIterable {
        case hotspot = "Hotspot"            // High change frequency
        case stable = "Stable"              // Low change frequency, recently active
        case decaying = "Decaying"          // Not touched in months, possibly stale
        case accelerating = "Accelerating"  // Change velocity increasing
        case coupled = "Coupled"            // Always changes with other files

        var icon: String {
            switch self {
            case .hotspot:      return "flame"
            case .stable:       return "checkmark.shield"
            case .decaying:     return "clock.badge.exclamationmark"
            case .accelerating: return "arrow.up.right"
            case .coupled:      return "link"
            }
        }

        var riskLevel: String {
            switch self {
            case .hotspot:      return "High risk — changes frequently, more likely to have regressions"
            case .stable:       return "Low risk — well-established, rarely changes"
            case .decaying:     return "Medium risk — possibly outdated, may need review"
            case .accelerating: return "High risk — change rate increasing, potential instability"
            case .coupled:      return "Medium risk — changes cascade to coupled files"
            }
        }
    }
}

// MARK: - Temporal Snapshot

struct TemporalSnapshot: Codable {
    let generatedAt: Date
    let workingDirectory: String
    var profiles: [FileTemporalProfile]
    var couplingPairs: [(String, String, Double)]  // (fileA, fileB, couplingScore)

    /// Top N hotspots by change frequency.
    func topHotspots(_ n: Int = 5) -> [FileTemporalProfile] {
        profiles.filter { $0.classification == .hotspot }
            .sorted { $0.changeCount > $1.changeCount }
            .prefix(n).map { $0 }
    }

    /// Files that haven't been touched in > 90 days but are still in the project.
    func decayingFiles() -> [FileTemporalProfile] {
        profiles.filter { $0.classification == .decaying }
            .sorted { $0.lastChanged < $1.lastChanged }
    }

    /// Files with accelerating change velocity.
    func acceleratingFiles() -> [FileTemporalProfile] {
        profiles.filter { $0.classification == .accelerating }
            .sorted { $0.recentVelocity > $1.recentVelocity }
    }

    /// System prompt fragment summarizing temporal intelligence.
    func promptSummary(maxTokens: Int = 800) -> String {
        var lines: [String] = []
        lines.append("# Temporal Code Intelligence\n")

        let hotspots = topHotspots(5)
        if !hotspots.isEmpty {
            lines.append("## Hotspots (most frequently changed)")
            for h in hotspots {
                let rel = makeRelativePath(h.filePath, base: workingDirectory)
                lines.append("- `\(rel)`: \(h.changeCount) changes, velocity \(String(format: "%.1f", h.recentVelocity))/week")
            }
        }

        let accel = acceleratingFiles().prefix(3)
        if !accel.isEmpty {
            lines.append("\n## Accelerating (change rate increasing)")
            for a in accel {
                let rel = makeRelativePath(a.filePath, base: workingDirectory)
                lines.append("- `\(rel)`: velocity \(String(format: "%.1f", a.recentVelocity))/week (↑)")
            }
        }

        let decaying = decayingFiles().prefix(3)
        if !decaying.isEmpty {
            lines.append("\n## Decaying (untouched >90 days)")
            for d in decaying {
                let rel = makeRelativePath(d.filePath, base: workingDirectory)
                let days = Int(Date().timeIntervalSince(d.lastChanged) / 86400)
                lines.append("- `\(rel)`: last changed \(days) days ago")
            }
        }

        let couplings = couplingPairs.sorted { $0.2 > $1.2 }.prefix(3)
        if !couplings.isEmpty {
            lines.append("\n## Hidden Coupling (files that always change together)")
            for (a, b, score) in couplings {
                let relA = makeRelativePath(a, base: workingDirectory)
                let relB = makeRelativePath(b, base: workingDirectory)
                lines.append("- `\(relA)` ↔ `\(relB)` (\(Int(score * 100))% correlation)")
            }
        }

        let result = lines.joined(separator: "\n")
        // Rough token limit: ~4 chars per token
        if result.count > maxTokens * 4 {
            return String(result.prefix(maxTokens * 4))
        }
        return result
    }

    private func makeRelativePath(_ path: String, base: String) -> String {
        if path.hasPrefix(base) {
            let relative = String(path.dropFirst(base.count))
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        }
        return (path as NSString).lastPathComponent
    }

    // Codable conformance for tuple array
    enum CodingKeys: String, CodingKey {
        case generatedAt, workingDirectory, profiles, couplingPairsEncoded
    }

    struct CouplingEntry: Codable {
        let fileA: String
        let fileB: String
        let score: Double
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(workingDirectory, forKey: .workingDirectory)
        try container.encode(profiles, forKey: .profiles)
        let entries = couplingPairs.map { CouplingEntry(fileA: $0.0, fileB: $0.1, score: $0.2) }
        try container.encode(entries, forKey: .couplingPairsEncoded)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        workingDirectory = try container.decode(String.self, forKey: .workingDirectory)
        profiles = try container.decode([FileTemporalProfile].self, forKey: .profiles)
        let entries = try container.decode([CouplingEntry].self, forKey: .couplingPairsEncoded)
        couplingPairs = entries.map { ($0.fileA, $0.fileB, $0.score) }
    }

    init(generatedAt: Date, workingDirectory: String, profiles: [FileTemporalProfile], couplingPairs: [(String, String, Double)]) {
        self.generatedAt = generatedAt
        self.workingDirectory = workingDirectory
        self.profiles = profiles
        self.couplingPairs = couplingPairs
    }
}

// MARK: - Temporal Code Intelligence Service

@MainActor
final class TemporalCodeIntelligenceService: ObservableObject {

    static let shared = TemporalCodeIntelligenceService()

    @Published private(set) var snapshot: TemporalSnapshot?
    @Published private(set) var isAnalyzing = false

    private var lastAnalysisDirectory: String = ""
    private var lastAnalysisTime: Date = .distantPast
    private let cacheDuration: TimeInterval = 600 // 10 minutes
    private let logger = GRumpLogger.general

    private init() {}

    // MARK: - Analysis

    /// Analyze the git history of the working directory and build a temporal snapshot.
    /// Results are cached for 10 minutes per directory.
    func analyze(workingDirectory: String) async {
        guard !workingDirectory.isEmpty else { return }

        // Check cache
        if workingDirectory == lastAnalysisDirectory,
           Date().timeIntervalSince(lastAnalysisTime) < cacheDuration,
           snapshot != nil {
            return
        }

        // Try loading from disk cache first
        if let cached = loadCachedSnapshot(workingDirectory: workingDirectory),
           Date().timeIntervalSince(cached.generatedAt) < cacheDuration {
            snapshot = cached
            lastAnalysisDirectory = workingDirectory
            lastAnalysisTime = cached.generatedAt
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Run git log to get file change history
        let gitLog = await runGitLog(in: workingDirectory)
        guard !gitLog.isEmpty else {
            logger.info("TemporalCodeIntelligence: No git history found")
            return
        }

        let commits = parseGitLog(gitLog)
        guard !commits.isEmpty else { return }

        // Build profiles
        var fileChanges: [String: [(date: Date, author: String)]] = [:]
        var commitFileSets: [[String]] = []

        for commit in commits {
            var filesInCommit: [String] = []
            for file in commit.files {
                let fullPath = (workingDirectory as NSString).appendingPathComponent(file)
                fileChanges[fullPath, default: []].append((date: commit.date, author: commit.author))
                filesInCommit.append(fullPath)
            }
            if filesInCommit.count >= 2 {
                commitFileSets.append(filesInCommit)
            }
        }

        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
        let ninetyDaysAgo = now.addingTimeInterval(-90 * 86400)

        var profiles: [FileTemporalProfile] = []

        for (filePath, changes) in fileChanges {
            let sortedChanges = changes.sorted { $0.date > $1.date }
            let recentChanges = sortedChanges.filter { $0.date > thirtyDaysAgo }
            let recentVelocity = Double(recentChanges.count) / 4.0 // changes per week over 30 days

            let authors = Array(Set(changes.map(\.author)))
            let lastChanged = sortedChanges.first?.date ?? now
            let firstSeen = sortedChanges.last?.date ?? now

            // Classify
            let classification: FileTemporalProfile.Classification
            if lastChanged < ninetyDaysAgo {
                classification = .decaying
            } else if recentVelocity > 3.0 {
                // Check if velocity is increasing: compare last 2 weeks vs prior 2 weeks
                let twoWeeksAgo = now.addingTimeInterval(-14 * 86400)
                let lastTwoWeeks = sortedChanges.filter { $0.date > twoWeeksAgo }.count
                let priorTwoWeeks = sortedChanges.filter { $0.date > thirtyDaysAgo && $0.date <= twoWeeksAgo }.count
                if lastTwoWeeks > priorTwoWeeks + 1 {
                    classification = .accelerating
                } else {
                    classification = .hotspot
                }
            } else if changes.count > 20 {
                classification = .hotspot
            } else {
                classification = .stable
            }

            profiles.append(FileTemporalProfile(
                filePath: filePath,
                changeCount: changes.count,
                lastChanged: lastChanged,
                firstSeen: firstSeen,
                recentVelocity: recentVelocity,
                authors: authors,
                coupledFiles: [],
                classification: classification
            ))
        }

        // Detect coupling: files that appear in the same commit >60% of the time
        var couplingPairs: [(String, String, Double)] = []
        let fileList = Array(fileChanges.keys)

        for i in 0..<fileList.count {
            for j in (i+1)..<fileList.count {
                let fileA = fileList[i]
                let fileB = fileList[j]

                let commitsWithA = commitFileSets.filter { $0.contains(fileA) }.count
                let commitsWithB = commitFileSets.filter { $0.contains(fileB) }.count
                let commitsWithBoth = commitFileSets.filter { $0.contains(fileA) && $0.contains(fileB) }.count

                guard commitsWithBoth >= 3 else { continue }

                let minCommits = min(commitsWithA, commitsWithB)
                guard minCommits > 0 else { continue }

                let couplingScore = Double(commitsWithBoth) / Double(minCommits)
                if couplingScore >= 0.6 {
                    couplingPairs.append((fileA, fileB, couplingScore))

                    // Mark files as coupled
                    if let idxA = profiles.firstIndex(where: { $0.filePath == fileA }) {
                        profiles[idxA].coupledFiles.append(fileB)
                        if profiles[idxA].classification == .stable {
                            profiles[idxA].classification = .coupled
                        }
                    }
                    if let idxB = profiles.firstIndex(where: { $0.filePath == fileB }) {
                        profiles[idxB].coupledFiles.append(fileA)
                        if profiles[idxB].classification == .stable {
                            profiles[idxB].classification = .coupled
                        }
                    }
                }
            }
        }

        let newSnapshot = TemporalSnapshot(
            generatedAt: now,
            workingDirectory: workingDirectory,
            profiles: profiles,
            couplingPairs: couplingPairs
        )

        snapshot = newSnapshot
        lastAnalysisDirectory = workingDirectory
        lastAnalysisTime = now

        // Cache to disk
        saveCachedSnapshot(newSnapshot, workingDirectory: workingDirectory)

        logger.info("TemporalCodeIntelligence: Analyzed \(profiles.count) files, found \(couplingPairs.count) coupling pairs")
    }

    /// Get the temporal profile for a specific file.
    func profile(for filePath: String) -> FileTemporalProfile? {
        snapshot?.profiles.first { $0.filePath == filePath }
    }

    /// Get the risk assessment for modifying a set of files.
    func riskAssessment(for filePaths: [String]) -> String? {
        guard let snap = snapshot else { return nil }

        let profiles = filePaths.compactMap { path in
            snap.profiles.first { $0.filePath == path }
        }
        guard !profiles.isEmpty else { return nil }

        let hotspots = profiles.filter { $0.classification == .hotspot || $0.classification == .accelerating }
        let coupled = profiles.flatMap(\.coupledFiles).filter { coupled in
            !filePaths.contains(coupled)
        }

        var warnings: [String] = []
        if !hotspots.isEmpty {
            let names = hotspots.map { ($0.filePath as NSString).lastPathComponent }
            warnings.append("Hotspot files being modified: \(names.joined(separator: ", "))")
        }
        if !coupled.isEmpty {
            let uniqueCoupled = Array(Set(coupled)).prefix(3)
            let names = uniqueCoupled.map { ($0 as NSString).lastPathComponent }
            warnings.append("Coupled files that may also need changes: \(names.joined(separator: ", "))")
        }

        return warnings.isEmpty ? nil : warnings.joined(separator: ". ")
    }

    // MARK: - Git Log Parsing

    private func runGitLog(in directory: String) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Get last 500 commits with files changed, formatted for parsing
        process.arguments = ["log", "--pretty=format:COMMIT|%H|%an|%aI", "--name-only", "-n", "500"]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            logger.error("TemporalCodeIntelligence: git log failed: \(error.localizedDescription)")
            return ""
        }
    }

    private struct GitCommit {
        let hash: String
        let author: String
        let date: Date
        let files: [String]
    }

    private func parseGitLog(_ log: String) -> [GitCommit] {
        let lines = log.components(separatedBy: "\n")
        var commits: [GitCommit] = []
        var currentCommit: (hash: String, author: String, date: Date)?
        var currentFiles: [String] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone, .withDashSeparatorInDate, .withColonSeparatorInTime]

        for line in lines {
            if line.hasPrefix("COMMIT|") {
                // Save previous commit
                if let commit = currentCommit, !currentFiles.isEmpty {
                    commits.append(GitCommit(
                        hash: commit.hash,
                        author: commit.author,
                        date: commit.date,
                        files: currentFiles
                    ))
                }

                // Parse new commit header
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 4 else { continue }
                let hash = parts[1]
                let author = parts[2]
                let dateStr = parts[3]
                let date = isoFormatter.date(from: dateStr) ?? Date()

                currentCommit = (hash: hash, author: author, date: date)
                currentFiles = []
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty, currentCommit != nil {
                currentFiles.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        // Don't forget the last commit
        if let commit = currentCommit, !currentFiles.isEmpty {
            commits.append(GitCommit(
                hash: commit.hash,
                author: commit.author,
                date: commit.date,
                files: currentFiles
            ))
        }

        return commits
    }

    // MARK: - Disk Cache

    private func cacheURL(workingDirectory: String) -> URL {
        let grumpDir = (workingDirectory as NSString).appendingPathComponent(".grump")
        return URL(fileURLWithPath: grumpDir).appendingPathComponent("temporal.json")
    }

    private func saveCachedSnapshot(_ snapshot: TemporalSnapshot, workingDirectory: String) {
        let url = cacheURL(workingDirectory: workingDirectory)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func loadCachedSnapshot(workingDirectory: String) -> TemporalSnapshot? {
        let url = cacheURL(workingDirectory: workingDirectory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TemporalSnapshot.self, from: data)
    }
}
