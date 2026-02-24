import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var perfAdvisor = PerformanceAdvisor.shared
    @State private var showGitShortcuts = false
    
    var body: some View {
        HStack(spacing: Spacing.xl) {
            // Left section - connection status
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                
                Text(connectionStatus)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            
            Spacer()
            
            // Center section - git shortcuts
            if !viewModel.workingDirectory.isEmpty {
                Button(action: { showGitShortcuts.toggle() }) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10))
                        Text("Git")
                            .font(Typography.micro)
                    }
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showGitShortcuts, arrowEdge: .top) {
                    GitShortcutsPopover(workingDirectory: viewModel.workingDirectory)
                        .environmentObject(themeManager)
                }
            }
            
            // Performance indicator
            if perfAdvisor.isUnderPressure || perfAdvisor.appMemoryMB > 500 {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: perfAdvisor.thermalState == .critical ? "thermometer.sun.fill" :
                            perfAdvisor.thermalState == .serious ? "thermometer.high" : "memorychip")
                        .font(.system(size: 10))
                        .foregroundColor(perfAdvisor.isUnderPressure ? .accentOrange : themeManager.palette.textMuted)
                    Text(String(format: "%.0f MB", perfAdvisor.appMemoryMB))
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .help(perfAdvisor.statusSummary)
            }

            // Right section - errors and info
            HStack(spacing: Spacing.md) {
                if let error = viewModel.errorMessage {
                    Button(action: { viewModel.errorMessage = nil }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentOrange)
                            Text("Error")
                                .font(Typography.micro)
                                .foregroundColor(.accentOrange)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                if viewModel.isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                        Text("AI working...")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .background(themeManager.palette.bgSidebar)
        .overlay(
            Rectangle()
                .fill(themeManager.palette.borderCrisp)
                .frame(height: Border.thin),
            alignment: .top
        )
    }
    
    private var connectionColor: Color {
        if viewModel.isLoading { return .accentGreen }
        return viewModel.platformUser != nil ? .accentGreen : .accentOrange
    }
    
    private var connectionStatus: String {
        if viewModel.isLoading { return "Streaming..." }
        if viewModel.platformUser != nil { return "Connected" }
        return "Guest mode"
    }
}

struct GitShortcutsPopover: View {
    @EnvironmentObject var themeManager: ThemeManager
    let workingDirectory: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Git Shortcuts")
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textPrimary)
            
            Divider()
            
            GitShortcutButton(label: "Status", shortcut: "⌘⇧G S") {
                runGitCommand("status")
            }
            GitShortcutButton(label: "Commit", shortcut: "⌘⇧G C") {
                runGitCommand("commit")
            }
            GitShortcutButton(label: "Push", shortcut: "⌘⇧G P") {
                runGitCommand("push")
            }
            GitShortcutButton(label: "Pull", shortcut: "⌘⇧G L") {
                runGitCommand("pull")
            }
            GitShortcutButton(label: "Log", shortcut: "⌘⇧G G") {
                runGitCommand("log --oneline -10")
            }
        }
        .padding(Spacing.lg)
        .frame(width: 180)
    }
    
    private func runGitCommand(_ args: String) {
        #if os(macOS)
        Task {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args.components(separatedBy: " ")
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try? process.run()
            process.waitUntilExit()
        }
        #endif
    }
}

struct GitShortcutButton: View {
    @EnvironmentObject var themeManager: ThemeManager
    let label: String
    let shortcut: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                Text(shortcut)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Spacing.xs)
    }
}

#if swift(>=5.9) && canImport(SwiftUI)
@available(macOS 14.0, iOS 17.0, *)
private struct StatusBarPreview: PreviewProvider {
    static var previews: some View {
        StatusBarView(viewModel: ChatViewModel())
            .environmentObject(ThemeManager())
    }
}
#endif
