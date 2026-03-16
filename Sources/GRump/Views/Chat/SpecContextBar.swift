import SwiftUI

/// Inline expandable section above the chat input for Spec mode context.
/// Replaces the old SpecQuestionsModal sheet.
struct SpecContextBar: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var isExpanded: Bool
    let userMessage: String
    let onContinue: (String) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @State private var platform: String = ""
    @State private var constraints: String = ""
    @State private var libraries: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible when expanded
            HStack(spacing: Spacing.lg) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text("Spec Mode")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("— add context before sending")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)

                Spacer()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onCancel()
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Cancel")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Context fields
            VStack(alignment: .leading, spacing: Spacing.lg) {
                specField(
                    label: "Platform",
                    placeholder: "macOS, iOS, web, CLI…",
                    text: $platform
                )

                specField(
                    label: "Constraints",
                    placeholder: "Performance, compatibility, no dependencies…",
                    text: $constraints
                )

                specField(
                    label: "Libraries / Patterns",
                    placeholder: "SwiftUI, async/await, MVVM…",
                    text: $libraries
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Action buttons
            HStack(spacing: Spacing.lg) {
                Spacer()

                Button("Skip") {
                    onSkip()
                }
                .font(Typography.captionSmallMedium)
                .foregroundColor(themeManager.palette.textMuted)
                .buttonStyle(ScaleButtonStyle())

                Button(action: {
                    let context = buildContext()
                    onContinue(context)
                }) {
                    HStack(spacing: Spacing.sm) {
                        Text("Continue")
                            .font(Typography.captionSmallSemibold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(themeManager.palette.effectiveAccent.opacity(0.3), lineWidth: Border.thin)
        )
        .padding(.horizontal, Spacing.xxxl)
        .padding(.bottom, Spacing.md)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }

    private func specField(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted)
                .textCase(.uppercase)

            TextField(placeholder, text: text)
                .font(Typography.bodySmall)
                .foregroundColor(themeManager.palette.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func buildContext() -> String {
        var parts: [String] = []
        if !platform.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("Platform: \(platform.trimmingCharacters(in: .whitespaces))")
        }
        if !constraints.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("Constraints: \(constraints.trimmingCharacters(in: .whitespaces))")
        }
        if !libraries.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append("Libraries/Patterns: \(libraries.trimmingCharacters(in: .whitespaces))")
        }
        return parts.joined(separator: "\n")
    }
}
