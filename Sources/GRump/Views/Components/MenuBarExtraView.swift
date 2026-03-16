import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct MenuBarExtraView: View {
    @EnvironmentObject var viewModel: ChatViewModel

    private var recentConversations: [Conversation] {
        Array(viewModel.conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(5))
    }

    var body: some View {
        // Agent status
        if viewModel.isLoading {
            Label {
                VStack(alignment: .leading) {
                    Text("Agent Running")
                        .font(.headline)
                    if let step = viewModel.currentAgentStep, let max = viewModel.currentAgentStepMax, max > 1 {
                        Text("Step \(step) of \(max)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "bolt.circle.fill")
                    .foregroundColor(.orange)
            }
            .disabled(true)

            Button("Stop Agent") {
                viewModel.stopGeneration()
            }

            Divider()
        } else if viewModel.isPaused {
            Label("Agent Paused", systemImage: "pause.circle.fill")
                .foregroundColor(.yellow)
                .disabled(true)

            Button("Resume Agent") {
                viewModel.resumeAgent()
            }

            Divider()
        }

        // Quick prompt
        Button("New Chat") {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: Notification.Name("GRumpNewChat"), object: nil)
        }
        .keyboardShortcut("n", modifiers: .command)

        Divider()

        // Recent conversations
        if !recentConversations.isEmpty {
            Text("Recent")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(recentConversations) { conversation in
                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    viewModel.selectConversation(conversation)
                }) {
                    HStack {
                        Image(systemName: "bubble.left")
                            .foregroundColor(.secondary)
                        Text(conversation.title)
                            .lineLimit(1)
                        Spacer()
                        Text(relativeTime(conversation.updatedAt))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()
        }

        Button("Bring to Front") {
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("b", modifiers: .command)

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: Notification.Name("GRumpOpenSettings"), object: nil)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit G-Rump") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

#endif
