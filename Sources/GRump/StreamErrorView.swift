import SwiftUI

/// Graceful error display for streaming failures.
/// Preserves partial responses, shows inline retry button,
/// and provides context about what went wrong.
struct StreamErrorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let error: String
    let partialContent: String?
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Partial content (preserved)
            if let partial = partialContent, !partial.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.md) {
                        FrownyFaceLogo(size: 24, mood: .error)
                            .frame(width: 24, height: 24)

                        Text("Partial response (stream interrupted)")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textMuted)

                        Spacer()
                    }

                    MarkdownTextView(text: partial, onCodeBlockTap: nil)
                        .textSelection(.enabled)
                        .padding(.leading, 36) // Align with content past avatar
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.md)
            }

            // Error card
            HStack(alignment: .top, spacing: Spacing.xxl) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Stream interrupted")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)

                    // Collapsible error details
                    Button(action: { withAnimation(reduceMotion ? .none : Anim.spring) { isExpanded.toggle() } }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(isExpanded ? "Hide details" : "Show details")
                                .font(Typography.micro)
                        }
                        .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        Text(error)
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.textSecondary)
                            .padding(Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(themeManager.palette.bgElevated.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                            .textSelection(.enabled)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Action buttons
                    HStack(spacing: Spacing.xl) {
                        Button(action: onRetry) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Retry")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xxl)
                            .padding(.vertical, Spacing.md)
                            .background(themeManager.palette.effectiveAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button(action: onDismiss) {
                            Text("Dismiss")
                                .font(Typography.captionSmallMedium)
                                .foregroundColor(themeManager.palette.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, Spacing.sm)
                }

                Spacer()
            }
            .padding(Spacing.xxl)
            .background(
                RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                    .fill(Color.orange.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: Border.thin)
            )
            .padding(.horizontal, Spacing.huge)
        }
        .transition(reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .bottom)),
                removal: .opacity
            )
        )
        .onAppear {
            #if os(macOS)
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: "Stream interrupted: \(error)"]
            )
            #endif
        }
    }
}
