import SwiftUI

// MARK: - Suggestion Banner View

/// Subtle notification banner that appears at top of the main app and QuickChatPopover.
/// Slides in from top with spring animation, auto-dismisses after configurable seconds.
/// Three actions per suggestion: Accept, Snooze, Dismiss.
struct SuggestionBannerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var engine: ProactiveEngine

    @AppStorage("SuggestionBannerAutoDismiss") private var autoDismissSeconds: Double = 8
    @State private var expandedView = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if let top = engine.pendingSuggestions.first {
                bannerCard(suggestion: top)
                    .transition(.move(edge: .top).combined(with: .opacity))

                // Grouped indicator for additional suggestions
                if engine.pendingSuggestions.count > 1 {
                    groupedIndicator
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: engine.pendingSuggestions.count)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Banner Card

    private func bannerCard(suggestion: ProactiveSuggestion) -> some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: suggestion.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(urgencyColor(suggestion.urgency))
                .frame(width: 28, height: 28)
                .background(urgencyColor(suggestion.urgency).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.caption.bold())
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Text(suggestion.detail)
                    .font(.caption2)
                    .foregroundColor(themeManager.palette.textMuted)
                    .lineLimit(2)
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                // Accept
                Button(action: {
                    dismissTask?.cancel()
                    engine.accept(suggestion)
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Accept")

                // Snooze
                Button(action: {
                    dismissTask?.cancel()
                    engine.snooze(suggestion)
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
                .help("Snooze (30 min)")

                // Dismiss
                Button(action: {
                    dismissTask?.cancel()
                    engine.dismiss(suggestion)
                }) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(themeManager.palette.bgCard)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(urgencyColor(suggestion.urgency).opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            startAutoDismiss(suggestion: suggestion)
        }
        .onDisappear {
            dismissTask?.cancel()
        }
    }

    // MARK: - Grouped Indicator

    private var groupedIndicator: some View {
        VStack(spacing: 4) {
            Button(action: { expandedView.toggle() }) {
                HStack(spacing: 4) {
                    Text("+\(engine.pendingSuggestions.count - 1) more")
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                    Image(systemName: expandedView ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(themeManager.palette.bgCard.opacity(0.5))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if expandedView {
                ForEach(engine.pendingSuggestions.dropFirst().prefix(3)) { suggestion in
                    bannerCard(suggestion: suggestion)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Auto-Dismiss

    private func startAutoDismiss(suggestion: ProactiveSuggestion) {
        dismissTask?.cancel()
        guard autoDismissSeconds > 0 else { return }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoDismissSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            engine.dismiss(suggestion)
        }
    }

    // MARK: - Urgency Color

    private func urgencyColor(_ urgency: UrgencyLevel) -> Color {
        switch urgency.tier {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }
}
