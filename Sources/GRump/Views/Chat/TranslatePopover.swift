import SwiftUI

// MARK: - Translate Popover
//
// Extracted from MessageViews.swift for maintainability.
// Provides inline translation of message content.

struct TranslatePopover: View {
    let text: String
    let themeManager: ThemeManager
    @State private var translatedText = ""
    @State private var selectedLanguage: TranslationLanguage = .spanish
    @State private var isTranslating = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Image(systemName: "translate")
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("Translate")
                    .font(Typography.bodySemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
            }
            Picker("To", selection: $selectedLanguage) {
                ForEach(TranslatePopover.availableLanguages) { lang in
                    Text(lang.name).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedLanguage) { _, _ in translateText() }

            if isTranslating {
                ProgressView()
                    .scaleEffect(0.8)
            } else if !translatedText.isEmpty {
                Text(translatedText)
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .frame(minWidth: 280, maxWidth: 360)
        .onAppear { translateText() }
    }

    static let availableLanguages: [TranslationLanguage] = [
        .spanish, .french, .german, .japanese, .chineseSimplified, .korean, .portuguese
    ]

    private func translateText() {
        guard !text.isEmpty else { return }
        isTranslating = true
        Task {
            do {
                translatedText = try await TranslationService.shared.translate(text, to: selectedLanguage)
            } catch {
                translatedText = "Translation unavailable"
            }
            isTranslating = false
        }
    }
}
