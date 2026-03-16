import SwiftUI

// MARK: - Suggestion History View

/// Timeline view of past suggestions and their outcomes.
/// Shows acceptance rate per type. Accessible from the menu bar agent and MemoryPanel.
struct SuggestionHistoryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var engine: ProactiveEngine

    @State private var history: [ProactiveSuggestion] = []
    @State private var typeStats: [(type: ProactiveSuggestionType, total: Int, accepted: Int, dismissed: Int)] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if history.isEmpty && typeStats.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        if !typeStats.isEmpty {
                            statsSection
                        }
                        if !history.isEmpty {
                            timelineSection
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { loadData() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text("Suggestion History")
                .font(.headline)
                .foregroundColor(themeManager.palette.textPrimary)
            Spacer()
            Button("Refresh") { loadData() }
                .font(.caption)
                .foregroundColor(themeManager.palette.effectiveAccent)
        }
        .padding(12)
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acceptance Rates")
                .font(.caption.bold())
                .foregroundColor(themeManager.palette.textPrimary)

            ForEach(typeStats, id: \.type) { stat in
                HStack(spacing: 8) {
                    Image(systemName: stat.type.icon)
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 14)

                    Text(stat.type.displayName)
                        .font(.caption)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Mini bar chart
                    GeometryReader { geo in
                        let total = max(1, stat.total)
                        let acceptWidth = geo.size.width * CGFloat(stat.accepted) / CGFloat(total)
                        let dismissWidth = geo.size.width * CGFloat(stat.dismissed) / CGFloat(total)

                        HStack(spacing: 1) {
                            Rectangle()
                                .fill(Color.green.opacity(0.7))
                                .frame(width: acceptWidth)
                            Rectangle()
                                .fill(Color.red.opacity(0.5))
                                .frame(width: dismissWidth)
                            Spacer(minLength: 0)
                        }
                        .frame(height: 6)
                        .cornerRadius(3)
                    }
                    .frame(width: 60, height: 6)

                    Text("\(stat.accepted)/\(stat.total)")
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
        .padding(10)
        .background(themeManager.palette.bgCard.opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption.bold())
                .foregroundColor(themeManager.palette.textPrimary)

            ForEach(history) { suggestion in
                HStack(spacing: 8) {
                    // State indicator
                    Circle()
                        .fill(stateColor(suggestion.state))
                        .frame(width: 6, height: 6)

                    Image(systemName: suggestion.icon)
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(.caption)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .lineLimit(1)
                        Text(stateLabel(suggestion.state))
                            .font(.caption2)
                            .foregroundColor(stateColor(suggestion.state))
                    }

                    Spacer()

                    Text(formatRelativeTime(suggestion.createdAt))
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
        }
        .padding(10)
        .background(themeManager.palette.bgCard.opacity(0.3))
        .cornerRadius(8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
            Text("No suggestion history")
                .font(.subheadline)
                .foregroundColor(themeManager.palette.textMuted)
            Text("Suggestions will appear here\nas you interact with them.")
                .font(.caption)
                .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func loadData() {
        Task {
            let h = await engine.lifecycleManager.recentHistory(limit: 20)
            let s = await engine.lifecycleManager.typeStats()
            await MainActor.run {
                history = h
                typeStats = s
            }
        }
    }

    private func stateColor(_ state: SuggestionState) -> Color {
        switch state {
        case .accepted, .chained: return .green
        case .dismissed: return .red
        case .expired: return .gray
        case .snoozed: return .orange
        default: return .blue
        }
    }

    private func stateLabel(_ state: SuggestionState) -> String {
        switch state {
        case .accepted: return "Accepted"
        case .dismissed: return "Dismissed"
        case .expired: return "Expired"
        case .snoozed: return "Snoozed"
        case .chained(let nextId): return "Chained → \(String(nextId.prefix(8)))"
        case .pending: return "Pending"
        case .dispatched: return "Dispatched"
        case .seen: return "Seen"
        }
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
