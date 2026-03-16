import SwiftUI

struct AmbientInsightsPopover: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var ambientService: AmbientCodeAwarenessService
    var onAskGRump: (String) -> Void

    private var activeInsights: [AmbientInsight] {
        ambientService.insights.filter { !$0.dismissed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                Text("Ambient Insights")
                    .font(Typography.bodySemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                if !activeInsights.isEmpty {
                    Button(action: { ambientService.dismissAll() }) {
                        Text("Dismiss All")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.xl)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: 1)

            if activeInsights.isEmpty {
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.accentGreen)
                    Text("No insights right now")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("The agent is watching your project for issues.")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.colossal)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(activeInsights) { insight in
                            insightRow(insight)
                        }
                    }
                    .padding(Spacing.lg)
                }
                .frame(maxHeight: 400)
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: 1)

            // Footer
            HStack(spacing: Spacing.lg) {
                if ambientService.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing\u{2026}")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                } else {
                    Image(systemName: "eye")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("Watching \(ambientService.insights.count) file\(ambientService.insights.count == 1 ? "" : "s")")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.lg)
        }
        .frame(width: 380)
        .background(themeManager.palette.bgCard)
    }

    @ViewBuilder
    private func insightRow(_ insight: AmbientInsight) -> some View {
        HStack(alignment: .top, spacing: Spacing.lg) {
            Image(systemName: insight.category.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorForCategory(insight.category))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(insight.title)
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(2)

                if !insight.detail.isEmpty {
                    Text(insight.detail)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(2)
                }

                HStack(spacing: Spacing.md) {
                    if !insight.filePath.isEmpty {
                        Text(insight.filePath)
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                        if let line = insight.lineNumber {
                            Text("L\(line)")
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.textMuted)
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: Spacing.sm) {
                Button(action: {
                    let prompt = ambientService.promptForInsight(insight)
                    onAskGRump(prompt)
                }) {
                    Text("Ask")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, 4)
                        .background(themeManager.palette.effectiveAccent.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button(action: { ambientService.dismissInsight(insight.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    private func colorForCategory(_ category: AmbientInsight.Category) -> Color {
        switch category {
        case .todo: return .blue
        case .unusedImport: return .orange
        case .missingTest: return .purple
        case .largeFile: return .yellow
        case .complexity: return .red
        case .error: return .red
        case .security: return .red
        }
    }
}
