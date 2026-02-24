import SwiftUI
import Foundation

// MARK: - Xcode Project Models

struct XcodeTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let type: TargetType
    let bundleId: String?
    let deploymentTarget: String?

    enum TargetType: String, Hashable {
        case app = "Application"
        case framework = "Framework"
        case staticLibrary = "Static Library"
        case unitTest = "Unit Tests"
        case uiTest = "UI Tests"
        case appExtension = "App Extension"
        case watchApp = "Watch App"
        case widgetExtension = "Widget Extension"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .app: return "app.fill"
            case .framework: return "shippingbox.fill"
            case .staticLibrary: return "building.columns.fill"
            case .unitTest: return "checkmark.diamond.fill"
            case .uiTest: return "iphone.badge.play"
            case .appExtension: return "puzzlepiece.extension.fill"
            case .watchApp: return "applewatch"
            case .widgetExtension: return "rectangle.3.group.fill"
            case .unknown: return "questionmark.square"
            }
        }

        var color: Color {
            switch self {
            case .app: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .framework: return Color(red: 1.0, green: 0.6, blue: 0.2)
            case .staticLibrary: return Color(red: 0.6, green: 0.6, blue: 0.7)
            case .unitTest, .uiTest: return .accentGreen
            case .appExtension, .widgetExtension: return Color(red: 0.8, green: 0.4, blue: 0.9)
            case .watchApp: return Color(red: 0.9, green: 0.4, blue: 0.5)
            case .unknown: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

struct XcodeScheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isShared: Bool
}

struct XcodeBuildConfig: Identifiable, Hashable {
    let id: String
    let name: String
}

struct XcodeSigningInfo: Identifiable {
    let id = UUID()
    let teamId: String?
    let signingStyle: String
    let provisioningProfile: String?
    let isValid: Bool
}

// MARK: - Xcode Project Service

@MainActor
final class XcodeProjectService: ObservableObject {
    @Published var projectName: String = ""
    @Published var projectPath: String = ""
    @Published var targets: [XcodeTarget] = []
    @Published var schemes: [XcodeScheme] = []
    @Published var buildConfigs: [XcodeBuildConfig] = []
    @Published var signingInfo: XcodeSigningInfo?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedScheme: String = ""
    @Published var selectedConfig: String = "Debug"

    func setDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        let dir = path

        Task { @MainActor in
            let result = await Self.parseProject(dir: dir)
            self.projectName = result.name
            self.projectPath = result.path
            self.targets = result.targets
            self.schemes = result.schemes
            self.buildConfigs = result.configs
            self.selectedScheme = result.schemes.first?.name ?? ""
            self.isLoading = false
            if result.targets.isEmpty && result.path.isEmpty {
                self.errorMessage = "No Xcode project found"
            }
        }
    }

    func build() {
        guard !projectPath.isEmpty, !selectedScheme.isEmpty else { return }
        let dir = (projectPath as NSString).deletingLastPathComponent
        let scheme = selectedScheme
        let config = selectedConfig

        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = [
                "-scheme", scheme,
                "-configuration", config,
                "build"
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
        }
    }

    func openInXcode() {
        #if os(macOS)
        guard !projectPath.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: projectPath))
        #endif
    }

    struct ParseResult {
        let name: String
        let path: String
        let targets: [XcodeTarget]
        let schemes: [XcodeScheme]
        let configs: [XcodeBuildConfig]
    }

    nonisolated private static func parseProject(dir: String) -> ParseResult {
        let fm = FileManager.default

        // Find .xcodeproj or .xcworkspace
        var projectPath = ""
        var projectName = ""

        if let contents = try? fm.contentsOfDirectory(atPath: dir) {
            // Prefer workspace
            if let workspace = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".")}) {
                projectPath = (dir as NSString).appendingPathComponent(workspace)
                projectName = (workspace as NSString).deletingPathExtension
            } else if let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                projectPath = (dir as NSString).appendingPathComponent(project)
                projectName = (project as NSString).deletingPathExtension
            }
        }

        guard !projectPath.isEmpty else {
            return ParseResult(name: "", path: "", targets: [], schemes: [], configs: [])
        }

        // Parse targets from pbxproj
        let targets = parsePbxproj(projectPath: projectPath)

        // Parse schemes
        let schemes = parseSchemes(projectPath: projectPath)

        // Standard build configs
        let configs = [
            XcodeBuildConfig(id: "Debug", name: "Debug"),
            XcodeBuildConfig(id: "Release", name: "Release")
        ]

        return ParseResult(
            name: projectName, path: projectPath,
            targets: targets, schemes: schemes, configs: configs
        )
    }

    nonisolated private static func parsePbxproj(projectPath: String) -> [XcodeTarget] {
        // If it's a workspace, find the embedded project
        var pbxprojPath: String
        if projectPath.hasSuffix(".xcworkspace") {
            let parent = (projectPath as NSString).deletingLastPathComponent
            let projectName = (projectPath as NSString).lastPathComponent
                .replacingOccurrences(of: ".xcworkspace", with: ".xcodeproj")
            pbxprojPath = (parent as NSString).appendingPathComponent(projectName)
            pbxprojPath = (pbxprojPath as NSString).appendingPathComponent("project.pbxproj")
        } else {
            pbxprojPath = (projectPath as NSString).appendingPathComponent("project.pbxproj")
        }

        guard let content = try? String(contentsOfFile: pbxprojPath, encoding: .utf8) else {
            return []
        }

        var targets: [XcodeTarget] = []

        // Parse PBXNativeTarget sections
        let lines = content.components(separatedBy: "\n")
        var inTargetSection = false
        var currentName = ""
        var currentProductType = ""
        var currentId = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("/* Begin PBXNativeTarget section */") {
                inTargetSection = true
                continue
            }
            if trimmed.contains("/* End PBXNativeTarget section */") {
                inTargetSection = false
                continue
            }

            if inTargetSection {
                if trimmed.contains("isa = PBXNativeTarget") {
                    // Extract target ID from the line above (the section entry)
                    currentId = UUID().uuidString
                }

                if trimmed.hasPrefix("name = ") {
                    currentName = trimmed
                        .replacingOccurrences(of: "name = ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }

                if trimmed.hasPrefix("productType = ") {
                    currentProductType = trimmed
                        .replacingOccurrences(of: "productType = ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .replacingOccurrences(of: "\"", with: "")
                        .trimmingCharacters(in: .whitespaces)

                    let targetType = mapProductType(currentProductType)

                    if !currentName.isEmpty {
                        targets.append(XcodeTarget(
                            id: currentId.isEmpty ? currentName : currentId,
                            name: currentName,
                            type: targetType,
                            bundleId: nil,
                            deploymentTarget: nil
                        ))
                    }
                    currentName = ""
                    currentProductType = ""
                    currentId = ""
                }
            }
        }

        return targets
    }

    nonisolated private static func mapProductType(_ productType: String) -> XcodeTarget.TargetType {
        if productType.contains("application") { return .app }
        if productType.contains("framework") { return .framework }
        if productType.contains("static") { return .staticLibrary }
        if productType.contains("unit-test") { return .unitTest }
        if productType.contains("ui-testing") { return .uiTest }
        if productType.contains("app-extension") || productType.contains("appex") { return .appExtension }
        if productType.contains("watchkit") { return .watchApp }
        if productType.contains("widget") { return .widgetExtension }
        return .unknown
    }

    nonisolated private static func parseSchemes(projectPath: String) -> [XcodeScheme] {
        let fm = FileManager.default
        var schemes: [XcodeScheme] = []

        // Check shared schemes
        let sharedSchemesDir: String
        if projectPath.hasSuffix(".xcworkspace") {
            sharedSchemesDir = (projectPath as NSString).appendingPathComponent("xcshareddata/xcschemes")
        } else {
            sharedSchemesDir = (projectPath as NSString).appendingPathComponent("xcshareddata/xcschemes")
        }

        if let files = try? fm.contentsOfDirectory(atPath: sharedSchemesDir) {
            for file in files where file.hasSuffix(".xcscheme") {
                let name = (file as NSString).deletingPathExtension
                schemes.append(XcodeScheme(id: name, name: name, isShared: true))
            }
        }

        // Also try xcodebuild -list for schemes
        if schemes.isEmpty {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = ["-list", "-json"]
            let dir = (projectPath as NSString).deletingLastPathComponent
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let projectInfo = json["project"] as? [String: Any] ?? json["workspace"] as? [String: Any] ?? [:]
                if let schemeNames = projectInfo["schemes"] as? [String] {
                    schemes = schemeNames.map { XcodeScheme(id: $0, name: $0, isShared: false) }
                }
            }
        }

        return schemes
    }
}

// MARK: - Xcode Project View

struct XcodeProjectView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = XcodeProjectService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: Spacing.lg) {
                Image(systemName: "hammer.fill")
                    .font(Typography.bodySmall)
                    .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))

                Text(service.projectName.isEmpty ? "No Project" : service.projectName)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                #if os(macOS)
                Button(action: { service.openInXcode() }) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Open in Xcode")
                .disabled(service.projectPath.isEmpty)
                #endif

                Button(action: { service.setDirectory(viewModel.workingDirectory) }) {
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
                    Image(systemName: "hammer")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text(error)
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Scheme & Config pickers
                        if !service.schemes.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Scheme")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)

                                Picker("Scheme", selection: $service.selectedScheme) {
                                    ForEach(service.schemes) { scheme in
                                        Text(scheme.name).tag(scheme.name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, Spacing.xl)
                        }

                        if !service.buildConfigs.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Configuration")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)

                                Picker("Config", selection: $service.selectedConfig) {
                                    ForEach(service.buildConfigs) { config in
                                        Text(config.name).tag(config.name)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(.horizontal, Spacing.xl)
                        }

                        // Build button
                        Button(action: { service.build() }) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 12))
                                Text("Build")
                                    .font(Typography.bodySmallSemibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.lg)
                            .background(themeManager.palette.effectiveAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(service.selectedScheme.isEmpty)
                        .padding(.horizontal, Spacing.xl)

                        // Targets
                        if !service.targets.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Text("Targets")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textSecondary)
                                    .padding(.horizontal, Spacing.xl)

                                ForEach(service.targets) { target in
                                    HStack(spacing: Spacing.lg) {
                                        Image(systemName: target.type.icon)
                                            .font(Typography.bodySmall)
                                            .foregroundColor(target.type.color)
                                            .frame(width: 24)

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
                                    .padding(.horizontal, Spacing.xl)
                                    .padding(.vertical, Spacing.md)
                                }
                            }
                        }
                    }
                    .padding(.vertical, Spacing.xl)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
    }
}
