import SwiftUI

/// A view that renders markdown text with formatting support and progressive rendering.
/// Handles: **bold**, *italic*, `inline code`, ~~strikethrough~~, [links](url),
/// fenced code blocks, headers, lists, blockquotes, tables, and horizontal rules.
struct MarkdownTextView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let text: String
    let onCodeBlockTap: ((String) -> Void)?
    
    /// Progressive rendering state
    @State private var renderedBlocks: [Block] = []
    @State private var pendingText: String = ""
    @State private var isStreaming: Bool = false
    @State private var renderTask: Task<Void, Never>?
    @State private var lastRenderedLength: Int = 0
    
    /// Incremental parsing state — tracks how far we've parsed to avoid re-parsing the whole text
    @State private var lastParsedOffset: Int = 0
    @State private var stableBlockCount: Int = 0
    
    /// Cached parsed blocks; debounced to avoid parse-per-keystroke during streaming.
    @State private var cachedBlocks: [Block] = []
    @State private var debounceTask: Task<Void, Never>?
    
    /// Animation configuration
    @State private var animationDuration: Double = 0.3
    @State private var chunkSize: Int = 100
    
    private var debounceNs: UInt64 {
        let ms = UserDefaults.standard.object(forKey: "StreamDebounceMs") as? Int ?? 80
        return UInt64(max(0, ms)) * 1_000_000
    }
    
    init(text: String, themeManager: ThemeManager? = nil, onCodeBlockTap: ((String) -> Void)? = nil) {
        self.text = text
        self.onCodeBlockTap = onCodeBlockTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .padding(.top, topSpacing(for: block, previous: index > 0 ? renderedBlocks[index - 1] : nil))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: animationDuration), value: renderedBlocks.count)
            }
            
            // Show streaming indicator for incomplete content
            if isStreaming && !pendingText.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(themeManager.palette.effectiveAccent.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .scaleEffect(dotIndex == index ? 1.25 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: dotIndex)
                    }
                }
                .padding(.top, Spacing.sm)
            }
        }
        .onAppear {
            startProgressiveRendering()
        }
        .onChange(of: text) { _, newValue in
            detectStreamingChange(newValue)
        }
        .onDisappear {
            renderTask?.cancel()
            debounceTask?.cancel()
        }
    }
    
    @State private var dotIndex: Int = 0
    @State private var timer: Timer?

    // MARK: - Block Types

    private enum Block {
        case codeBlock(language: String, code: String)
        case paragraph(String)
        case header(Int, String)
        case listItem(indent: Int, ordered: Bool, number: Int, content: String)
        case blockquote(String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
    }

    private func parseOnBackground(_ input: String) {
        debounceTask?.cancel()
        debounceTask = Task.detached(priority: .userInitiated) {
            let blocks = Self.parseBlocksStatic(input)
            guard !Task.isCancelled else { return }
            let count = input.count
            await MainActor.run {
                renderedBlocks = blocks
                cachedBlocks = blocks
                lastParsedOffset = count
                stableBlockCount = blocks.count
            }
        }
    }

    // MARK: - Context-Aware Spacing

    private func topSpacing(for block: Block, previous: Block?) -> CGFloat {
        guard previous != nil else { return 0 }
        switch block {
        case .header(1, _): return 24
        case .header(2, _): return 20
        case .header(3, _): return 16
        case .header(_, _): return 14
        case .paragraph: return 12
        case .listItem: return 4
        case .codeBlock: return 16
        case .blockquote: return 12
        case .horizontalRule: return 16
        case .table: return 16
        }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .paragraph(let content):
            buildInlineText(content)
                .font(Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor))
                .foregroundColor(themeManager.palette.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(3)

        case .header(let level, let content):
            buildInlineText(content)
                .font(headerFont(level))
                .foregroundColor(themeManager.palette.textPrimary)

        case .listItem(let indent, let ordered, let number, let content):
            let bodyFont = Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor)
            HStack(alignment: .top, spacing: Spacing.md) {
                Text(ordered ? "\(number)." : "•")
                    .font(bodyFont)
                    .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                    .frame(width: ordered ? 20 : 12, alignment: ordered ? .trailing : .center)
                buildInlineText(content)
                    .font(bodyFont)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineSpacing(2)
            }
            .padding(.leading, CGFloat(indent) * 20)

        case .blockquote(let content):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeManager.palette.effectiveAccent.opacity(0.4))
                    .frame(width: 3)
                buildInlineText(content)
                    .font(Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor))
                    .foregroundColor(themeManager.palette.textSecondary)
                    .italic()
                    .lineSpacing(2)
                    .padding(.leading, Spacing.xxl)
            }

        case .horizontalRule:
            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, Spacing.sm)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
        }
    }

    // MARK: - Table Rendering

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    buildInlineText(headers[i].trimmingCharacters(in: .whitespaces))
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(themeManager.palette.bgElevated)

            Divider()

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 0) {
                    ForEach(rows[rowIdx].indices, id: \.self) { colIdx in
                        buildInlineText(rows[rowIdx][colIdx].trimmingCharacters(in: .whitespaces))
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rowIdx < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    // MARK: - Block Parsing

    /// Static version for background thread use (no self capture needed)
    nonisolated private static func parseBlocksStatic(_ text: String) -> [Block] {
        parseBlocksImpl(text)
    }

    private func parseBlocks(_ text: String) -> [Block] {
        Self.parseBlocksImpl(text)
    }

    nonisolated private static func parseBlocksImpl(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // Skip closing ```
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule: ---, ***, ___
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.count >= 3 && (
                trimmedLine.allSatisfy({ $0 == "-" }) ||
                trimmedLine.allSatisfy({ $0 == "*" }) ||
                trimmedLine.allSatisfy({ $0 == "_" })
            ) {
                blocks.append(.horizontalRule)
                i += 1; continue
            }

            // Headers
            if line.hasPrefix("### ") {
                blocks.append(.header(3, String(line.dropFirst(4))))
                i += 1; continue
            }
            if line.hasPrefix("## ") {
                blocks.append(.header(2, String(line.dropFirst(3))))
                i += 1; continue
            }
            if line.hasPrefix("# ") {
                blocks.append(.header(1, String(line.dropFirst(2))))
                i += 1; continue
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    let content = lines[i].hasPrefix("> ") ? String(lines[i].dropFirst(2)) : ""
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Table detection: line with pipes
            if line.contains("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                // Check if next line is a separator row (contains |---| pattern)
                if nextLine.contains("|") && nextLine.contains("-") {
                    let headerCells = parsePipeLine(line)
                    if headerCells.count > 1 {
                        i += 2 // Skip header + separator
                        var dataRows: [[String]] = []
                        while i < lines.count && lines[i].contains("|") {
                            let cells = parsePipeLine(lines[i])
                            if !cells.isEmpty {
                                dataRows.append(cells)
                            }
                            i += 1
                        }
                        blocks.append(.table(headers: headerCells, rows: dataRows))
                        continue
                    }
                }
            }

            // List items (unordered)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                blocks.append(.listItem(indent: 0, ordered: false, number: 0, content: content))
                i += 1; continue
            }

            // Indented list items
            if let indentMatch = line.range(of: #"^(\s+)[-*]\s"#, options: .regularExpression) {
                let indentStr = line[indentMatch].filter({ $0 == " " })
                let indent = indentStr.count / 2
                let content = String(line[indentMatch.upperBound...])
                blocks.append(.listItem(indent: indent, ordered: false, number: 0, content: content))
                i += 1; continue
            }

            // Numbered list
            if let range = line.range(of: #"^(\s*)(\d+)\.\s"#, options: .regularExpression) {
                let prefix = String(line[range])
                let indent = prefix.prefix(while: { $0 == " " }).count / 2
                let numberStr = prefix.trimmingCharacters(in: .whitespaces).dropLast() // remove trailing dot+space chars
                let number = Int(numberStr.filter(\.isNumber)) ?? 1
                blocks.append(.listItem(indent: indent, ordered: true, number: number, content: String(line[range.upperBound...])))
                i += 1; continue
            }

            // Empty line
            if trimmedLine.isEmpty {
                i += 1; continue
            }

            // Paragraph: merge consecutive non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                // Stop merging at special lines
                if nextTrimmed.isEmpty || nextLine.hasPrefix("```") || nextLine.hasPrefix("#") ||
                   nextLine.hasPrefix("- ") || nextLine.hasPrefix("* ") || nextLine.hasPrefix("> ") ||
                   (nextTrimmed.count >= 3 && (nextTrimmed.allSatisfy({ $0 == "-" }) || nextTrimmed.allSatisfy({ $0 == "*" }) || nextTrimmed.allSatisfy({ $0 == "_" }))) ||
                   nextLine.range(of: #"^\s*\d+\.\s"#, options: .regularExpression) != nil ||
                   nextLine.range(of: #"^\s+[-*]\s"#, options: .regularExpression) != nil ||
                   (nextLine.contains("|") && i + 1 < lines.count && lines[i + 1].contains("|") && lines[i + 1].contains("-")) {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    nonisolated private static func parsePipeLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.hasPrefix("|") ? String(trimmed.dropFirst()) : trimmed
        let end = stripped.hasSuffix("|") ? String(stripped.dropLast()) : stripped
        return end.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Inline Formatting

    private func buildInlineText(_ text: String) -> Text {
        let attrStr = buildAttributedString(text)
        return Text(attrStr)
    }

    private func buildAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Bold + Italic: ***text***
            if remaining.hasPrefix("***"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 3)...].range(of: "***") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 3)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Bold: **text**
            if remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "**") {
                let boldContent = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(boldContent))
                result[start..<result.endIndex].inlinePresentationIntent = .stronglyEmphasized
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "~~") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].strikethroughStyle = .single
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Inline code: `text`
            if remaining.hasPrefix("`"),
               let endIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "`") {
                let codeContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                let start = result.endIndex
                result.append(AttributedString(codeContent))
                result[start..<result.endIndex].font = .system(.body, design: .monospaced)
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Link: [text](url) — tappable via .link
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]"),
               remaining.index(after: closeBracket) < remaining.endIndex,
               remaining[remaining.index(after: closeBracket)] == "(",
               let closeParen = remaining[remaining.index(after: closeBracket)...].firstIndex(of: ")") {
                let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                let urlStart = remaining.index(after: remaining.index(after: closeBracket))
                let urlString = String(remaining[urlStart..<closeParen])
                let start = result.endIndex
                result.append(AttributedString(linkText))
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                result[start..<result.endIndex].underlineStyle = .single
                if let url = URL(string: urlString) {
                    result[start..<result.endIndex].link = url
                }
                remaining = remaining[remaining.index(after: closeParen)...]
                continue
            }

            // Italic: *text*
            if remaining.hasPrefix("*"),
               let endIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "*") {
                let italicContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                let start = result.endIndex
                result.append(AttributedString(italicContent))
                result[start..<result.endIndex].inlinePresentationIntent = .emphasized
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Regular character
            let char = remaining[remaining.startIndex]
            result.append(AttributedString(String(char)))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }
    
    // MARK: - Progressive Rendering
    
    private func startProgressiveRendering() {
        renderTask?.cancel()
        renderTask = Task {
            await renderProgressively()
        }
    }
    
    private func detectStreamingChange(_ newText: String) {
        let isIncreasing = newText.count > lastRenderedLength
        
        if !isIncreasing {
            // Text shrunk (edit/undo) — trim blocks and full re-parse
            isStreaming = false
            lastParsedOffset = 0
            stableBlockCount = 0
            parseOnBackground(newText)
            lastRenderedLength = newText.count
            return
        }
        
        let delta = newText.count - lastRenderedLength
        lastRenderedLength = newText.count
        
        if delta > 0 {
            isStreaming = true
            // Incremental: only parse from the last stable block boundary
            incrementalParse(newText)
        }
    }
    
    /// Incremental append-only parse: re-parses only from the last "stable" block boundary.
    /// During streaming, the last block is often incomplete (e.g., a paragraph still being typed).
    /// We keep all blocks except the last one as stable, and only re-parse from there.
    private func incrementalParse(_ fullText: String) {
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            // Find the offset where stable blocks end
            let currentBlocks = await MainActor.run { renderedBlocks }
            let stableCount = max(0, currentBlocks.count - 1) // Last block may be incomplete
            
            // Compute character offset of stable blocks
            var stableOffset = 0
            for i in 0..<stableCount {
                stableOffset += Self.blockLengthStatic(currentBlocks[i])
            }
            
            // Parse only the tail portion (from stable offset onward)
            let tailStart = fullText.index(fullText.startIndex, offsetBy: min(stableOffset, fullText.count))
            let tailText = String(fullText[tailStart...])
            let tailBlocks = Self.parseBlocksStatic(tailText)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Replace blocks from stableCount onward with newly parsed tail blocks
                var merged = Array(currentBlocks.prefix(stableCount))
                merged.append(contentsOf: tailBlocks)
                renderedBlocks = merged
                cachedBlocks = merged
                pendingText = ""
            }
        }
    }
    
    @MainActor
    private func renderProgressively() async {
        let fullText = text
        
        // For initial render, parse on background thread
        let blocks = await Task.detached(priority: .userInitiated) {
            Self.parseBlocksStatic(fullText)
        }.value
        
        guard !Task.isCancelled else { return }
        
        renderedBlocks = blocks
        cachedBlocks = blocks
        lastParsedOffset = fullText.count
        stableBlockCount = blocks.count
        isStreaming = false
        pendingText = ""
    }
    
    private func blockLength(_ block: Block) -> Int {
        Self.blockLengthStatic(block)
    }

    nonisolated private static func blockLengthStatic(_ block: Block) -> Int {
        switch block {
        case .codeBlock(_, let code):
            return code.count + 6 // ```\n...\n```
        case .paragraph(let content):
            return content.count
        case .header(_, let content):
            return content.count + 2 // #\n
        case .listItem(_, _, _, let content):
            return content.count + 2 // •\n
        case .blockquote(let content):
            return content.count + 2 // >\n
        case .horizontalRule:
            return 3 // ---
        case .table(let headers, let rows):
            let headerLength = headers.joined().count
            let rowLength = rows.flatMap { $0 }.joined().count
            return headerLength + rowLength
        }
    }
    

    private func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return Typography.heading1
        case 2: return Typography.heading2
        case 3: return Typography.heading3
        default: return Typography.bodyLarge
        }
    }
}
