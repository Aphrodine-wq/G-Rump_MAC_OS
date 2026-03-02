import SwiftUI

// MARK: - Test Models

struct TestTarget: Identifiable {
    let id: String
    let name: String
    var classes: [TestClass]
    var isExpanded: Bool = true
}

struct TestClass: Identifiable {
    let id: String
    let name: String
    var methods: [TestMethod]
    var isExpanded: Bool = false

    var passCount: Int { methods.filter { $0.status == .passed }.count }
    var failCount: Int { methods.filter { $0.status == .failed }.count }
    var totalCount: Int { methods.count }
}

struct TestMethod: Identifiable {
    let id: String
    let name: String
    var status: TestStatus = .notRun
    var duration: TimeInterval?
    var failureMessage: String?

    enum TestStatus {
        case notRun, running, passed, failed, skipped

        var icon: String {
            switch self {
            case .notRun: return "circle"
            case .running: return "hourglass"
            case .passed: return "checkmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            case .skipped: return "forward.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .notRun: return Color(red: 0.5, green: 0.5, blue: 0.6)
            case .running: return .orange
            case .passed: return .accentGreen
            case .failed: return .red
            case .skipped: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

// MARK: - Test Service

@MainActor
final class TestService: ObservableObject {
    @Published var targets: [TestTarget] = []
    @Published var isRunning = false
    @Published var isScanning = false
    @Published var lastRunSummary: String = ""
    @Published var errorMessage: String?

    private var workingDirectory: String = ""

    func setDirectory(_ path: String) {
        workingDirectory = path
        scanTests()
    }

    func scanTests() {
        guard !workingDirectory.isEmpty else { return }
        isScanning = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let targets = await Self.discoverTests(dir: dir)
            await MainActor.run {
                self.targets = targets
                self.isScanning = false
            }
        }
    }

    func runAll() {
        guard !workingDirectory.isEmpty else { return }
        isRunning = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let (output, _) = await Self.runSwiftTest(dir: dir, filter: nil)
            let results = await Self.parseTestResults(output)
            await MainActor.run {
                self.applyResults(results)
                self.isRunning = false
                let passed = self.targets.flatMap(\.classes).flatMap(\.methods).filter { $0.status == .passed }.count
                let failed = self.targets.flatMap(\.classes).flatMap(\.methods).filter { $0.status == .failed }.count
                self.lastRunSummary = "\(passed) passed, \(failed) failed"
            }
        }
    }

    func runTest(_ method: TestMethod) {
        guard !workingDirectory.isEmpty else { return }
        isRunning = true
        let dir = workingDirectory
        let filter = method.name
        Task.detached(priority: .userInitiated) {
            let (output, _) = await Self.runSwiftTest(dir: dir, filter: filter)
            let results = await Self.parseTestResults(output)
            await MainActor.run {
                self.applyResults(results)
                self.isRunning = false
            }
        }
    }

    func runClass(_ cls: TestClass) {
        guard !workingDirectory.isEmpty else { return }
        isRunning = true
        let dir = workingDirectory
        let filter = cls.name
        Task.detached(priority: .userInitiated) {
            let (output, _) = await Self.runSwiftTest(dir: dir, filter: filter)
            let results = await Self.parseTestResults(output)
            await MainActor.run {
                self.applyResults(results)
                self.isRunning = false
            }
        }
    }

    private func applyResults(_ results: [String: TestMethod.TestStatus]) {
        for ti in targets.indices {
            for ci in targets[ti].classes.indices {
                for mi in targets[ti].classes[ci].methods.indices {
                    let name = targets[ti].classes[ci].methods[mi].name
                    if let status = results[name] {
                        targets[ti].classes[ci].methods[mi].status = status
                    }
                }
            }
        }
    }

    nonisolated private static func discoverTests(dir: String) -> [TestTarget] {
        let fm = FileManager.default
        let testsDir = (dir as NSString).appendingPathComponent("Tests")
        guard fm.fileExists(atPath: testsDir) else { return [] }

        guard let targetDirs = try? fm.contentsOfDirectory(atPath: testsDir) else { return [] }

        var targets: [TestTarget] = []
        for targetName in targetDirs.sorted() {
            let targetPath = (testsDir as NSString).appendingPathComponent(targetName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue else { continue }

            guard let files = try? fm.contentsOfDirectory(atPath: targetPath) else { continue }
            var classes: [TestClass] = []

            for file in files.sorted() where file.hasSuffix(".swift") {
                let filePath = (targetPath as NSString).appendingPathComponent(file)
                guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

                // Parse test classes and methods
                let parsedClasses = parseSwiftTestFile(content, fileName: file)
                classes.append(contentsOf: parsedClasses)
            }

            if !classes.isEmpty {
                targets.append(TestTarget(id: targetName, name: targetName, classes: classes))
            }
        }
        return targets
    }

    nonisolated private static func parseSwiftTestFile(_ content: String, fileName: String) -> [TestClass] {
        var classes: [TestClass] = []
        var currentClass: String?
        var currentMethods: [TestMethod] = []

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect test class
            if trimmed.contains("class ") && (trimmed.contains(": XCTestCase") || trimmed.contains("XCTestCase")) {
                if let cls = currentClass {
                    classes.append(TestClass(id: cls, name: cls, methods: currentMethods))
                }
                let parts = trimmed.components(separatedBy: "class ")
                if parts.count > 1 {
                    let name = parts[1].components(separatedBy: ":").first?.trimmingCharacters(in: .whitespaces) ?? ""
                    currentClass = name
                    currentMethods = []
                }
            }

            // Detect test methods
            if trimmed.hasPrefix("func test") {
                let name = trimmed
                    .replacingOccurrences(of: "func ", with: "")
                    .components(separatedBy: "(").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !name.isEmpty {
                    currentMethods.append(TestMethod(id: "\(currentClass ?? "").\(name)", name: name))
                }
            }
        }

        if let cls = currentClass {
            classes.append(TestClass(id: cls, name: cls, methods: currentMethods))
        }

        return classes
    }

    nonisolated private static func runSwiftTest(dir: String, filter: String?) -> (String, Bool) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        var args = ["test"]
        if let filter = filter {
            args.append(contentsOf: ["--filter", filter])
        }
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: dir)
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = (String(data: data, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
        return (output, process.terminationStatus == 0)
        #else
        return ("Running tests is not available on iOS", false)
        #endif
    }

    nonisolated private static func parseTestResults(_ output: String) -> [String: TestMethod.TestStatus] {
        var results: [String: TestMethod.TestStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            if line.contains("passed") {
                let name = line.components(separatedBy: "'").dropFirst().first ?? ""
                if !name.isEmpty { results[name] = .passed }
            }
            if line.contains("failed") {
                let name = line.components(separatedBy: "'").dropFirst().first ?? ""
                if !name.isEmpty { results[name] = .failed }
            }
            // XCTest format: Test Case '-[ClassName testMethod]' passed
            if line.contains("Test Case") {
                if line.contains("passed") {
                    let method = extractTestMethodName(from: line)
                    if !method.isEmpty { results[method] = .passed }
                } else if line.contains("failed") {
                    let method = extractTestMethodName(from: line)
                    if !method.isEmpty { results[method] = .failed }
                }
            }
        }
        return results
    }

    nonisolated private static func extractTestMethodName(from line: String) -> String {
        // Format: "Test Case '-[Class method]' passed/failed"
        guard let start = line.firstIndex(of: "["),
              let end = line.firstIndex(of: "]") else { return "" }
        let inside = line[line.index(after: start)..<end]
        let parts = inside.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : ""
    }
}

// MARK: - Test Explorer View

struct TestExplorerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var testService = TestService()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Tests")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                if !testService.lastRunSummary.isEmpty {
                    Text(testService.lastRunSummary)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }

                Spacer()

                if testService.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: { testService.runAll() }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Run All")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(.accentGreen)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(testService.isRunning)
                .help("Run all tests")

                Button(action: { testService.scanTests() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh test list")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            if testService.isScanning && testService.targets.isEmpty {
                ProgressView("Scanning tests…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if testService.targets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach($testService.targets) { $target in
                            TestTargetRow(target: $target, testService: testService)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { testService.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            testService.setDirectory(newDir)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "checkmark.diamond")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("No tests found")
                .font(Typography.bodySmallMedium)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Add XCTest files to your Tests/ directory")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Test Target Row

struct TestTargetRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var target: TestTarget
    @ObservedObject var testService: TestService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Target header
            Button(action: { target.isExpanded.toggle() }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: target.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 10)

                    Image(systemName: "testtube.2")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)

                    Text(target.name)
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)

                    Spacer()

                    // Summary badges
                    let passed = target.classes.reduce(0) { $0 + $1.passCount }
                    let failed = target.classes.reduce(0) { $0 + $1.failCount }

                    if passed > 0 {
                        Text("\(passed) passed")
                            .font(Typography.micro)
                            .foregroundColor(.accentGreen)
                    }
                    if failed > 0 {
                        Text("\(failed) failed")
                            .font(Typography.micro)
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
            }
            .buttonStyle(.plain)

            if target.isExpanded {
                ForEach($target.classes) { $cls in
                    TestClassRow(testClass: $cls, testService: testService)
                }
            }
        }
    }
}

// MARK: - Test Class Row

struct TestClassRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Binding var testClass: TestClass
    @ObservedObject var testService: TestService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { testClass.isExpanded.toggle() }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: testClass.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 8)

                    Text(testClass.name)
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textPrimary)

                    Text("\(testClass.passCount)/\(testClass.totalCount)")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)

                    Spacer()

                    Button(action: { testService.runClass(testClass) }) {
                        Image(systemName: "play.circle")
                            .font(Typography.captionSmall)
                            .foregroundColor(.accentGreen)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.leading, Spacing.xxxl)
                .padding(.trailing, Spacing.xl)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            if testClass.isExpanded {
                ForEach(testClass.methods) { method in
                    TestMethodRow(method: method, testService: testService)
                }
            }
        }
    }
}

// MARK: - Test Method Row

struct TestMethodRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let method: TestMethod
    @ObservedObject var testService: TestService
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: method.status.icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(method.status.color)
                .frame(width: 14)

            Text(method.name)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textPrimary)
                .lineLimit(1)

            if let duration = method.duration {
                Text(String(format: "%.2fs", duration))
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            Spacer()

            if isHovered {
                Button(action: { testService.runTest(method) }) {
                    Image(systemName: "play.circle")
                        .font(Typography.captionSmall)
                        .foregroundColor(.accentGreen)
                }
                .buttonStyle(ScaleButtonStyle())
                .transition(.opacity)
            }
        }
        .padding(.leading, CGFloat(Spacing.colossal + Spacing.xl))
        .padding(.trailing, Spacing.xl)
        .padding(.vertical, 2)
        .background(isHovered ? themeManager.palette.bgElevated.opacity(0.3) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }
}
