import SwiftUI

// MARK: - Accessibility Issue Model

struct AccessibilityIssue: Identifiable {
    let id = UUID()
    let file: String
    let line: Int
    let category: IssueCategory
    let message: String
    let suggestion: String
    let severity: Severity

    enum IssueCategory: String, CaseIterable {
        case missingLabel = "Missing Label"
        case missingHint = "Missing Hint"
        case touchTarget = "Touch Target"
        case contrast = "Contrast"
        case dynamicType = "Dynamic Type"
        case imageLabel = "Image Label"

        var icon: String {
            switch self {
            case .missingLabel: return "text.badge.xmark"
            case .missingHint: return "questionmark.bubble"
            case .touchTarget: return "hand.tap"
            case .contrast: return "circle.lefthalf.filled"
            case .dynamicType: return "textformat.size"
            case .imageLabel: return "photo.badge.exclamationmark"
            }
        }

        var color: Color {
            switch self {
            case .missingLabel: return .red
            case .missingHint: return .orange
            case .touchTarget: return .orange
            case .contrast: return .red
            case .dynamicType: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .imageLabel: return .red
            }
        }
    }

    enum Severity: String {
        case critical
        case warning
        case suggestion

        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            case .suggestion: return Color(red: 0.3, green: 0.6, blue: 1.0)
            }
        }
    }
}

// MARK: - Accessibility Service

@MainActor
final class AccessibilityAuditService: ObservableObject {
    @Published var issues: [AccessibilityIssue] = []
    @Published var isScanning = false
    @Published var summary: AuditSummary?

    struct AuditSummary {
        let totalFiles: Int
        let filesWithIssues: Int
        let criticalCount: Int
        let warningCount: Int
        let suggestionCount: Int
    }

    func scan(directory: String) {
        guard !directory.isEmpty else { return }
        isScanning = true
        let dir = directory
        Task.detached(priority: .userInitiated) {
            let issues = await Self.scanSwiftFiles(dir: dir)
            let filesWithIssues = Set(issues.map(\.file)).count

            let summary = AuditSummary(
                totalFiles: await Self.countSwiftFiles(dir: dir),
                filesWithIssues: filesWithIssues,
                criticalCount: issues.filter { $0.severity == .critical }.count,
                warningCount: issues.filter { $0.severity == .warning }.count,
                suggestionCount: issues.filter { $0.severity == .suggestion }.count
            )

            await MainActor.run {
                self.issues = issues
                self.summary = summary
                self.isScanning = false
            }
        }
    }

    nonisolated static func countSwiftFiles(dir: String) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return 0 }
        var count = 0
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" || name == "Tests" {
                enumerator.skipDescendants()
                continue
            }
            if path.hasSuffix(".swift") { count += 1 }
        }
        return count
    }

    nonisolated static func scanSwiftFiles(dir: String) -> [AccessibilityIssue] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return [] }
        var issues: [AccessibilityIssue] = []

        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" || name == "Tests" {
                enumerator.skipDescendants()
                continue
            }
            guard path.hasSuffix(".swift") else { continue }

            let fullPath = (dir as NSString).appendingPathComponent(path)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: "\n")
            var hasImportSwiftUI = false

            for (lineNum, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.contains("import SwiftUI") { hasImportSwiftUI = true }
                guard hasImportSwiftUI else { continue }

                // Check for Image without accessibility label
                if trimmed.contains("Image(") && !trimmed.contains("decorative:") {
                    // Look ahead a few lines for .accessibilityLabel
                    let lookAhead = lines[lineNum..<min(lineNum + 5, lines.count)].joined(separator: " ")
                    if !lookAhead.contains(".accessibilityLabel") && !lookAhead.contains(".accessibilityHidden(true)") {
                        issues.append(AccessibilityIssue(
                            file: path, line: lineNum + 1,
                            category: .imageLabel,
                            message: "Image missing accessibility label",
                            suggestion: "Add .accessibilityLabel(\"description\") or use Image(decorative:)",
                            severity: .critical
                        ))
                    }
                }

                // Check for Button without accessibility label
                if trimmed.contains("Button(action:") || (trimmed.contains("Button {") && !trimmed.contains("Button(\"")) {
                    let lookAhead = lines[lineNum..<min(lineNum + 8, lines.count)].joined(separator: " ")
                    if !lookAhead.contains(".accessibilityLabel") && !lookAhead.contains("Text(") {
                        issues.append(AccessibilityIssue(
                            file: path, line: lineNum + 1,
                            category: .missingLabel,
                            message: "Button may lack accessible label",
                            suggestion: "Add .accessibilityLabel(\"action description\") or include Text in button label",
                            severity: .warning
                        ))
                    }
                }

                // Check for small touch targets
                if trimmed.contains(".frame(width:") || trimmed.contains(".frame(height:") {
                    // Extract size values
                    if let widthMatch = trimmed.range(of: #"width:\s*(\d+)"#, options: .regularExpression) {
                        let numStr = trimmed[widthMatch]
                            .components(separatedBy: ":").last?
                            .trimmingCharacters(in: .whitespaces) ?? ""
                        if let size = Int(numStr), size < 44 {
                            issues.append(AccessibilityIssue(
                                file: path, line: lineNum + 1,
                                category: .touchTarget,
                                message: "Touch target may be too small (\(size)pt)",
                                suggestion: "Apple HIG recommends minimum 44×44pt touch targets",
                                severity: .suggestion
                            ))
                        }
                    }
                }

                // Check for hardcoded font sizes (Dynamic Type concern)
                if trimmed.contains(".font(.system(size:") && !trimmed.contains("Typography.") {
                    issues.append(AccessibilityIssue(
                        file: path, line: lineNum + 1,
                        category: .dynamicType,
                        message: "Hardcoded font size — won't scale with Dynamic Type",
                        suggestion: "Consider using .font(.body) or scaled typography tokens",
                        severity: .suggestion
                    ))
                }
            }
        }

        return issues
    }
}

// MARK: - Accessibility Audit View

struct AccessibilityAuditView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = AccessibilityAuditService()
    @State private var searchText = ""
    @State private var filterCategory: AccessibilityIssue.IssueCategory?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Accessibility Audit")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                Spacer()

                if service.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { service.scan(directory: viewModel.workingDirectory) }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                        Text("Scan")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(service.isScanning || viewModel.workingDirectory.isEmpty)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Summary bar
            if let summary = service.summary {
                HStack(spacing: Spacing.xxl) {
                    Label("\(summary.totalFiles) files", systemImage: "doc.text")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)

                    if summary.criticalCount > 0 {
                        Label("\(summary.criticalCount) critical", systemImage: "xmark.circle.fill")
                            .font(Typography.micro)
                            .foregroundColor(.red)
                    }
                    if summary.warningCount > 0 {
                        Label("\(summary.warningCount) warnings", systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.micro)
                            .foregroundColor(.orange)
                    }
                    if summary.suggestionCount > 0 {
                        Label("\(summary.suggestionCount) suggestions", systemImage: "lightbulb.fill")
                            .font(Typography.micro)
                            .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .background(themeManager.palette.bgCard)
            }

            // Category filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    categoryChip(nil, label: "All")
                    ForEach(AccessibilityIssue.IssueCategory.allCases, id: \.self) { cat in
                        categoryChip(cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            if service.isScanning && service.issues.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    ProgressView("Scanning files…")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.issues.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredIssues) { issue in
                            AccessibilityIssueRow(issue: issue)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear {
            if !viewModel.workingDirectory.isEmpty && service.issues.isEmpty {
                service.scan(directory: viewModel.workingDirectory)
            }
        }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            if !newDir.isEmpty { service.scan(directory: newDir) }
        }
    }

    private func categoryChip(_ cat: AccessibilityIssue.IssueCategory?, label: String) -> some View {
        let isSelected = filterCategory == cat
        return Button(action: { filterCategory = cat }) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(isSelected ? (cat?.color ?? themeManager.palette.effectiveAccent) : themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? (cat?.color ?? themeManager.palette.effectiveAccent).opacity(0.12) : themeManager.palette.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var filteredIssues: [AccessibilityIssue] {
        var result = service.issues
        if let cat = filterCategory {
            result = result.filter { $0.category == cat }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.file.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "figure.stand")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("Accessibility Audit")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Scan your Swift files for\naccessibility issues")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Issue Row

struct AccessibilityIssueRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let issue: AccessibilityIssue

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: issue.category.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(issue.category.color)

                Text(issue.message)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Spacer()

                Text(issue.severity.rawValue.capitalized)
                    .font(Typography.micro)
                    .foregroundColor(issue.severity.color)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 1)
                    .background(issue.severity.color.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: Spacing.lg) {
                HStack(spacing: Spacing.xs) {
                    Text(issue.file)
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text(":\(issue.line)")
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.textMuted)
                }

                Text(issue.suggestion)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgElevated.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
        )
    }
}
