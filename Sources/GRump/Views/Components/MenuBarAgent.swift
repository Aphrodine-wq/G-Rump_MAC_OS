import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Menu Bar Agent

/// Rich, context-aware menu bar experience replacing the basic MenuBarExtraView.
/// Shows active project, agent status, recent activity, and proactive suggestion badges.
struct MenuBarAgent: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject private var ambientMonitor = AmbientMonitor.shared

    @AppStorage("ShowMenuBarExtra") private var showMenuBarExtra = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with project info
            headerSection

            Divider()

            // Agent status
            agentStatusSection

            Divider()

            // Quick actions
            quickActionsSection

            Divider()

            // Recent activity
            recentActivitySection

            Divider()

            // Suggestion badges (connects to ProactiveEngine)
            suggestionSection

            Divider()

            // Footer
            footerSection
        }
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                Text("G-Rump")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            if !viewModel.workingDirectory.isEmpty {
                let projectName = (viewModel.workingDirectory as NSString).lastPathComponent
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(projectName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            if !ambientMonitor.currentApp.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "app.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(ambientMonitor.currentApp)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    // MARK: - Agent Status

    private var agentStatusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(viewModel.isLoading ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(viewModel.isLoading ? "Working…" : "Ready")
                    .font(.caption)
                    .foregroundColor(.primary)
                Spacer()
                if let step = viewModel.currentAgentStep, let maxStep = viewModel.currentAgentStepMax {
                    Text("Step \(step)/\(maxStep)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let model = viewModel.currentEnhancedModel {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(model.displayName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 2) {
            menuButton("New Chat", icon: "plus.bubble", shortcut: "⌘N") {
                NotificationCenter.default.post(name: .init("GRumpNewChat"), object: nil)
            }
            menuButton("Open Full App", icon: "macwindow", shortcut: nil) {
                #if os(macOS)
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.isVisible }) {
                    window.makeKeyAndOrderFront(nil)
                }
                #endif
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Activity")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            let recent = viewModel.activityStore.entries.prefix(5)
            if recent.isEmpty {
                Text("No recent activity")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(recent), id: \.id) { entry in
                    HStack(spacing: 6) {
                        Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(entry.success ? .green : .red)
                        Text(entry.toolName)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(formatRelativeTime(entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Suggestions

    private var suggestionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            let suggestions = viewModel.suggestions
            if !suggestions.isEmpty {
                Text("Suggestions")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)

                ForEach(suggestions.prefix(3)) { suggestion in
                    Button(action: {
                        // Route suggestion into chat
                        viewModel.userInput = suggestion.prompt
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: suggestion.icon)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                            Text(suggestion.title)
                                .font(.caption)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button("Settings…") {
                NotificationCenter.default.post(name: .init("GRumpOpenSettings"), object: nil)
                #if os(macOS)
                NSApp.activate(ignoringOtherApps: true)
                #endif
            }
            .font(.caption)

            Spacer()

            Button("Quit") {
                #if os(macOS)
                NSApp.terminate(nil)
                #endif
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .padding(12)
    }

    // MARK: - Helpers

    private func menuButton(_ title: String, icon: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .frame(width: 16)
                Text(title)
                    .font(.caption)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
