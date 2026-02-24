import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Terminal Session Model

struct TerminalSession: Identifiable {
    let id = UUID()
    var title: String
    var workingDirectory: String
    var isRunning: Bool = false
    var output: AttributedString = AttributedString()
    var rawOutput: String = ""
    var exitCode: Int32?
}

// MARK: - Terminal Service

@MainActor
final class TerminalService: ObservableObject {
    @Published var sessions: [TerminalSession] = []
    @Published var activeSessionIndex: Int = 0
    @Published var commandInput: String = ""

    private var processes: [UUID: Process] = [:]

    var activeSession: TerminalSession? {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return nil }
        return sessions[activeSessionIndex]
    }

    func createSession(workingDirectory: String) {
        let resolvedDir = workingDirectory.isEmpty
            ? (FileManager.default.homeDirectoryForCurrentUser.path)
            : workingDirectory
        let session = TerminalSession(
            title: "Terminal \(sessions.count + 1)",
            workingDirectory: resolvedDir
        )
        sessions.append(session)
        activeSessionIndex = sessions.count - 1
    }

    func closeSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }
        let session = sessions[index]
        if let process = processes[session.id] {
            process.terminate()
            processes.removeValue(forKey: session.id)
        }
        sessions.remove(at: index)
        if activeSessionIndex >= sessions.count {
            activeSessionIndex = max(0, sessions.count - 1)
        }
    }

    func runCommand(_ command: String) {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }
        let sessionId = sessions[activeSessionIndex].id
        let dir = sessions[activeSessionIndex].workingDirectory

        sessions[activeSessionIndex].isRunning = true
        sessions[activeSessionIndex].rawOutput += "$ \(command)\n"
        sessions[activeSessionIndex].output = parseANSI(sessions[activeSessionIndex].rawOutput)

        let idx = activeSessionIndex

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
                    self.sessions[idx].rawOutput += text
                    self.sessions[idx].output = self.parseANSI(self.sessions[idx].rawOutput)
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    guard let self = self, idx < self.sessions.count else { return }
                    self.sessions[idx].rawOutput += text
                    self.sessions[idx].output = self.parseANSI(self.sessions[idx].rawOutput)
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
                    self.sessions[idx].rawOutput += "Error: \(error.localizedDescription)\n"
                    self.sessions[idx].output = self.parseANSI(self.sessions[idx].rawOutput)
                }
            }

            // Clean up pipe handlers to prevent retain cycles
            pipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            await MainActor.run { [weak self] in
                guard let self = self, idx < self.sessions.count else { return }
                self.sessions[idx].isRunning = false
                self.sessions[idx].exitCode = process.terminationStatus
                self.sessions[idx].rawOutput += "\n"
                self.sessions[idx].output = self.parseANSI(self.sessions[idx].rawOutput)
                self.processes.removeValue(forKey: sessionId)
            }
        }
    }

    func interruptActive() {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }
        let sessionId = sessions[activeSessionIndex].id
        if let process = processes[sessionId] {
            process.interrupt()
        }
    }

    func clearActive() {
        guard activeSessionIndex >= 0 && activeSessionIndex < sessions.count else { return }
        sessions[activeSessionIndex].rawOutput = ""
        sessions[activeSessionIndex].output = AttributedString()
    }

    // MARK: - ANSI Parsing

    func parseANSI(_ raw: String) -> AttributedString {
        // Strip ANSI escape codes for basic rendering
        let stripped = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
        var result = AttributedString(stripped)
        result.font = .system(size: 12, weight: .regular, design: .monospaced)
        return result
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
                    HStack(spacing: Spacing.xs) {
                        ForEach(Array(service.sessions.enumerated()), id: \.element.id) { index, session in
                            terminalTab(index: index, session: session)
                        }

                        Button(action: {
                            service.createSession(workingDirectory: viewModel.workingDirectory)
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(themeManager.palette.textMuted)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .help("New terminal")
                    }
                    .padding(.horizontal, Spacing.lg)
                }

                Spacer()

                if let session = service.activeSession, session.isRunning {
                    Button(action: { service.interruptActive() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(Typography.captionSmall)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Interrupt (Ctrl+C)")
                }

                Button(action: { service.clearActive() }) {
                    Image(systemName: "trash")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Clear")
                .padding(.trailing, Spacing.lg)
            }
            .padding(.vertical, Spacing.md)
            .background(themeManager.palette.bgCard)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Terminal output
            if service.sessions.isEmpty {
                emptyState
            } else if let session = service.activeSession {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(session.output)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.lg)
                            .id("bottom")
                    }
                    .onChange(of: session.rawOutput) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .background(Color.black.opacity(0.85))

                // Command input
                HStack(spacing: Spacing.md) {
                    Text("$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentGreen)

                    TextField("command…", text: $service.commandInput)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)
                        .foregroundColor(.white)
                        .focused($inputFocused)
                        .onSubmit {
                            guard !service.commandInput.isEmpty else { return }
                            service.runCommand(service.commandInput)
                            service.commandInput = ""
                        }

                    if service.activeSession?.isRunning == true {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
                .background(Color.black.opacity(0.9))
            }
        }
        .background(Color.black.opacity(0.85))
        .onAppear {
            if service.sessions.isEmpty {
                service.createSession(workingDirectory: viewModel.workingDirectory)
            }
        }
    }

    private func terminalTab(index: Int, session: TerminalSession) -> some View {
        let isActive = index == service.activeSessionIndex

        return HStack(spacing: Spacing.sm) {
            if session.isRunning {
                Circle()
                    .fill(Color.accentGreen)
                    .frame(width: 5, height: 5)
            }

            Text(session.title)
                .font(Typography.micro)
                .foregroundColor(isActive ? themeManager.palette.textPrimary : themeManager.palette.textMuted)
                .lineLimit(1)

            if service.sessions.count > 1 {
                Button(action: { service.closeSession(at: index) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isActive ? themeManager.palette.bgElevated : Color.clear)
        )
        .onTapGesture { service.activeSessionIndex = index }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "terminal.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("Terminal")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Open a terminal session to run commands")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)

            Button(action: {
                service.createSession(workingDirectory: viewModel.workingDirectory)
            }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "plus")
                    Text("New Terminal")
                        .font(Typography.captionSmallSemibold)
                }
                .foregroundColor(themeManager.palette.effectiveAccent)
            }
            .buttonStyle(ScaleButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
