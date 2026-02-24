import Foundation
#if os(macOS)
import AppKit
import CoreGraphics
import ImageIO
#endif

// MARK: - Git, Build, Web, Database, Image, Docker, IDE Tool Execution
// Extracted from ChatViewModel+ToolExecution.swift for maintainability.

extension ChatViewModel {

    // MARK: - Build & Lint

    func executeRunBuild(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        if let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty {
            return await runShellCommand(command, cwd: cwd, timeoutSeconds: 300)
        }
        let dir = (cwd as NSString).standardizingPath
        let fm = FileManager.default
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("npm run build", cwd: cwd, timeoutSeconds: 300)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
            return await runShellCommand("swift build", cwd: cwd, timeoutSeconds: 300)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("cargo build", cwd: cwd, timeoutSeconds: 300)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Makefile")) {
            return await runShellCommand("make", cwd: cwd, timeoutSeconds: 300)
        }
        return "No supported project (package.json, Package.swift, Cargo.toml, Makefile). Pass 'command' to run a custom build."
    }

    func executeRunLinter(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        if let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty {
            let pathArg = args["path"] as? String
            let dir = pathArg.map { resolvePath($0) } ?? cwd
            var isDir: ObjCBool = false
            let resolvedDir = FileManager.default.fileExists(atPath: dir, isDirectory: &isDir) && isDir.boolValue ? dir : (dir as NSString).deletingLastPathComponent
            return await runShellCommand(command, cwd: resolvedDir, timeoutSeconds: 120)
        }
        let pathArg = (args["path"] as? String).map { resolvePath($0) } ?? cwd
        var isDir: ObjCBool = false
        let dir = FileManager.default.fileExists(atPath: pathArg, isDirectory: &isDir) && isDir.boolValue ? pathArg : (pathArg as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("npx eslint . 2>/dev/null || true", cwd: dir, timeoutSeconds: 120)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
            return await runShellCommand("swiftlint 2>/dev/null || true", cwd: dir, timeoutSeconds: 120)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("pyproject.toml")) {
            return await runShellCommand("ruff check . 2>/dev/null || true", cwd: dir, timeoutSeconds: 120)
        }
        if fm.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("cargo clippy --no-deps 2>/dev/null || true", cwd: dir, timeoutSeconds: 120)
        }
        return "No linter detected (eslint, swiftlint, ruff, clippy). Pass 'command' to run a custom linter."
    }

    func executeRunFormat(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        if let cmd = args["command"] as? String, !cmd.isEmpty {
            return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 60)
        }
        let path = (args["path"] as? String).map { resolvePath($0) } ?? cwd
        let dir = (path as NSString).deletingLastPathComponent
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("npx prettier --write . 2>/dev/null || true", cwd: dir, timeoutSeconds: 60)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("pyproject.toml")) {
            return await runShellCommand("ruff format . 2>/dev/null || black . 2>/dev/null || true", cwd: dir, timeoutSeconds: 60)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("cargo fmt", cwd: dir, timeoutSeconds: 60)
        }
        return await runShellCommand("swiftformat . 2>/dev/null || true", cwd: dir, timeoutSeconds: 60)
    }

    func executeGetPackageDeps(_ args: [String: Any]) async -> String {
        let cwd = (args["path"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory)
        let dir = (cwd as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("cat package.json | grep -A 1000 '\"dependencies\"' | head -50", cwd: dir, timeoutSeconds: 5)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("requirements.txt")) {
            return await runShellCommand("cat requirements.txt", cwd: dir, timeoutSeconds: 5)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("grep -E '^\\[dependencies\\]|^[a-z]' Cargo.toml | head -80", cwd: dir, timeoutSeconds: 5)
        }
        return "No package file found (package.json, requirements.txt, Cargo.toml)"
    }

    func executeNpmInstall(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        if let pkg = args["package"] as? String, !pkg.isEmpty {
            let dev = args["dev"] as? Bool ?? false
            let safePkg = pkg.replacingOccurrences(of: "'", with: "'\\''")
            let cmd = dev ? "npm install '\(safePkg)' --save-dev" : "npm install '\(safePkg)'"
            return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 120)
        }
        return await runShellCommand("npm install", cwd: cwd, timeoutSeconds: 120)
    }

    func executePipInstall(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        if let pkg = args["package"] as? String, !pkg.isEmpty {
            return await runShellCommand("pip install \(pkg.replacingOccurrences(of: "'", with: "'\\''"))", cwd: cwd, timeoutSeconds: 120)
        }
        return await runShellCommand("pip install -r requirements.txt 2>/dev/null || pip install .", cwd: cwd, timeoutSeconds: 120)
    }

    func executeCargoAdd(_ args: [String: Any]) async -> String {
        guard let pkg = args["package"] as? String else { return "Error: missing package" }
        let cwd = workingDirectory.isEmpty ? FileManager.default.currentDirectoryPath : workingDirectory
        let dev = args["dev"] as? Bool ?? false
        let safePkg = pkg.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = dev ? "cargo add '\(safePkg)' --dev" : "cargo add '\(safePkg)'"
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 30)
    }

    // MARK: - Git

    func executeGitLog(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let limit = args["limit"] as? Int ?? 20
        let path = args["path"] as? String
        let oneline = (args["oneline"] as? Bool) ?? true
        var cmd = "git log -n \(limit)"
        if oneline { cmd += " --oneline" }
        if let p = path, !p.isEmpty {
            cmd += " -- '\(p.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 15)
    }

    func executeGitDiff(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let staged = (args["staged"] as? Bool) ?? false
        let path = args["path"] as? String
        let ref = args["ref"] as? String
        var cmd = "git diff"
        if staged { cmd += " --staged" }
        if let r = ref, !r.isEmpty { cmd += " \(r)" }
        if let p = path, !p.isEmpty {
            cmd += " -- '\(p.replacingOccurrences(of: "'", with: "'\\''"))'"
        }
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 15)
    }

    func executeGitBranch(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let all = (args["all"] as? Bool) ?? false
        let cmd = all ? "git branch -a" : "git branch"
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitShow(_ args: [String: Any]) async -> String {
        guard let ref = args["ref"] as? String,
              let path = args["path"] as? String else {
            return "Error: missing ref or path"
        }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let safePath = path.replacingOccurrences(of: "'", with: "'\\''")
        let safeRef = ref.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("git show '\(safeRef):\(safePath)'", cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitAdd(_ args: [String: Any]) async -> String {
        guard let paths = args["paths"] as? [String] else { return "Error: missing paths" }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let pathsStr = paths.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
        return await runShellCommand("git add \(pathsStr)", cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitCommit(_ args: [String: Any]) async -> String {
        guard let msg = args["message"] as? String else { return "Error: missing message" }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let safe = msg.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("git commit -m '\(safe)'", cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitStash(_ args: [String: Any]) async -> String {
        guard let action = args["action"] as? String else { return "Error: missing action (push or pop)" }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        if action == "push" {
            let msg = (args["message"] as? String).map { " \($0.replacingOccurrences(of: "'", with: "'\\''"))" } ?? ""
            return await runShellCommand("git stash push\(msg)", cwd: cwd, timeoutSeconds: 10)
        }
        return await runShellCommand("git stash pop", cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitCheckout(_ args: [String: Any]) async -> String {
        guard let target = args["target"] as? String else { return "Error: missing target" }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        if target == "--", let paths = args["paths"] as? [String], !paths.isEmpty {
            let quotedPaths = paths.map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }.joined(separator: " ")
            return await runShellCommand("git checkout -- \(quotedPaths)", cwd: cwd, timeoutSeconds: 10)
        }
        return await runShellCommand("git checkout \(target.replacingOccurrences(of: "'", with: "'\\''"))", cwd: cwd, timeoutSeconds: 10)
    }

    func executeGitPush(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let remote = (args["remote"] as? String ?? "origin").replacingOccurrences(of: "'", with: "'\\''")
        let branch = (args["branch"] as? String ?? "").replacingOccurrences(of: "'", with: "'\\''")
        let cmd = branch.isEmpty ? "git push '\(remote)'" : "git push '\(remote)' '\(branch)'"
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 30)
    }

    func executeGitPull(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let remote = (args["remote"] as? String ?? "origin").replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("git pull '\(remote)'", cwd: cwd, timeoutSeconds: 30)
    }

    func executeGitStatus(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let statusResult = await runShellCommand("git status", cwd: cwd, timeoutSeconds: 10)
        let includeDiffStat = (args["include_diff_stat"] as? Bool) ?? true
        if !includeDiffStat {
            return statusResult
        }
        let diffResult = await runShellCommand("git diff --stat", cwd: cwd, timeoutSeconds: 10)
        if diffResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return statusResult + "\n\n--- git diff --stat ---\n(no changes)"
        }
        return statusResult + "\n\n--- git diff --stat ---\n" + diffResult
    }

    func executeGitRemote(_ args: [String: Any]) async -> String {
        let cwd = (args["path"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        return await runShellCommand("git remote -v", cwd: cwd, timeoutSeconds: 5)
    }

    func executeGitTag(_ args: [String: Any]) async -> String {
        let cwd = (args["path"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        return await runShellCommand("git tag -l", cwd: cwd, timeoutSeconds: 5)
    }

    func executeGitReset(_ args: [String: Any]) async -> String {
        guard let mode = args["mode"] as? String else { return "Error: missing mode" }
        let validModes = ["soft", "mixed", "hard", "merge", "keep"]
        guard validModes.contains(mode) else {
            return "Error: invalid mode '\(mode)'. Use: \(validModes.joined(separator: ", "))"
        }
        let target = (args["target"] as? String ?? "HEAD").replacingOccurrences(of: "'", with: "'\\''")
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        return await runShellCommand("git reset --\(mode) '\(target)'", cwd: cwd, timeoutSeconds: 5)
    }

    // MARK: - Tests

    func executeRunTests(_ args: [String: Any]) async -> String {
        let cwd = workingDirectory.isEmpty ? (FileManager.default.currentDirectoryPath) : workingDirectory
        if let command = args["command"] as? String, !command.trimmingCharacters(in: .whitespaces).isEmpty {
            return await runShellCommand(command, cwd: cwd, timeoutSeconds: 120)
        }
        let dir = (cwd as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("npm test", cwd: cwd, timeoutSeconds: 120)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
            return await runShellCommand("swift test", cwd: cwd, timeoutSeconds: 120)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("pyproject.toml")) {
            return await runShellCommand("pytest", cwd: cwd, timeoutSeconds: 120)
        }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("cargo test", cwd: cwd, timeoutSeconds: 120)
        }
        return "No supported project file found (package.json, Package.swift, pyproject.toml, Cargo.toml). Pass a 'command' argument to run a custom test command."
    }

    // MARK: - Web & Network

    func executeWebSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: missing query"
        }

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://html.duckduckgo.com/html/?q=\(encoded)"

        guard let url = URL(string: searchURL) else {
            return "Error: could not form search URL"
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""

            var results: [(title: String, snippet: String, url: String)] = []
            let resultPattern = #"class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)</a>"#
            let snippetPattern = #"class="result__snippet"[^>]*>(.*?)</span>"#

            let titleRegex = try? NSRegularExpression(pattern: resultPattern, options: [.dotMatchesLineSeparators])
            let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators])

            let titleMatches = titleRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
            let snippetMatches = snippetRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

            for (i, match) in titleMatches.prefix(8).enumerated() {
                guard let urlRange = Range(match.range(at: 1), in: html),
                      let titleRange = Range(match.range(at: 2), in: html) else { continue }

                var resultURL = String(html[urlRange])
                if resultURL.contains("uddg="), let decoded = resultURL.components(separatedBy: "uddg=").last?.removingPercentEncoding {
                    resultURL = decoded.components(separatedBy: "&").first ?? decoded
                }

                let title = String(html[titleRange])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                var snippet = ""
                if i < snippetMatches.count,
                   let snippetRange = Range(snippetMatches[i].range(at: 1), in: html) {
                    snippet = String(html[snippetRange])
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if !title.isEmpty {
                    results.append((title: title, snippet: snippet, url: resultURL))
                }
            }

            if results.isEmpty {
                return "Web search for '\(query)' returned no results. Try a different query or use read_url with a specific documentation URL."
            }

            var output = "Search results for: \(query)\n\n"
            for (i, r) in results.enumerated() {
                output += "\(i + 1). \(r.title)\n"
                if !r.snippet.isEmpty { output += "   \(r.snippet)\n" }
                output += "   URL: \(r.url)\n\n"
            }
            return output
        } catch {
            return "Web search failed: \(error.localizedDescription). Try using read_url with a direct documentation URL instead."
        }
    }

    func executeReadURL(_ args: [String: Any]) async -> String {
        guard let urlString = args["url"] as? String,
              let url = URL(string: urlString) else {
            return "Error: invalid URL"
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                return "HTTP \(httpResponse.statusCode) for \(urlString)"
            }

            let text = String(data: data, encoding: .utf8) ?? "(binary content, \(data.count) bytes)"

            let stripped = text
                .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let limit = 12000
            if stripped.count > limit {
                return "Content from \(urlString) (\(stripped.count) chars, truncated):\n\n" + String(stripped.prefix(limit)) + "\n\n[Truncated at \(limit) characters]"
            }
            return "Content from \(urlString) (\(stripped.count) chars):\n\n" + stripped
        } catch {
            return "Error fetching URL: \(error.localizedDescription)"
        }
    }

    func executeFetchJson(_ args: [String: Any]) async -> String {
        guard let urlString = args["url"] as? String, let url = URL(string: urlString) else {
            return "Error: invalid URL"
        }
        do {
            var request = URLRequest(url: url)
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: pretty, encoding: .utf8) else {
                return "Response is not valid JSON"
            }
            return String(str.prefix(15000)) + (str.count > 15000 ? "\n\n[Truncated]" : "")
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executeDownloadFile(_ args: [String: Any]) async -> String {
        guard let urlString = args["url"] as? String, let url = URL(string: urlString),
              let path = args["path"] as? String else {
            return "Error: missing url or path"
        }
        let resolved = resolvePath(path)
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.createDirectory(at: URL(fileURLWithPath: resolved).deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: resolved) {
                try FileManager.default.removeItem(atPath: resolved)
            }
            try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: resolved))
            return "Downloaded to \(resolved)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executeHttpRequest(_ args: [String: Any]) async -> String {
        guard let urlString = args["url"] as? String, let url = URL(string: urlString) else {
            return "Error: invalid URL"
        }
        let method = (args["method"] as? String)?.uppercased() ?? "GET"
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        if let headers = args["headers"] as? [String: String] {
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }
        if let body = args["body"] as? String, !body.isEmpty {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            return "Status: \(status)\n\n\(body)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executePingHost(_ args: [String: Any]) async -> String {
        guard let host = args["host"] as? String else { return "Error: missing host" }
        let count = (args["count"] as? Int) ?? 3
        let safe = host.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("ping -c \(count) '\(safe)' 2>/dev/null || ping -n \(count) '\(safe)' 2>/dev/null", cwd: nil, timeoutSeconds: 15)
    }

    func executeResolveDns(_ args: [String: Any]) async -> String {
        guard let host = args["hostname"] as? String else { return "Error: missing hostname" }
        let safe = host.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("host '\(safe)' 2>/dev/null || nslookup '\(safe)' 2>/dev/null", cwd: nil, timeoutSeconds: 10)
    }

    // MARK: - SQLite

    func executeSqliteQuery(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String, let query = args["query"] as? String else {
            return "Error: missing path or query"
        }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: database file not found: \(resolved)"
        }
        let safePath = resolved.replacingOccurrences(of: "'", with: "'\\''")
        let safeQuery = query.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("sqlite3 -header -csv '\(safePath)' '\(safeQuery)'", cwd: nil, timeoutSeconds: 30)
    }

    func executeSqliteSchema(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else {
            return "Error: missing path"
        }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: database file not found: \(resolved)"
        }
        let safePath = resolved.replacingOccurrences(of: "'", with: "'\\''")
        if let table = args["table"] as? String, !table.isEmpty {
            let safeTable = table.replacingOccurrences(of: "'", with: "''")
            return await runShellCommand("sqlite3 '\(safePath)' \"SELECT sql FROM sqlite_master WHERE type='table' AND name='\(safeTable)'\"", cwd: nil, timeoutSeconds: 5)
        }
        return await runShellCommand("sqlite3 '\(safePath)' '.schema'", cwd: nil, timeoutSeconds: 5)
    }

    func executeSqliteTables(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else {
            return "Error: missing path"
        }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: database file not found: \(resolved)"
        }
        let safePath = resolved.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("sqlite3 '\(safePath)' \"SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name\"", cwd: nil, timeoutSeconds: 5)
    }

    // MARK: - Image

    func executeImageInfo(_ args: [String: Any]) -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: image file not found: \(resolved)"
        }
        let url = URL(fileURLWithPath: resolved)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return "Error: could not read image"
        }
        let count = CGImageSourceGetCount(src)
        var lines: [String] = []
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            if let w = props[kCGImagePropertyPixelWidth as String] as? Int,
               let h = props[kCGImagePropertyPixelHeight as String] as? Int {
                lines.append("Dimensions: \(w) x \(h)")
            }
            if let dpi = props[kCGImagePropertyDPIWidth as String] as? Double {
                lines.append("DPI: \(dpi)")
            }
        }
        if let uti = CGImageSourceGetType(src) {
            lines.append("Format: \(uti as String)")
        }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: resolved)
            if let size = attrs[.size] as? Int64 {
                lines.append("File size: \(size) bytes")
            }
        } catch {}
        lines.append("Frames: \(count)")
        return lines.joined(separator: "\n")
        #else
        return "image_info is available on macOS only"
        #endif
    }

    func executeImageResize(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: image file not found: \(resolved)"
        }
        let outPath = (args["output_path"] as? String).map { resolvePath($0) } ?? resolved
        let safeIn = resolved.replacingOccurrences(of: "'", with: "'\\''")
        let safeOut = outPath.replacingOccurrences(of: "'", with: "'\\''")
        let cmd: String
        if let maxW = args["max_width"] as? Int {
            cmd = "sips -Z \(maxW) '\(safeIn)' --out '\(safeOut)'"
        } else if let maxH = args["max_height"] as? Int {
            cmd = "sips -Z \(maxH) '\(safeIn)' --out '\(safeOut)'"
        } else if let w = args["width"] as? Int, let h = args["height"] as? Int {
            cmd = "sips -z \(h) \(w) '\(safeIn)' --out '\(safeOut)'"
        } else {
            return "Error: specify max_width, max_height, or width+height"
        }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 30)
        #else
        return "image_resize is available on macOS only"
        #endif
    }

    func executeImageConvert(_ args: [String: Any]) async -> String {
        #if os(macOS)
        guard let path = args["path"] as? String, let outputPath = args["output_path"] as? String else {
            return "Error: missing path or output_path"
        }
        let resolved = resolvePath(path)
        let outResolved = resolvePath(outputPath)
        guard FileManager.default.fileExists(atPath: resolved) else {
            return "Error: image file not found: \(resolved)"
        }
        let ext = (outputPath as NSString).pathExtension.lowercased()
        let format = ext == "jpg" || ext == "jpeg" ? "jpeg" : ext
        let quality = (args["quality"] as? Double).map { Int($0 * 100) } ?? 90
        let safeIn = resolved.replacingOccurrences(of: "'", with: "'\\''")
        let safeOut = outResolved.replacingOccurrences(of: "'", with: "'\\''")
        let qArg = format == "jpeg" ? " -s formatOptions \(quality)" : ""
        return await runShellCommand("sips -s format \(format)\(qArg) '\(safeIn)' --out '\(safeOut)'", cwd: nil, timeoutSeconds: 30)
        #else
        return "image_convert is available on macOS only"
        #endif
    }

    // MARK: - Env Files

    func executeReadEnvFile(_ args: [String: Any]) -> String {
        let path = (args["path"] as? String).map { resolvePath($0) } ?? resolvePath(".env")
        guard FileManager.default.fileExists(atPath: path) else {
            return "Error: .env file not found at \(path)"
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return "Error: could not read file"
        }
        var lines: [String] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if let eq = trimmed.firstIndex(of: "=") {
                let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                var val = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("\"") && val.hasSuffix("\"") { val = String(val.dropFirst().dropLast()) }
                if val.hasPrefix("'") && val.hasSuffix("'") { val = String(val.dropFirst().dropLast()) }
                lines.append("\(key)=\(val)")
            }
        }
        return lines.joined(separator: "\n")
    }

    func executeWriteEnvFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String, let vars = args["vars"] as? [String: Any] else {
            return "Error: missing path or vars"
        }
        let resolved = resolvePath(path)
        var existing: [String: String] = [:]
        if FileManager.default.fileExists(atPath: resolved),
           let content = try? String(contentsOfFile: resolved, encoding: .utf8) {
            for line in content.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if let eq = trimmed.firstIndex(of: "=") {
                    let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
                    let val = String(trimmed[trimmed.index(after: eq)...])
                    existing[key] = val
                }
            }
        }
        for (k, v) in vars {
            let key = k.uppercased().replacingOccurrences(of: " ", with: "_")
            existing[key] = "\(v)"
        }
        let out = existing.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        do {
            try out.write(toFile: resolved, atomically: true, encoding: .utf8)
            return "Wrote \(existing.count) vars to \(resolved)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Docker

    func executeDockerPs(_ args: [String: Any]) async -> String {
        let all = (args["all"] as? Bool) ?? true
        let cmd = all ? "docker ps -a" : "docker ps"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 15)
    }

    func executeDockerImages(_ args: [String: Any]) async -> String {
        return await runShellCommand("docker images", cwd: nil, timeoutSeconds: 15)
    }

    // MARK: - Swift IDE Intelligence Tool Implementations

    func executeAppleDocsSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else {
            return "Error: missing 'query' parameter"
        }
        let service = AppleDocSearchService()
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                service.search(query: query)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let result = service.formattedResults()
                continuation.resume(returning: result)
            }
        }
    }

    func executeLSPDiagnostics(_ args: [String: Any]) -> String {
        let fileFilter = args["file"] as? String
        let allDiags = lspDiagnostics

        let filtered: [(String, [LSPDiagnostic])]
        if let file = fileFilter {
            let fileName = (file as NSString).lastPathComponent
            filtered = allDiags.filter { $0.key.contains(fileName) }.map { ($0.key, $0.value) }
        } else {
            filtered = allDiags.map { ($0.key, $0.value) }
        }

        if filtered.isEmpty {
            return "No diagnostics found. SourceKit-LSP status: \(lspStatusMessage)"
        }

        var output = "SourceKit-LSP Diagnostics:\n"
        for (file, diags) in filtered.sorted(by: { $0.0 < $1.0 }) {
            output += "\n\(file):\n"
            for d in diags {
                output += "  :\(d.line):\(d.column) \(d.severity.label.lowercased()): \(d.message)\n"
            }
        }

        let errors = filtered.flatMap(\.1).filter { $0.severity == .error }.count
        let warnings = filtered.flatMap(\.1).filter { $0.severity == .warning }.count
        output += "\nSummary: \(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")"
        return output
    }

    func executeAccessibilityAudit(_ args: [String: Any]) async -> String {
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let issues = AccessibilityAuditService.scanSwiftFiles(dir: dir)
                let totalFiles = AccessibilityAuditService.countSwiftFiles(dir: dir)
                let filesWithIssues = Set(issues.map(\.file)).count
                let critical = issues.filter { $0.severity == .critical }.count
                let warnings = issues.filter { $0.severity == .warning }.count
                let suggestions = issues.filter { $0.severity == .suggestion }.count

                var output = "Accessibility Audit Results:\n"
                output += "Files scanned: \(totalFiles), Files with issues: \(filesWithIssues)\n"
                output += "Critical: \(critical), Warnings: \(warnings), Suggestions: \(suggestions)\n\n"

                for issue in issues.prefix(30) {
                    let sev = issue.severity == .critical ? "CRITICAL" : issue.severity == .warning ? "WARNING" : "SUGGESTION"
                    output += "[\(sev)] \(issue.file):\(issue.line) — \(issue.message)\n"
                    output += "  Fix: \(issue.suggestion)\n\n"
                }

                if issues.count > 30 {
                    output += "... and \(issues.count - 30) more issues\n"
                }

                continuation.resume(returning: output)
            }
        }
    }

    func executeLocalizationAudit(_ args: [String: Any]) async -> String {
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let (catalog, entries, locales) = LocalizationService.findAndParse(dir: dir)
                let hardcoded = LocalizationService.scanForHardcodedStrings(dir: dir)

                var output = "Localization Audit Results:\n"
                output += "Catalog: \(catalog.isEmpty ? "None found" : catalog)\n"
                output += "Locales: \(locales.joined(separator: ", "))\n"
                output += "Entries: \(entries.count)\n"
                output += "Hardcoded strings found: \(hardcoded.count)\n\n"

                if !hardcoded.isEmpty {
                    output += "Hardcoded Strings:\n"
                    for hs in hardcoded.prefix(20) {
                        output += "  \(hs.file):\(hs.line) — \"\(hs.text)\"\n"
                    }
                    if hardcoded.count > 20 {
                        output += "  ... and \(hardcoded.count - 20) more\n"
                    }
                }

                let untranslated = entries.filter { $0.state == .needsReview }
                if !untranslated.isEmpty {
                    output += "\nUntranslated Keys (\(untranslated.count)):\n"
                    for entry in untranslated.prefix(15) {
                        output += "  \(entry.key) — \"\(entry.baseValue)\"\n"
                    }
                }

                continuation.resume(returning: output)
            }
        }
    }

    func executeSPMResolve(_ args: [String: Any]) async -> String {
        let action = args["action"] as? String ?? "status"
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }

        let packagePath = (dir as NSString).appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packagePath) else {
            return "Error: No Package.swift found in \(dir)"
        }

        switch action {
        case "resolve":
            return await runProcess(executablePath: "/usr/bin/swift", arguments: ["package", "resolve"], cwd: dir, stdoutLimitLines: 50)
        case "update":
            return await runProcess(executablePath: "/usr/bin/swift", arguments: ["package", "update"], cwd: dir, stdoutLimitLines: 50)
        default:
            return await withCheckedContinuation { continuation in
                Task.detached(priority: .userInitiated) {
                    let deps = SPMService.parseDependencies(dir: dir)
                    let targets = SPMService.parseTargets(dir: dir)
                    let version = SPMService.getSwiftVersion()

                    var output = "Swift Package Manager Status:\n"
                    output += "\(version)\n\n"

                    output += "Dependencies (\(deps.count)):\n"
                    for dep in deps {
                        let resolved = dep.resolvedVersion.map { " → v\($0)" } ?? ""
                        output += "  \(dep.name) ≥\(dep.version)\(resolved)\n"
                        output += "    \(dep.url)\n"
                    }

                    output += "\nTargets (\(targets.count)):\n"
                    for target in targets {
                        output += "  [\(target.type.rawValue)] \(target.name)\n"
                    }

                    continuation.resume(returning: output)
                }
            }
        }
    }

    func executeAppStoreChecklist(_ args: [String: Any]) async -> String {
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }

        return await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let checks = AppStoreService.performChecks(dir: dir)

                var output = "App Store Submission Checklist:\n\n"
                let passed = checks.filter { $0.status == .pass }.count
                let failed = checks.filter { $0.status == .fail }.count
                let warnings = checks.filter { $0.status == .warning }.count

                output += "Results: \(passed) passed, \(failed) failed, \(warnings) warnings\n\n"

                for check in checks {
                    let icon: String
                    switch check.status {
                    case .pass: icon = "✓"
                    case .fail: icon = "✗"
                    case .warning: icon = "⚠"
                    case .notChecked: icon = "–"
                    }
                    output += "\(icon) \(check.title)\n"
                    output += "  \(check.detail)\n\n"
                }

                continuation.resume(returning: output)
            }
        }
    }
}
