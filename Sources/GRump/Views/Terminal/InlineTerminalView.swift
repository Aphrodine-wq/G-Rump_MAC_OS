import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Terminal Colors

private enum TerminalColors {
    static let background = Color(red: 0.11, green: 0.11, blue: 0.13)
    static let inputBackground = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let tabBarBackground = Color(red: 0.14, green: 0.14, blue: 0.16)
    static let activeTabBackground = Color(red: 0.20, green: 0.20, blue: 0.22)
    static let textPrimary = Color(red: 0.85, green: 0.85, blue: 0.85)
    static let textMuted = Color(red: 0.50, green: 0.50, blue: 0.54)
    static let promptUser = Color(red: 0.35, green: 0.78, blue: 0.98)
    static let promptDir = Color(red: 0.40, green: 0.85, blue: 0.55)
    static let promptSymbol = Color(red: 0.85, green: 0.85, blue: 0.85)
    static let errorText = Color(red: 0.95, green: 0.40, blue: 0.40)
    static let runningDot = Color(red: 0.30, green: 0.85, blue: 0.45)
    static let border = Color.white.opacity(0.06)
}

// MARK: - Terminal Session Model

struct TerminalSession: Identifiable {
    let id = UUID()
    var title: String
    var workingDirectory: String
    var isRunning: Bool = false
    var outputLines: [TerminalLine] = []
    var rawOutput: String = ""
    var exitCode: Int32?
}

struct TerminalLine: Identifiable {
    let id = UUID()
    enum Kind { case command, stdout, stderr, status }
    let kind: Kind
    let text: String
    let cwd: String?
}

// MARK: - Terminal Service

@MainActor
final class TerminalService: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionIndex: Int = 0
    @Published var commandInput: String = ""
    @Published var commandHistory: [String] = []
    @Published var historyIndex: Int = -1

    #if os(macOS)
    private var processes: [UUID: Process] = [:]
    #endif

    var activeSession: TerminalSession? {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return nil }
        return sessions[activeSessionIndex]
    }

    func createSession(workingDirectory: String) {
        let resolvedDir = workingDirectory.isEmpty
            ? NSHomeDirectory()
            : workingDirectory
        let dirName = (resolvedDir as NSString).lastPathComponent
        let session = TerminalSession(
            title: dirName.isEmpty ? "Terminal" : dirName,
            workingDirectory: resolvedDir
        )
        sessions.append(session)
        activeSessionIndex = sessions.count - 1
    }

    func closeSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }
        let session = sessions[index]
        #if os(macOS)
        if let process = processes[session.id] {
            process.terminate()
            processes.removeValue(forKey: session.id)
        }
        #endif
        sessions.remove(at: index)
        if activeSessionIndex >= sessions.count {
            activeSessionIndex = max(0, sessions.count - 1)
        }
    }

    func navigateHistory(up: Bool) {
        guard !commandHistory.isEmpty else { return }
        if up {
            if historyIndex < commandHistory.count - 1 {
                historyIndex += 1
                commandInput = commandHistory[commandHistory.count - 1 - historyIndex]
            }
        } else {
            if historyIndex > 0 {
                historyIndex -= 1
                commandInput = commandHistory[commandHistory.count - 1 - historyIndex]
            } else {
                historyIndex = -1
                commandInput = ""
            }
        }
    }

    func runCommand(_ command: String) {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }

        // Add to history
        if !command.trimmingCharacters(in: .whitespaces).isEmpty {
            commandHistory.append(command)
        }
        historyIndex = -1

        // Handle `cd` commands locally — update working directory without spawning a process
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        if trimmed == "cd" || trimmed.hasPrefix("cd ") {
            let idx = activeSessionIndex
            let currentDir = sessions[idx].workingDirectory
            let targetArg = trimmed == "cd" ? "~" : String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            let cmdLine = TerminalLine(kind: .command, text: command, cwd: currentDir)
            sessions[idx].outputLines.append(cmdLine)

            let resolved: String
            if targetArg == "~" || targetArg.isEmpty {
                resolved = NSHomeDirectory()
            } else if targetArg == "-" {
                // cd - is not tracked, treat as no-op
                sessions[idx].outputLines.append(
                    TerminalLine(kind: .stderr, text: "cd -: previous directory not tracked", cwd: nil)
                )
                return
            } else if targetArg.hasPrefix("/") {
                resolved = targetArg
            } else if targetArg.hasPrefix("~") {
                resolved = NSHomeDirectory() + String(targetArg.dropFirst())
            } else {
                resolved = (currentDir as NSString).appendingPathComponent(targetArg)
            }

            // Resolve symlinks and normalize
            let standardized = (resolved as NSString).standardizingPath

            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir), isDir.boolValue {
                sessions[idx].workingDirectory = standardized
                sessions[idx].title = (standardized as NSString).lastPathComponent
            } else {
                sessions[idx].outputLines.append(
                    TerminalLine(kind: .stderr, text: "cd: no such file or directory: \(targetArg)", cwd: nil)
                )
            }
            return
        }

        #if os(macOS)
        let sessionId = sessions[activeSessionIndex].id
        let dir = sessions[activeSessionIndex].workingDirectory
        let idx = activeSessionIndex

        // Add command line to output
        let cmdLine = TerminalLine(kind: .command, text: command, cwd: dir)
        sessions[idx].outputLines.append(cmdLine)
        sessions[idx].isRunning = true

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", command]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, idx < self.sessions.count else { return }
                    let lines = text.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        self.sessions[idx].outputLines.append(
                            TerminalLine(kind: .stdout, text: line, cwd: nil)
                        )
                    }
                    self.sessions[idx].rawOutput += text
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, idx < self.sessions.count else { return }
                    let lines = text.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        self.sessions[idx].outputLines.append(
                            TerminalLine(kind: .stderr, text: line, cwd: nil)
                        )
                    }
                    self.sessions[idx].rawOutput += text
                }
            }

            do {
                try process.run()
                await MainActor.run { [weak self] in
                    self?.processes[sessionId] = process
                }
                process.waitUntilExit()
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self, idx < self.sessions.count else { return }
                    self.sessions[idx].outputLines.append(
                        TerminalLine(kind: .stderr, text: "Error: \(error.localizedDescription)", cwd: nil)
                    )
                }
            }

            pipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            await MainActor.run { [weak self] in
                guard let self = self, idx < self.sessions.count else { return }
                self.sessions[idx].isRunning = false
                self.sessions[idx].exitCode = process.terminationStatus
                if process.terminationStatus != 0 {
                    self.sessions[idx].outputLines.append(
                        TerminalLine(kind: .status, text: "Process exited with code \(process.terminationStatus)", cwd: nil)
                    )
                }
                self.processes.removeValue(forKey: sessionId)
            }
        }
        #endif
    }

    func interruptActive() {
        #if os(macOS)
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }
        let sessionId = sessions[activeSessionIndex].id
        if let process = processes[sessionId] {
            process.interrupt()
        }
        #endif
    }

    func clearActive() {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }
        sessions[activeSessionIndex].outputLines = []
        sessions[activeSessionIndex].rawOutput = ""
    }
}

// MARK: - Inline Terminal View

struct InlineTerminalView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = TerminalService()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(service.sessions.enumerated()), id: \.element.id) { index, session in
                            terminalTab(index: index, session: session)
                        }

                        Button(action: {
                            service.createSession(workingDirectory: viewModel.workingDirectory)
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(TerminalColors.textMuted)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("New terminal")
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                HStack(spacing: 6) {
                    if let session = service.activeSession, session.isRunning {
                        Button(action: { service.interruptActive() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TerminalColors.errorText)
                        }
                        .buttonStyle(.plain)
                        .help("Interrupt (Ctrl+C)")
                    }

                    Button(action: { service.clearActive() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TerminalColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
                .padding(.trailing, 10)
            }
            .padding(.vertical, 6)
            .background(TerminalColors.tabBarBackground)

            Rectangle()
                .fill(TerminalColors.border)
                .frame(height: 1)

            // Terminal output
            if service.sessions.isEmpty {
                emptyState
            } else if let session = service.activeSession {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(session.outputLines) { line in
                                terminalLineView(line)
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: session.outputLines.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .background(TerminalColors.background)

                // Command input line
                HStack(spacing: 6) {
                    // CWD-aware prompt
                    promptView(cwd: service.activeSession?.workingDirectory ?? "~")

                    TextField("", text: $service.commandInput)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)
                        .foregroundColor(TerminalColors.textPrimary)
                        .focused($inputFocused)
                        .onSubmit {
                            guard !service.commandInput.isEmpty else { return }
                            service.runCommand(service.commandInput)
                            service.commandInput = ""
                        }

                    if service.activeSession?.isRunning == true {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(TerminalColors.inputBackground)
                .overlay(
                    Rectangle()
                        .fill(TerminalColors.border)
                        .frame(height: 1),
                    alignment: .top
                )
            }
        }
        .background(TerminalColors.background)
        .onAppear {
            if service.sessions.isEmpty {
                service.createSession(workingDirectory: viewModel.workingDirectory)
            }
            inputFocused = true
        }
    }

    // MARK: - Prompt View

    @ViewBuilder
    private func promptView(cwd: String) -> some View {
        let dir = abbreviatePath(cwd)
        HStack(spacing: 0) {
            Text(NSUserName())
                .foregroundColor(TerminalColors.promptUser)
            Text(":")
                .foregroundColor(TerminalColors.textMuted)
            Text(dir)
                .foregroundColor(TerminalColors.promptDir)
            Text(" $")
                .foregroundColor(TerminalColors.promptSymbol)
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home) {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    // MARK: - Terminal Line Rendering

    @ViewBuilder
    private func terminalLineView(_ line: TerminalLine) -> some View {
        switch line.kind {
        case .command:
            HStack(spacing: 0) {
                promptView(cwd: line.cwd ?? "~")
                Text(" ")
                Text(line.text)
                    .foregroundColor(TerminalColors.textPrimary)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.vertical, 1)
            .textSelection(.enabled)

        case .stdout:
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(TerminalColors.textPrimary)
                .textSelection(.enabled)
                .padding(.vertical, 0.5)

        case .stderr:
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(TerminalColors.errorText)
                .textSelection(.enabled)
                .padding(.vertical, 0.5)

        case .status:
            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(TerminalColors.textMuted)
                .italic()
                .padding(.vertical, 2)
        }
    }

    // MARK: - Tab View

    private func terminalTab(index: Int, session: TerminalSession) -> some View {
        let isActive = index == service.activeSessionIndex

        return HStack(spacing: 5) {
            if session.isRunning {
                Circle()
                    .fill(TerminalColors.runningDot)
                    .frame(width: 5, height: 5)
            }

            Image(systemName: "terminal")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isActive ? TerminalColors.textPrimary : TerminalColors.textMuted)

            Text(session.title)
                .font(.system(size: 11, weight: isActive ? .medium : .regular))
                .foregroundColor(isActive ? TerminalColors.textPrimary : TerminalColors.textMuted)
                .lineLimit(1)

            if service.sessions.count > 1 {
                Button(action: { service.closeSession(at: index) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(TerminalColors.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? TerminalColors.activeTabBackground : Color.clear)
        )
        .onTapGesture { service.activeSessionIndex = index }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(TerminalColors.textMuted)
            Text("Terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TerminalColors.textPrimary)
            Text("Press \u{2318}T or click + to open a session")
                .font(.system(size: 12))
                .foregroundColor(TerminalColors.textMuted)

            Button(action: {
                service.createSession(workingDirectory: viewModel.workingDirectory)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                    Text("New Terminal")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(TerminalColors.promptUser)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(TerminalColors.promptUser.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TerminalColors.background)
    }
}
