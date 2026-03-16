import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Parallel Agents Panel
//
// Shown inline in the chat when agentMode == .parallel.
// Displays each sub-agent as a collapsible card with status badge,
// model label, task type icon, and live streaming text.

struct ParallelAgentsPanelView: View {
    let agents: [ParallelAgentState]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.brandPurple)
                Text("Parallel Agents")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.brandPurple)
                Spacer()
                Text("\(completedCount)/\(agents.count) done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.brandPurple)
                        .frame(width: geo.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 14)

            // Agent cards
            ForEach(agents) { agent in
                AgentCardView(agent: agent)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.bgCard.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.brandPurple.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var completedCount: Int {
        agents.filter { $0.status == .completed || $0.status == .failed }.count
    }

    private var progress: Double {
        guard !agents.isEmpty else { return 0 }
        return Double(completedCount) / Double(agents.count)
    }
}

// MARK: - Individual Agent Card

struct AgentCardView: View {
    let agent: ParallelAgentState
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header — always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    // Status indicator
                    statusIcon
                        .frame(width: 18, height: 18)

                    // Task type icon
                    Image(systemName: agent.taskType.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 14)

                    // Agent label
                    Text("Agent \(agent.agentIndex)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    // Task type badge
                    Text(agent.taskType.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())

                    // Model badge
                    Text(agent.modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.brandPurpleLight)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.brandPurple.opacity(0.08))
                        .clipShape(Capsule())
                        .lineLimit(1)

                    Spacer()

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Expandable content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                // Task description
                Text(agent.taskDescription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .lineLimit(2)

                // Streaming / result text
                if !agent.streamingText.isEmpty {
                    ScrollView {
                        Text(agent.streamingText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                } else if agent.status == .pending {
                    Text("Waiting for dependencies…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                        .italic()
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                } else if agent.status == .running {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text("Running…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(cardBorder, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch agent.status {
        case .pending:
            Image(systemName: "circle.dotted")
                .font(.system(size: 14))
                .foregroundColor(.secondary.opacity(0.5))
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .tint(.brandPurple)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.red)
        }
    }

    private var cardBackground: Color {
        switch agent.status {
        case .completed: return Color.green.opacity(0.04)
        case .failed:    return Color.red.opacity(0.04)
        case .running:   return Color.brandPurple.opacity(0.04)
        case .pending:   return Color.bgCard.opacity(0.3)
        }
    }

    private var cardBorder: Color {
        switch agent.status {
        case .completed: return Color.green.opacity(0.2)
        case .failed:    return Color.red.opacity(0.2)
        case .running:   return Color.brandPurple.opacity(0.2)
        case .pending:   return Color.secondary.opacity(0.1)
        }
    }
}
