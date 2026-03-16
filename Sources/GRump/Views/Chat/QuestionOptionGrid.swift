import SwiftUI

// MARK: - Question Option Model

struct QuestionOption: Identifiable {
    let id = UUID()
    let letter: String
    let label: String
    let description: String
}

// MARK: - Parsed Question

struct ParsedQuestion {
    let questionText: String
    let options: [QuestionOption]
}

// MARK: - Question Parser (Markdown Fallback)

enum QuestionParser {

    /// Attempt to parse a markdown message that contains a question with lettered/numbered options.
    /// Returns nil if no question+options pattern is detected.
    static func parse(from markdown: String) -> ParsedQuestion? {
        // Strategy 1: Classic question + lettered options (A. / B. / 1. / 2.)
        if let classic = parseClassicQuestionOptions(markdown) {
            return classic
        }

        // Strategy 2: Numbered question list (Spec/Build mode — multiple "N. Question?" lines)
        if let numbered = parseNumberedQuestions(markdown) {
            return numbered
        }

        return nil
    }

    private static func parseClassicQuestionOptions(_ markdown: String) -> ParsedQuestion? {
        let lines = markdown.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        var questionLine: String?
        var optionStartIndex: Int?

        for (i, line) in lines.enumerated() {
            if line.contains("?") && !line.isEmpty {
                let remaining = Array(lines.dropFirst(i + 1)).filter { !$0.isEmpty }
                if remaining.count >= 2 && looksLikeOptions(remaining) {
                    questionLine = line
                    optionStartIndex = i + 1
                    break
                }
            }
        }

        guard let question = questionLine, let startIdx = optionStartIndex else { return nil }

        let optionLines = Array(lines.dropFirst(startIdx)).filter { !$0.isEmpty }
        let parsed = parseOptionLines(optionLines)

        guard parsed.count >= 2 else { return nil }

        return ParsedQuestion(questionText: question, options: parsed)
    }

    /// Detects numbered question patterns like:
    /// 1. What feature do you want to build?
    /// 2. What's the current state of the project?
    /// 3. Any specific tech stack preferences?
    private static func parseNumberedQuestions(_ markdown: String) -> ParsedQuestion? {
        let lines = markdown.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]

        // Look for sequences of numbered lines containing question marks
        let numberedQuestionPattern = #"^(\d+)[\.\)]\s+\*{0,2}(.+?\?)\*{0,2}\s*$"#
        let regex = try? NSRegularExpression(pattern: numberedQuestionPattern)

        var questions: [QuestionOption] = []

        for line in lines {
            guard let regex = regex else { continue }
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range),
               let textRange = Range(match.range(at: 2), in: line) {
                let text = String(line[textRange])
                    .replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let letter = questions.count < letters.count ? letters[questions.count] : "\(questions.count + 1)"
                questions.append(QuestionOption(letter: letter, label: text, description: ""))
            }
        }

        guard questions.count >= 2 else { return nil }

        return ParsedQuestion(questionText: "Clarifying Questions", options: Array(questions.prefix(6)))
    }

    /// Parse structured JSON from the ask_user tool call.
    static func parseFromToolCall(arguments: String) -> ParsedQuestion? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let question = json["question"] as? String,
              let optionsArray = json["options"] as? [[String: Any]] else {
            return nil
        }

        let letters = ["A", "B", "C", "D", "E", "F"]
        var options: [QuestionOption] = []

        for (i, opt) in optionsArray.prefix(4).enumerated() {
            let label = opt["label"] as? String ?? "Option \(letters[i])"
            let desc = opt["description"] as? String ?? ""
            options.append(QuestionOption(letter: letters[i], label: label, description: desc))
        }

        guard options.count >= 2 else { return nil }
        return ParsedQuestion(questionText: question, options: options)
    }

    private static func looksLikeOptions(_ lines: [String]) -> Bool {
        let patterns = [
            #"^[A-Da-d][\.\)]\s+"#,
            #"^[1-4][\.\)]\s+"#,
            #"^-\s+\*\*[A-Da-d]"#,
            #"^\*\*[A-Da-d][\.\)]"#
        ]
        var matchCount = 0
        for line in lines.prefix(4) {
            for pattern in patterns {
                if line.range(of: pattern, options: .regularExpression) != nil {
                    matchCount += 1
                    break
                }
            }
        }
        return matchCount >= 2
    }

    private static func parseOptionLines(_ lines: [String]) -> [QuestionOption] {
        let letters = ["A", "B", "C", "D"]
        var options: [QuestionOption] = []

        let optionRegex = try? NSRegularExpression(
            pattern: #"^(?:[A-Da-d1-4][\.\)]\s*\*{0,2})(.+?)(?:\*{0,2}\s*[-–—:]\s*(.+))?$"#
        )

        for (i, line) in lines.prefix(4).enumerated() {
            let cleaned = line
                .replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            if let regex = optionRegex,
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) {
                let label: String = {
                    guard match.range(at: 1).location != NSNotFound,
                          let r = Range(match.range(at: 1), in: cleaned) else { return cleaned }
                    return String(cleaned[r]).trimmingCharacters(in: .init(charactersIn: "*"))
                }()
                let desc: String = {
                    guard match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound,
                          let r = Range(match.range(at: 2), in: cleaned) else { return "" }
                    return String(cleaned[r]).trimmingCharacters(in: .init(charactersIn: "*"))
                }()
                options.append(QuestionOption(letter: letters[i], label: label, description: desc))
            } else if !cleaned.isEmpty {
                options.append(QuestionOption(letter: letters[i], label: cleaned, description: ""))
            }
        }

        return options
    }
}

// MARK: - 2x2 Question Option Grid View

struct QuestionOptionGrid: View {
    @EnvironmentObject var themeManager: ThemeManager
    let question: ParsedQuestion
    let onSelect: (QuestionOption) -> Void

    private var columns: [GridItem] {
        if question.options.count <= 2 {
            return [GridItem(.flexible(), spacing: Spacing.lg)]
        }
        return [
            GridItem(.flexible(), spacing: Spacing.lg),
            GridItem(.flexible(), spacing: Spacing.lg)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            LazyVGrid(columns: columns, spacing: Spacing.lg) {
                ForEach(question.options) { option in
                    Button(action: { onSelect(option) }) {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            // Letter badge
                            Text(option.letter)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .frame(width: 26, height: 26)
                                .background(themeManager.palette.effectiveAccent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(option.label)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)

                                if !option.description.isEmpty {
                                    Text(option.description)
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.textMuted)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(themeManager.palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(themeManager.palette.borderCrisp.opacity(0.5), lineWidth: Border.thin)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
    }
}
