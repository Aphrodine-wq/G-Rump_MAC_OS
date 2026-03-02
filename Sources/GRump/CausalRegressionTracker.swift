import Foundation
import OSLog

// MARK: - Causal Regression Tracker
//
// When a build fails or test breaks, traces backward through git history
// to find the exact commit that introduced the regression. Automated
// git bisect on steroids — uses the agent's understanding of error messages
// to correlate failures with specific diffs.
//
// No AI tool traverses git history to find *when* something broke and
// *what specific change* caused it. This gives the agent temporal debugging.

// MARK: - Regression Analysis

struct RegressionAnalysis: Identifiable {
    let id = UUID()
    let errorMessage: String
    let suspectedCommit: SuspectedCommit?
    let relatedCommits: [SuspectedCommit]
    let analysisMethod: AnalysisMethod
    let confidence: Double
    let timestamp: Date

    enum AnalysisMethod: String {
        case symbolTrace      // Traced error symbols through git history
        case fileHistory      // Analyzed recent changes to error-related files
        case bisectLike       // Walked commits checking build/test status
    }

    /// Formatted markdown for conversation injection.
    var markdownSummary: String {
        var lines: [String] = []
        lines.append("**Regression Analysis** (confidence: \(Int(confidence * 100))%)")
        lines.append("")

        if let commit = suspectedCommit {
            lines.append("**Suspected cause:** commit `\(commit.shortHash)` by \(commit.author)")
            lines.append("  *\(commit.message)*")
            lines.append("  \(commit.timeAgo)")
            if !commit.changedFiles.isEmpty {
                lines.append("  Changed files:")
                for file in commit.changedFiles.prefix(5) {
                    lines.append("  - `\(file)`")
                }
            }
            if let diff = commit.relevantDiff {
                lines.append("")
                lines.append("  **Relevant diff:**")
                lines.append("  ```")
                lines.append("  \(String(diff.prefix(500)))")
                lines.append("  ```")
            }
        } else {
            lines.append("Could not identify a specific commit. The issue may predate recent history.")
        }

        if !relatedCommits.isEmpty {
            lines.append("")
            lines.append("**Other potentially related commits:**")
            for commit in relatedCommits.prefix(3) {
                lines.append("- `\(commit.shortHash)` \(commit.message) (\(commit.timeAgo))")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Suspected Commit

struct SuspectedCommit: Identifiable {
    let id = UUID()
    let hash: String
    let shortHash: String
    let author: String
    let message: String
    let date: Date
    let changedFiles: [String]
    let relevantDiff: String?
    let relevanceScore: Double

    var timeAgo: String {
        let interval = Date().timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - Causal Regression Tracker

@MainActor
final class CausalRegressionTracker: ObservableObject {

    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastAnalysis: RegressionAnalysis?

    private let logger = GRumpLogger.general

    // MARK: - Analysis

    /// Analyze a build or test failure to find its root cause in git history.
    func analyze(
        errorOutput: String,
        failedCommand: String,
        workingDirectory: String
    ) async -> RegressionAnalysis? {
        guard !workingDirectory.isEmpty, !errorOutput.isEmpty else { return nil }

        isAnalyzing = true
        defer { isAnalyzing = false }

        // Step 1: Extract file paths and symbols from the error
        let errorFiles = extractFilePaths(from: errorOutput, baseDir: workingDirectory)
        let errorSymbols = extractSymbols(from: errorOutput)

        guard !errorFiles.isEmpty || !errorSymbols.isEmpty else {
            logger.info("CausalRegressionTracker: No files or symbols found in error output")
            return nil
        }

        // Step 2: Get recent commits that touched these files
        let recentCommits = await getRecentCommits(
            for: errorFiles,
            symbols: errorSymbols,
            in: workingDirectory,
            limit: 20
        )

        guard !recentCommits.isEmpty else {
            logger.info("CausalRegressionTracker: No relevant commits found")
            return nil
        }

        // Step 3: Score commits by relevance to the error
        let scoredCommits = scoreCommits(recentCommits, errorOutput: errorOutput, errorFiles: errorFiles, errorSymbols: errorSymbols)

        // Step 4: Build analysis
        let topCommit = scoredCommits.first
        let relatedCommits = Array(scoredCommits.dropFirst().prefix(3))

        let analysis = RegressionAnalysis(
            errorMessage: String(errorOutput.prefix(500)),
            suspectedCommit: topCommit,
            relatedCommits: relatedCommits,
            analysisMethod: errorFiles.isEmpty ? .symbolTrace : .fileHistory,
            confidence: topCommit?.relevanceScore ?? 0.0,
            timestamp: Date()
        )

        lastAnalysis = analysis
        logger.info("CausalRegressionTracker: Analysis complete. Top suspect: \(topCommit?.shortHash ?? "none") (confidence: \(String(format: "%.0f%%", (topCommit?.relevanceScore ?? 0) * 100)))")

        return analysis
    }

    // MARK: - File & Symbol Extraction

    /// Extract file paths from compiler/test error output.
    private func extractFilePaths(from errorOutput: String, baseDir: String) -> [String] {
        var files: Set<String> = []
        let lines = errorOutput.components(separatedBy: .newlines)

        for line in lines {
            // Swift compiler: /path/to/File.swift:42:13: error: ...
            if let match = line.range(of: #"(/[^\s:]+\.\w+):\d+"#, options: .regularExpression) {
                let path = String(line[match]).components(separatedBy: ":").first ?? ""
                if !path.isEmpty { files.insert(path) }
            }

            // Relative paths: Sources/Module/File.swift:42
            if let match = line.range(of: #"(\S+/\S+\.\w+):\d+"#, options: .regularExpression) {
                let relPath = String(line[match]).components(separatedBy: ":").first ?? ""
                if !relPath.isEmpty {
                    let fullPath = (baseDir as NSString).appendingPathComponent(relPath)
                    if FileManager.default.fileExists(atPath: fullPath) {
                        files.insert(fullPath)
                    } else {
                        files.insert(relPath)
                    }
                }
            }

            // XCTest failures: TestFile.testMethod()
            if let match = line.range(of: #"(\w+Tests?)\.\w+\(\)"#, options: .regularExpression) {
                let testClass = String(line[match]).components(separatedBy: ".").first ?? ""
                files.insert(testClass)
            }
        }

        return Array(files)
    }

    /// Extract symbol names (types, functions, variables) from error output.
    private func extractSymbols(from errorOutput: String) -> [String] {
        var symbols: Set<String> = []
        let lines = errorOutput.components(separatedBy: .newlines)

        for line in lines {
            // Type names: 'TypeName' or type 'TypeName'
            let typePattern = #"(?:type|struct|class|enum|protocol)\s+'(\w+)'"#
            if let match = line.range(of: typePattern, options: .regularExpression) {
                let segment = String(line[match])
                if let quote1 = segment.firstIndex(of: "'"),
                   let quote2 = segment[segment.index(after: quote1)...].firstIndex(of: "'") {
                    symbols.insert(String(segment[segment.index(after: quote1)..<quote2]))
                }
            }

            // Function/member names: member 'functionName' or value 'name'
            let memberPattern = #"(?:member|value|property|method)\s+'(\w+)'"#
            if let match = line.range(of: memberPattern, options: .regularExpression) {
                let segment = String(line[match])
                if let quote1 = segment.firstIndex(of: "'"),
                   let quote2 = segment[segment.index(after: quote1)...].firstIndex(of: "'") {
                    symbols.insert(String(segment[segment.index(after: quote1)..<quote2]))
                }
            }

            // Undefined symbol: use of undeclared 'X'
            if line.contains("undeclared") || line.contains("undefined") || line.contains("unresolved") {
                let words = line.components(separatedBy: "'")
                if words.count >= 3 {
                    symbols.insert(words[1])
                }
            }
        }

        return Array(symbols).filter { $0.count > 2 } // Filter out noise
    }

    // MARK: - Git History

    /// Get recent commits that touched the error-related files or contain error symbols.
    private func getRecentCommits(
        for files: [String],
        symbols: [String],
        in directory: String,
        limit: Int
    ) async -> [SuspectedCommit] {
        var allCommits: [SuspectedCommit] = []

        // Get commits for each file
        for file in files.prefix(5) {
            let commits = await gitLogForFile(file, in: directory, limit: limit / 2)
            allCommits.append(contentsOf: commits)
        }

        // If no file-specific commits, get general recent commits
        if allCommits.isEmpty {
            allCommits = await gitLogRecent(in: directory, limit: limit)
        }

        // Deduplicate by hash
        var seen: Set<String> = []
        allCommits = allCommits.filter { seen.insert($0.hash).inserted }

        return allCommits
    }

    private func gitLogForFile(_ file: String, in directory: String, limit: Int) async -> [SuspectedCommit] {
        let relativePath: String
        if file.hasPrefix(directory) {
            relativePath = String(file.dropFirst(directory.count + 1))
        } else {
            relativePath = file
        }

        let output = await runGit(
            args: ["log", "--pretty=format:%H|%h|%an|%aI|%s", "--name-only", "-n", "\(limit)", "--", relativePath],
            in: directory
        )
        return parseGitOutput(output, in: directory)
    }

    private func gitLogRecent(in directory: String, limit: Int) async -> [SuspectedCommit] {
        let output = await runGit(
            args: ["log", "--pretty=format:%H|%h|%an|%aI|%s", "--name-only", "-n", "\(limit)"],
            in: directory
        )
        return parseGitOutput(output, in: directory)
    }

    private func parseGitOutput(_ output: String, in directory: String) -> [SuspectedCommit] {
        let lines = output.components(separatedBy: "\n")
        var commits: [SuspectedCommit] = []
        var currentHeader: (hash: String, shortHash: String, author: String, date: Date, message: String)?
        var currentFiles: [String] = []

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withFullTime, .withTimeZone, .withDashSeparatorInDate, .withColonSeparatorInTime]

        for line in lines {
            if line.contains("|") && line.components(separatedBy: "|").count >= 5 {
                // Save previous commit
                if let header = currentHeader {
                    commits.append(SuspectedCommit(
                        hash: header.hash,
                        shortHash: header.shortHash,
                        author: header.author,
                        message: header.message,
                        date: header.date,
                        changedFiles: currentFiles,
                        relevantDiff: nil,
                        relevanceScore: 0.0
                    ))
                }

                let parts = line.components(separatedBy: "|")
                let date = isoFormatter.date(from: parts[3]) ?? Date()
                currentHeader = (
                    hash: parts[0],
                    shortHash: parts[1],
                    author: parts[2],
                    date: date,
                    message: parts.dropFirst(4).joined(separator: "|")
                )
                currentFiles = []
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                currentFiles.append(line.trimmingCharacters(in: .whitespaces))
            }
        }

        // Last commit
        if let header = currentHeader {
            commits.append(SuspectedCommit(
                hash: header.hash,
                shortHash: header.shortHash,
                author: header.author,
                message: header.message,
                date: header.date,
                changedFiles: currentFiles,
                relevantDiff: nil,
                relevanceScore: 0.0
            ))
        }

        return commits
    }

    // MARK: - Scoring

    /// Score commits by relevance to the error.
    private func scoreCommits(
        _ commits: [SuspectedCommit],
        errorOutput: String,
        errorFiles: [String],
        errorSymbols: [String]
    ) -> [SuspectedCommit] {
        let errorLower = errorOutput.lowercased()

        return commits.map { commit in
            var score = 0.0

            // File overlap: how many error files were changed in this commit
            let fileOverlap = commit.changedFiles.filter { changedFile in
                errorFiles.contains { errorFile in
                    errorFile.hasSuffix(changedFile) || changedFile.hasSuffix((errorFile as NSString).lastPathComponent)
                }
            }.count
            score += Double(fileOverlap) * 0.3

            // Symbol overlap: does the commit message mention error symbols
            let messageLower = commit.message.lowercased()
            let symbolHits = errorSymbols.filter { messageLower.contains($0.lowercased()) }.count
            score += Double(symbolHits) * 0.2

            // Recency bonus: more recent commits are more likely suspects
            let hoursAgo = Date().timeIntervalSince(commit.date) / 3600
            let recencyBonus = max(0, 0.2 - hoursAgo * 0.005)
            score += recencyBonus

            // Commit message keywords
            let riskKeywords = ["fix", "bug", "hack", "workaround", "temp", "todo", "wip", "broken", "revert"]
            let riskHits = riskKeywords.filter { messageLower.contains($0) }.count
            score += Double(riskHits) * 0.1

            // Error file name in commit files
            for errorFile in errorFiles {
                let baseName = (errorFile as NSString).lastPathComponent
                if commit.changedFiles.contains(where: { ($0 as NSString).lastPathComponent == baseName }) {
                    score += 0.15
                }
            }

            return SuspectedCommit(
                hash: commit.hash,
                shortHash: commit.shortHash,
                author: commit.author,
                message: commit.message,
                date: commit.date,
                changedFiles: commit.changedFiles,
                relevantDiff: commit.relevantDiff,
                relevanceScore: min(1.0, score)
            )
        }
        .sorted { $0.relevanceScore > $1.relevanceScore }
    }

    // MARK: - Git Runner

    private func runGit(args: [String], in directory: String) async -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
