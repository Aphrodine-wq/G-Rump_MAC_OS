import SwiftUI

// MARK: - SPM Models

struct SPMDependency: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let version: String
    let resolvedVersion: String?
    var isOutdated: Bool = false
}

struct SPMTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let type: TargetType
    let dependencies: [String]

    enum TargetType: String, Hashable {
        case regular, test, executable, plugin, system, binary, macro

        var icon: String {
            switch self {
            case .regular: return "shippingbox"
            case .test: return "checkmark.diamond"
            case .executable: return "terminal"
            case .plugin: return "puzzlepiece"
            case .system: return "gearshape"
            case .binary: return "doc.zipper"
            case .macro: return "number.square"
            }
        }
    }
}

// MARK: - SPM Service

@MainActor
final class SPMService: ObservableObject {
    @Published var dependencies: [SPMDependency] = []
    @Published var targets: [SPMTarget] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var swiftVersion: String = ""

    private var workingDirectory = ""

    func setDirectory(_ path: String) {
        workingDirectory = path
        refresh()
    }

    func refresh() {
        guard !workingDirectory.isEmpty else { return }
        let packagePath = (workingDirectory as NSString).appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: packagePath) else {
            errorMessage = "No Package.swift found"
            return
        }

        isLoading = true
        errorMessage = nil
        let dir = workingDirectory

        Task.detached(priority: .userInitiated) {
            let deps = await Self.parseDependencies(dir: dir)
            let targets = await Self.parseTargets(dir: dir)
            let version = Self.getSwiftVersion()

            await MainActor.run {
                self.dependencies = deps
                self.targets = targets
                self.swiftVersion = version
                self.isLoading = false
            }
        }
    }

    func resolve() {
        guard !workingDirectory.isEmpty else { return }
        isLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["package", "resolve"]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            await self.refresh()
        }
    }

    func update() {
        guard !workingDirectory.isEmpty else { return }
        isLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["package", "update"]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            await self.refresh()
        }
    }

    nonisolated static func parseDependencies(dir: String) -> [SPMDependency] {
        // Parse Package.resolved for actual resolved versions
        let resolvedPath = (dir as NSString).appendingPathComponent("Package.resolved")
        var resolvedVersions: [String: String] = [:]

        if let data = FileManager.default.contents(atPath: resolvedPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // v2 format
            if let pins = json["pins"] as? [[String: Any]] {
                for pin in pins {
                    let identity = pin["identity"] as? String ?? ""
                    if let state = pin["state"] as? [String: Any],
                       let version = state["version"] as? String {
                        resolvedVersions[identity] = version
                    }
                }
            }
            // v1 format
            if let obj = json["object"] as? [String: Any],
               let pins = obj["pins"] as? [[String: Any]] {
                for pin in pins {
                    let pkg = pin["package"] as? String ?? ""
                    if let state = pin["state"] as? [String: Any],
                       let version = state["version"] as? String {
                        resolvedVersions[pkg.lowercased()] = version
                    }
                }
            }
        }

        // Parse Package.swift for declared dependencies
        let packagePath = (dir as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else { return [] }

        var deps: [SPMDependency] = []
        let lines = content.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match .package(url: "...", from: "...")
            if trimmed.contains(".package(") && trimmed.contains("url:") {
                var url = ""
                var version = ""

                // Extract URL
                if let urlStart = trimmed.range(of: "url:"),
                   let quoteStart = trimmed[urlStart.upperBound...].firstIndex(of: "\"") {
                    let afterQuote = trimmed.index(after: quoteStart)
                    if let quoteEnd = trimmed[afterQuote...].firstIndex(of: "\"") {
                        url = String(trimmed[afterQuote..<quoteEnd])
                    }
                }

                // Extract version
                if let fromRange = trimmed.range(of: "from:") {
                    let afterFrom = trimmed[fromRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if let qStart = afterFrom.firstIndex(of: "\""),
                       let qEnd = afterFrom[afterFrom.index(after: qStart)...].firstIndex(of: "\"") {
                        version = String(afterFrom[afterFrom.index(after: qStart)..<qEnd])
                    }
                }

                if !url.isEmpty {
                    let name = (url as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
                    let resolved = resolvedVersions[name.lowercased()]

                    deps.append(SPMDependency(
                        id: url, name: name, url: url,
                        version: version.isEmpty ? "unspecified" : version,
                        resolvedVersion: resolved
                    ))
                }
            }
        }

        return deps
    }

    nonisolated static func parseTargets(dir: String) -> [SPMTarget] {
        let packagePath = (dir as NSString).appendingPathComponent("Package.swift")
        guard let content = try? String(contentsOfFile: packagePath, encoding: .utf8) else { return [] }

        var targets: [SPMTarget] = []

        // Simple regex-free parsing for target declarations
        let patterns: [(String, SPMTarget.TargetType)] = [
            (".target(", .regular),
            (".testTarget(", .test),
            (".executableTarget(", .executable),
            (".plugin(", .plugin),
            (".systemLibrary(", .system),
            (".binaryTarget(", .binary)
        ]

        for (pattern, type) in patterns {
            var searchContent = content
            while let range = searchContent.range(of: pattern) {
                let afterPattern = searchContent[range.upperBound...]

                // Extract name
                if let nameStart = afterPattern.range(of: "name:") {
                    let afterName = afterPattern[nameStart.upperBound...].trimmingCharacters(in: .whitespaces)
                    if let qStart = afterName.firstIndex(of: "\""),
                       let qEnd = afterName[afterName.index(after: qStart)...].firstIndex(of: "\"") {
                        let name = String(afterName[afterName.index(after: qStart)..<qEnd])
                        targets.append(SPMTarget(id: name, name: name, type: type, dependencies: []))
                    }
                }

                searchContent = String(searchContent[range.upperBound...])
            }
        }

        return targets
    }

    nonisolated static func getSwiftVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        // Extract version number
        if let range = output.range(of: #"Swift version [\d.]+"#, options: .regularExpression) {
            return String(output[range])
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - SPM Dashboard View

struct SPMDashboardView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = SPMService()
    @State private var selectedTab: SPMTab = .dependencies

    enum SPMTab: String, CaseIterable {
        case dependencies = "Dependencies"
        case targets = "Targets"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Picker("", selection: $selectedTab) {
                    ForEach(SPMTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                if !service.swiftVersion.isEmpty {
                    Text(service.swiftVersion)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }

                Spacer()

                Button(action: { service.resolve() }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Resolve packages")

                Button(action: { service.update() }) {
                    Image(systemName: "arrow.up.circle")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Update packages")

                Button(action: { service.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = service.errorMessage {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text(error)
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch selectedTab {
                case .dependencies:
                    dependenciesView
                case .targets:
                    targetsView
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
    }

    private var dependenciesView: some View {
        Group {
            if service.dependencies.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "shippingbox")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("No dependencies")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(service.dependencies) { dep in
                            SPMDependencyRow(dependency: dep)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private var targetsView: some View {
        Group {
            if service.targets.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Text("No targets found")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(service.targets) { target in
                            HStack(spacing: Spacing.lg) {
                                Image(systemName: target.type.icon)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(themeManager.palette.effectiveAccent)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(target.name)
                                        .font(Typography.bodySmallMedium)
                                        .foregroundColor(themeManager.palette.textPrimary)
                                    Text(target.type.rawValue)
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.textMuted)
                                }

                                Spacer()
                            }
                            .padding(Spacing.xl)
                            .background(themeManager.palette.bgElevated.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }
}

// MARK: - SPM Dependency Row

struct SPMDependencyRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let dependency: SPMDependency

    var body: some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: "shippingbox.fill")
                .font(Typography.bodySmall)
                .foregroundColor(themeManager.palette.effectiveAccent)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(dependency.name)
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)

                HStack(spacing: Spacing.lg) {
                    if let resolved = dependency.resolvedVersion {
                        Text("v\(resolved)")
                            .font(Typography.codeMicro)
                            .foregroundColor(.accentGreen)
                    }

                    Text("≥ \(dependency.version)")
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.textMuted)
                }

                Text(dependency.url)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if dependency.isOutdated {
                Text("Update available")
                    .font(Typography.micro)
                    .foregroundColor(.orange)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 1)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
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
