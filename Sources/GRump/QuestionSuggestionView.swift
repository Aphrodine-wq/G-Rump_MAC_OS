import SwiftUI

struct QuestionSuggestionView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let questions: [String]
    let onSelect: (String) -> Void
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Suggested follow-ups")
                    .font(Typography.captionSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(questions, id: \.self) { question in
                        Button(action: { onSelect(question) }) {
                            Text(question)
                                .font(Typography.captionSmallMedium)
                                .foregroundColor(themeManager.palette.textPrimary)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .background(themeManager.palette.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                        .stroke(themeManager.palette.borderSubtle, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.md)
        .opacity(isVisible ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                isVisible = true
            }
        }
    }
}

#if swift(>=5.9) && canImport(SwiftUI)
@available(macOS 14.0, iOS 17.0, *)
private struct QuestionSuggestionPreview: PreviewProvider {
    static var previews: some View {
        QuestionSuggestionView(
            questions: [
                "Can you explain that in more detail?",
                "How do I implement this?",
                "What are the alternatives?",
                "Show me an example"
            ],
            onSelect: { _ in },
            onDismiss: { }
        )
        .environmentObject(ThemeManager())
    }
}
#endif
