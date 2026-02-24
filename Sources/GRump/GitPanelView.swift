import SwiftUI

// MARK: - Git Change Model

struct GitChange: Identifiable, Hashable {
    let id: String
    let status: ChangeStatus
    let path: String
    var isStaged: Bool

    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }

    enum ChangeStatus: String, Hashable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case untracked = "?"
        case conflicted = "U"

        var icon: String {
            switch self {
            case .modified: return "pencil.circle.fill"
            case .added: return "plus.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .renamed: return "arrow.right.circle.fill"
            case .untracked: return "questionmark.circle.fill"
            case .conflicted: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .modified: return .orange
            case .added: return .accentGreen
            case .deleted: return .red
            case .renamed: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .untracked: return Color(red: 0.5, green: 0.5, blue: 0.6)
            case .conflicted: return .red
            }
        }

        var label: String {
            switch self {
            case .modified: return "Modified"
            case .added: return "Added"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .untracked: return "Untracked"
            case .conflicted: return "Conflict"
            }
        }
    }
}

// MARK: - Git Branch

struct GitBranchInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let isCurrent: Bool
    let isRemote: Bool
}

// MARK: - Git Service

@MainActor
final class GitService: ObservableObject {
    @Published var changes: [GitChange] = []
    @Published var branches: [GitBranchInfo] = []
    @Published var currentBranch: String = ""
    @Published var commitLog: [GitCommitInfo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var suggestedCommitMessage: String = ""

    private var workingDirectory: String = ""

    func setDirectory(_ path: String) {
        workingDirectory = path
        refresh()
    }

    func refresh() {
        guard !workingDirectory.isEmpty else { return }
        isLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            async let changesResult = Self.parseStatus(dir: dir)
            async let branchResult = Self.parseBranches(dir: dir)
            async let logResult = Self.parseLog(dir: dir)

            let changes = await changesResult
            let (branches, current) = await branchResult
            let log = await logResult

            await MainActor.run {
                self.changes = changes
                self.branches = branches
                self.currentBranch = current
                self.commitLog = log
                self.isLoading = false
            }
        }
    }

    func stageFile(_ path: String) {
        runGit(["add", path])
    }

    func unstageFile(_ path: String) {
        runGit(["restore", "--staged", path])
    }

    func stageAll() {
        runGit(["add", "-A"])
    }

    func commit(message: String) {
        guard !message.isEmpty else { return }
        runGit(["commit", "-m", message])
    }

    func checkoutBranch(_ name: String) {
        runGit(["checkout", name])
    }

    func createBranch(_ name: String) {
        runGit(["checkout", "-b", name])
    }

    func push() {
        runGit(["push"])
    }

    func pull() {
        runGit(["pull"])
    }

    private func runGit(_ args: [String]) {
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            try? await Task.sleep(for: .milliseconds(500))
            await self.refresh()
        }
    }

    private static func parseStatus(dir: String) -> [GitChange] {
        guard let output = runGitSync(["status", "--porcelain=v1"], dir: dir) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let str = String(line)
            guard str.count >= 4 else { return nil }
            let indexStatus = str[str.index(str.startIndex, offsetBy: 0)]
            let workStatus = str[str.index(str.startIndex, offsetBy: 1)]
            let path = String(str.dropFirst(3))

            let status: GitChange.ChangeStatus
            let isStaged: Bool

            if indexStatus == "?" {
                status = .untracked; isStaged = false
            } else if indexStatus == "U" || workStatus == "U" {
                status = .conflicted; isStaged = false
            } else if indexStatus != " " && workStatus == " " {
                status = Self.mapStatus(indexStatus); isStaged = true
            } else {
                status = Self.mapStatus(workStatus != " " ? workStatus : indexStatus)
                isStaged = indexStatus != " " && indexStatus != "?"
            }

            return GitChange(id: path, status: status, path: path, isStaged: isStaged)
        }
    }

    private static func mapStatus(_ char: Character) -> GitChange.ChangeStatus {
        switch char {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "?": return .untracked
        case "U": return .conflicted
        default: return .modified
        }
    }

    private static func parseBranches(dir: String) -> ([GitBranchInfo], String) {
        guard let output = runGitSync(["branch", "-a", "--no-color"], dir: dir) else { return ([], "") }
        var branches: [GitBranchInfo] = []
        var current = ""
        for line in output.split(separator: "\n") {
            let str = String(line).trimmingCharacters(in: .whitespaces)
            let isCurrent = str.hasPrefix("* ")
            let name = str.replacingOccurrences(of: "* ", with: "")
            if isCurrent { current = name }
            let isRemote = name.hasPrefix("remotes/")
            if name.contains("HEAD ->") { continue }
            branches.append(GitBranchInfo(id: name, name: name, isCurrent: isCurrent, isRemote: isRemote))
        }
        return (branches, current)
    }

    private static func parseLog(dir: String) -> [GitCommitInfo] {
        guard let output = runGitSync(["log", "--oneline", "-20", "--no-color"], dir: dir) else { return [] }
        return output.split(separator: "\n").map { line in
            let str = String(line)
            let parts = str.split(separator: " ", maxSplits: 1)
            let hash = parts.count > 0 ? String(parts[0]) : ""
            let message = parts.count > 1 ? String(parts[1]) : ""
            return GitCommitInfo(id: hash, hash: hash, message: message)
        }
    }

    private static func runGitSync(_ args: [String], dir: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

struct GitCommitInfo: Identifiable, Hashable {
    let id: String
    let hash: String
    let message: String
}

// MARK: - Git Panel View

struct GitPanelView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var gitService = GitService()
    @State private var commitMessage = ""
    @State private var showBranches = false
    @State private var newBranchName = ""
    @State private var showNewBranch = false
    @State private var selectedSection: GitSection = .changes

    enum GitSection: String, CaseIterable {
        case changes = "Changes"
        case history = "History"
        case branches = "Branches"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                // Branch indicator
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text(gitService.currentBranch.isEmpty ? "—" : gitService.currentBranch)
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(1)
                }

                Spacer()

                // Push / Pull
                Button(action: { gitService.pull() }) {
                    Image(systemName: "arrow.down")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Pull")

                Button(action: { gitService.push() }) {
                    Image(systemName: "arrow.up")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Push")

                Button(action: { gitService.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Section picker
            Picker("", selection: $selectedSection) {
                ForEach(GitSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            switch selectedSection {
            case .changes:
                changesSection
            case .history:
                historySection
            case .branches:
                branchesSection
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { gitService.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            gitService.setDirectory(newDir)
        }
    }

    // MARK: - Changes

    private var changesSection: some View {
        VStack(spacing: 0) {
            if gitService.changes.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.accentGreen)
                    Text("Working tree clean")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Staged
                        let staged = gitService.changes.filter { $0.isStaged }
                        if !staged.isEmpty {
                            sectionHeader("Staged Changes", count: staged.count)
                            ForEach(staged) { change in
                                GitChangeRow(change: change) {
                                    gitService.unstageFile(change.path)
                                }
                            }
                        }

                        // Unstaged
                        let unstaged = gitService.changes.filter { !$0.isStaged }
                        if !unstaged.isEmpty {
                            sectionHeader("Changes", count: unstaged.count)
                            ForEach(unstaged) { change in
                                GitChangeRow(change: change) {
                                    gitService.stageFile(change.path)
                                }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }

                // Commit area
                commitArea
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(Typography.captionSmallSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("\(count)")
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 1)
                .background(themeManager.palette.bgElevated)
                .clipShape(Capsule())
            Spacer()
            if title == "Changes" {
                Button(action: { gitService.stageAll() }) {
                    Text("Stage All")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    private var commitArea: some View {
        VStack(spacing: Spacing.md) {
            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            HStack(spacing: Spacing.md) {
                TextField("Commit message…", text: $commitMessage)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)

                Button(action: {
                    gitService.commit(message: commitMessage)
                    commitMessage = ""
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Commit")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(commitMessage.isEmpty || gitService.changes.filter({ $0.isStaged }).isEmpty)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(themeManager.palette.bgCard)
    }

    // MARK: - History

    private var historySection: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(gitService.commitLog) { commit in
                    HStack(spacing: Spacing.lg) {
                        Text(String(commit.hash.prefix(7)))
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .frame(width: 56, alignment: .leading)

                        Text(commit.message)
                            .font(Typography.bodySmall)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                }
            }
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Branches

    private var branchesSection: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(gitService.branches.filter({ !$0.isRemote })) { branch in
                        HStack(spacing: Spacing.lg) {
                            Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                                .font(Typography.captionSmall)
                                .foregroundColor(branch.isCurrent ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)

                            Text(branch.name)
                                .font(Typography.bodySmall)
                                .foregroundColor(branch.isCurrent ? themeManager.palette.effectiveAccent : themeManager.palette.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            if !branch.isCurrent {
                                Button(action: { gitService.checkoutBranch(branch.name) }) {
                                    Text("Switch")
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.textMuted)
                                }
                                .buttonStyle(ScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }

            // New branch
            HStack(spacing: Spacing.md) {
                TextField("New branch name…", text: $newBranchName)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)

                Button(action: {
                    if !newBranchName.isEmpty {
                        gitService.createBranch(newBranchName)
                        newBranchName = ""
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(newBranchName.isEmpty)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgCard)
        }
    }
}

// MARK: - Git Change Row

struct GitChangeRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let change: GitChange
    var onToggleStage: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            Image(systemName: change.status.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(change.status.color)
                .frame(width: 16)

            // File path
            HStack(spacing: 0) {
                Text(change.directory)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                Text(change.fileName)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
            }
            .lineLimit(1)

            Spacer()

            if isHovered {
                Button(action: onToggleStage) {
                    Image(systemName: change.isStaged ? "minus.circle" : "plus.circle")
                        .font(Typography.captionSmall)
                        .foregroundColor(change.isStaged ? .orange : .accentGreen)
                }
                .buttonStyle(ScaleButtonStyle())
                .help(change.isStaged ? "Unstage" : "Stage")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, 3)
        .background(isHovered ? themeManager.palette.bgElevated.opacity(0.3) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }
}
