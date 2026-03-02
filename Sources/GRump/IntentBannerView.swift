import SwiftUI

// MARK: - Intent Banner View
//
// Shown at the top of the chat when an active intent exists.
// Displays the goal, progress bar, and quick actions.

struct IntentBannerView: View {
    let intent: UserIntent
    let onPause: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            Image(systemName: intent.status.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(themeManager.palette.effectiveAccent)

            // Goal and progress
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(intent.goal)
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                if !intent.milestones.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(themeManager.palette.bgInput)
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(themeManager.palette.effectiveAccent)
                                    .frame(width: geo.size.width * intent.progress, height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text(intent.progressSummary)
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                } else {
                    Text("Session \(intent.sessionCount) — last active \(intent.timeSinceLastSession)")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }

            Spacer()

            // Actions
            Button(action: onPause) {
                Image(systemName: "pause.circle")
                    .font(.system(size: 14))
                    .foregroundColor(themeManager.palette.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Pause this intent")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Dismiss banner")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.effectiveAccent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.effectiveAccent.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active intent: \(intent.goal). \(intent.progressSummary)")
    }
}
