import SwiftUI

/// Spec mode modal: optional Q&A before sending. User can answer, skip, or cancel.
struct SpecQuestionsModal: View {
    let userMessage: String
    let onContinue: (String) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var answers = ""

    private let placeholderQuestions = """
    Target platform? (e.g. macOS, iOS, web)
    Key requirements or constraints?
    Any specific libraries or patterns?
    """

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Text("Spec mode: add clarifying context (optional)")
                    .font(Typography.heading3)
                    .foregroundColor(.textPrimary)

                if !userMessage.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Your request")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                        Text(userMessage)
                            .font(Typography.bodySmall)
                            .foregroundColor(.textSecondary)
                            .lineLimit(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Spacing.lg)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Clarifying context (optional)")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.textMuted)
                    TextEditor(text: $answers)
                        .font(Typography.bodySmall)
                        .foregroundColor(.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 100, maxHeight: 180)
                        .padding(Spacing.lg)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                        .overlay(
                            Group {
                                if answers.isEmpty {
                                    Text(placeholderQuestions)
                                        .font(Typography.bodySmall)
                                        .foregroundColor(.textMuted)
                                        .padding(Spacing.xl)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                        .allowsHitTesting(false)
                                }
                            }
                        )
                }

                HStack(spacing: Spacing.lg) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundColor(.textMuted)

                    Button("Continue") {
                        onContinue(answers)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.palette.effectiveAccent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Spacing.huge)
            .frame(minWidth: 400, minHeight: 320)
            .background(themeManager.palette.bgDark)
            .navigationTitle("Spec Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}
