import SwiftUI

// MARK: - Diff Models

struct DiffHunk: Identifiable {
    let id = UUID()
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
    var status: HunkStatus = .pending

    enum HunkStatus {
        case pending, accepted, rejected
    }
}

struct DiffLine: Identifiable, Hashable {
    let id = UUID()
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType: Hashable {
        case context
        case addition
        case deletion

        var color: Color {
            switch self {
            case .context: return Color(red: 0.5, green: 0.5, blue: 0.6)
            case .addition: return .accentGreen
            case .deletion: return .red
            }
        }

        var bgColor: Color {
            switch self {
            case .context: return .clear
            case .addition: return Color.accentGreen.opacity(0.08)
            case .deletion: return Color.red.opacity(0.08)
            }
        }

        var prefix: String {
            switch self {
            case .context: return " "
            case .addition: return "+"
            case .deletion: return "-"
            }
        }
    }
}

// MARK: - Diff Parser

struct DiffParser {
    /// Compute a unified diff between two strings.
    static func computeDiff(old: String, new: String, contextLines: Int = 3) -> [DiffHunk] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")

        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var diffLines: [(DiffLine.LineType, String, Int?, Int?)] = []

        var oi = 0, ni = 0, li = 0
        while oi < oldLines.count || ni < newLines.count {
            if li < lcs.count && oi < oldLines.count && ni < newLines.count &&
               oldLines[oi] == lcs[li] && newLines[ni] == lcs[li] {
                diffLines.append((.context, oldLines[oi], oi + 1, ni + 1))
                oi += 1; ni += 1; li += 1
            } else if oi < oldLines.count && (li >= lcs.count || oldLines[oi] != lcs[li]) {
                diffLines.append((.deletion, oldLines[oi], oi + 1, nil))
                oi += 1
            } else if ni < newLines.count && (li >= lcs.count || newLines[ni] != lcs[li]) {
                diffLines.append((.addition, newLines[ni], nil, ni + 1))
                ni += 1
            }
        }

        // Group into hunks with context
        return groupIntoHunks(diffLines, contextLines: contextLines)
    }

    /// Parse a unified diff string into hunks.
    static func parseUnifiedDiff(_ diff: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentLines: [DiffLine] = []
        var oldStart = 0, oldCount = 0, newStart = 0, newCount = 0
        var oldLine = 0, newLine = 0

        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("@@") {
                // Save previous hunk
                if !currentLines.isEmpty {
                    hunks.append(DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: currentLines))
                    currentLines = []
                }
                // Parse hunk header: @@ -old,count +new,count @@
                let parts = line.components(separatedBy: " ")
                if parts.count >= 3 {
                    let oldPart = parts[1].dropFirst() // remove -
                    let newPart = parts[2].dropFirst() // remove +
                    let oldParts = oldPart.components(separatedBy: ",")
                    let newParts = newPart.components(separatedBy: ",")
                    oldStart = Int(oldParts[0]) ?? 0
                    oldCount = oldParts.count > 1 ? Int(oldParts[1]) ?? 0 : 1
                    newStart = Int(newParts[0]) ?? 0
                    newCount = newParts.count > 1 ? Int(newParts[1]) ?? 0 : 1
                    oldLine = oldStart
                    newLine = newStart
                }
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                currentLines.append(DiffLine(type: .addition, content: String(line.dropFirst()), oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                currentLines.append(DiffLine(type: .deletion, content: String(line.dropFirst()), oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            } else if !line.hasPrefix("---") && !line.hasPrefix("+++") && !line.hasPrefix("diff ") && !line.hasPrefix("index ") {
                let content = line.hasPrefix(" ") ? String(line.dropFirst()) : line
                currentLines.append(DiffLine(type: .context, content: content, oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            }
        }

        if !currentLines.isEmpty {
            hunks.append(DiffHunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, lines: currentLines))
        }

        return hunks
    }

    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        // Use space-optimized approach for large files
        if m > 5000 || n > 5000 {
            // Fall back to simple line-by-line comparison for very large files
            return Array(Set(a).intersection(Set(b)))
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }

        return result.reversed()
    }

    private static func groupIntoHunks(_ lines: [(DiffLine.LineType, String, Int?, Int?)], contextLines: Int) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHunkLines: [DiffLine] = []
        var hunkOldStart = 0, hunkNewStart = 0
        var contextCount = 0
        var inHunk = false

        for (i, (type, content, oldNum, newNum)) in lines.enumerated() {
            if type != .context {
                if !inHunk {
                    // Start new hunk, include preceding context
                    inHunk = true
                    hunkOldStart = (oldNum ?? 1) - min(contextLines, currentHunkLines.count)
                    hunkNewStart = (newNum ?? 1) - min(contextLines, currentHunkLines.count)
                    let precedingContext = Array(currentHunkLines.suffix(contextLines))
                    currentHunkLines = precedingContext
                }
                currentHunkLines.append(DiffLine(type: type, content: content, oldLineNumber: oldNum, newLineNumber: newNum))
                contextCount = 0
            } else {
                if inHunk {
                    contextCount += 1
                    currentHunkLines.append(DiffLine(type: .context, content: content, oldLineNumber: oldNum, newLineNumber: newNum))

                    if contextCount >= contextLines * 2 || i == lines.count - 1 {
                        // End hunk
                        let oldCount = currentHunkLines.filter { $0.type != .addition }.count
                        let newCount = currentHunkLines.filter { $0.type != .deletion }.count
                        hunks.append(DiffHunk(oldStart: max(1, hunkOldStart), oldCount: oldCount, newStart: max(1, hunkNewStart), newCount: newCount, lines: currentHunkLines))
                        currentHunkLines = []
                        inHunk = false
                        contextCount = 0
                    }
                } else {
                    currentHunkLines = [DiffLine(type: .context, content: content, oldLineNumber: oldNum, newLineNumber: newNum)]
                }
            }
        }

        if inHunk && !currentHunkLines.isEmpty {
            let oldCount = currentHunkLines.filter { $0.type != .addition }.count
            let newCount = currentHunkLines.filter { $0.type != .deletion }.count
            hunks.append(DiffHunk(oldStart: max(1, hunkOldStart), oldCount: oldCount, newStart: max(1, hunkNewStart), newCount: newCount, lines: currentHunkLines))
        }

        return hunks
    }
}

// MARK: - Diff View

struct DiffView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let fileName: String
    @Binding var hunks: [DiffHunk]
    var onAcceptAll: (() -> Void)?
    var onRejectAll: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text(fileName)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                let addCount = hunks.flatMap(\.lines).filter { $0.type == .addition }.count
                let delCount = hunks.flatMap(\.lines).filter { $0.type == .deletion }.count

                if addCount > 0 {
                    Text("+\(addCount)")
                        .font(Typography.codeMicro)
                        .foregroundColor(.accentGreen)
                }
                if delCount > 0 {
                    Text("-\(delCount)")
                        .font(Typography.codeMicro)
                        .foregroundColor(.red)
                }

                Button(action: { onAcceptAll?() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Accept All")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(.accentGreen)
                }
                .buttonStyle(ScaleButtonStyle())

                Button(action: { onRejectAll?() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Reject")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Diff content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(Array(hunks.enumerated()), id: \.offset) { index, hunk in
                        DiffHunkView(
                            hunk: hunk,
                            onAccept: { hunks[index].status = .accepted },
                            onReject: { hunks[index].status = .rejected }
                        )
                    }
                }
                .padding(Spacing.md)
            }
        }
        .background(themeManager.palette.bgElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }
}

// MARK: - Diff Hunk View

struct DiffHunkView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let hunk: DiffHunk
    var onAccept: () -> Void
    var onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hunk header
            HStack(spacing: Spacing.md) {
                Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@")
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.effectiveAccent.opacity(0.7))

                Spacer()

                if hunk.status == .pending {
                    Button(action: onAccept) {
                        Image(systemName: "checkmark.circle")
                            .font(Typography.captionSmall)
                            .foregroundColor(.accentGreen)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Accept hunk")

                    Button(action: onReject) {
                        Image(systemName: "xmark.circle")
                            .font(Typography.captionSmall)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Reject hunk")
                } else {
                    Text(hunk.status == .accepted ? "Accepted" : "Rejected")
                        .font(Typography.micro)
                        .foregroundColor(hunk.status == .accepted ? .accentGreen : .red)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(themeManager.palette.effectiveAccent.opacity(0.05))

            // Lines
            ForEach(hunk.lines) { line in
                HStack(spacing: 0) {
                    // Line numbers
                    HStack(spacing: 0) {
                        Text(line.oldLineNumber.map { "\($0)" } ?? "")
                            .frame(width: 32, alignment: .trailing)
                        Text(line.newLineNumber.map { "\($0)" } ?? "")
                            .frame(width: 32, alignment: .trailing)
                    }
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                    .padding(.trailing, Spacing.sm)

                    // Prefix
                    Text(line.type.prefix)
                        .font(Typography.codeSmall)
                        .foregroundColor(line.type.color)
                        .frame(width: 12)

                    // Content
                    Text(line.content)
                        .font(Typography.codeSmall)
                        .foregroundColor(line.type == .context ? themeManager.palette.textSecondary : themeManager.palette.textPrimary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 1)
                .background(line.type.bgColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
        .opacity(hunk.status == .rejected ? 0.4 : 1.0)
    }
}
