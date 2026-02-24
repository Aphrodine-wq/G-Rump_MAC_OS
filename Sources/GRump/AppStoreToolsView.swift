import SwiftUI

// MARK: - App Store Check Models

struct AppStoreCheck: Identifiable {
    let id: String
    let title: String
    let category: CheckCategory
    var status: CheckStatus
    var detail: String

    enum CheckCategory: String, CaseIterable {
        case icons = "Icons"
        case privacy = "Privacy"
        case entitlements = "Entitlements"
        case infoPlist = "Info.plist"
        case deployment = "Deployment"
        case localization = "Localization"

        var icon: String {
            switch self {
            case .icons: return "app.badge"
            case .privacy: return "hand.raised.fill"
            case .entitlements: return "lock.shield.fill"
            case .infoPlist: return "list.bullet.rectangle"
            case .deployment: return "iphone.and.arrow.forward"
            case .localization: return "globe"
            }
        }
    }

    enum CheckStatus {
        case pass, fail, warning, notChecked

        var icon: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .fail: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .notChecked: return "circle"
            }
        }

        var color: Color {
            switch self {
            case .pass: return .accentGreen
            case .fail: return .red
            case .warning: return .orange
            case .notChecked: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

// MARK: - App Store Service

@MainActor
final class AppStoreService: ObservableObject {
    @Published var checks: [AppStoreCheck] = []
    @Published var isRunning = false
    @Published var archiveLog: String = ""
    @Published var isArchiving = false

    func runChecks(directory: String) {
        guard !directory.isEmpty else { return }
        isRunning = true
        let dir = directory
        Task.detached(priority: .userInitiated) {
            let results = await Self.performChecks(dir: dir)
            await MainActor.run {
                self.checks = results
                self.isRunning = false
            }
        }
    }

    func archive(directory: String, scheme: String) {
        isArchiving = true
        archiveLog = "Starting archive…\n"
        let dir = directory
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = [
                "archive",
                "-scheme", scheme,
                "-archivePath", "\(dir)/build/\(scheme).xcarchive"
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor [weak self] in
                    self?.archiveLog += line
                }
            }

            try? process.run()
            process.waitUntilExit()

            await MainActor.run {
                self.isArchiving = false
                self.archiveLog += "\n\(process.terminationStatus == 0 ? "✓ Archive succeeded" : "✗ Archive failed")\n"
            }
        }
    }

    nonisolated static func performChecks(dir: String) -> [AppStoreCheck] {
        let fm = FileManager.default
        var checks: [AppStoreCheck] = []

        // 1. App Icon check
        let hasAppIcon = findFile(in: dir, matching: "AppIcon.appiconset")
        checks.append(AppStoreCheck(
            id: "app-icon", title: "App Icon present",
            category: .icons,
            status: hasAppIcon != nil ? .pass : .fail,
            detail: hasAppIcon != nil ? "Found AppIcon.appiconset" : "Missing AppIcon.appiconset in asset catalog"
        ))

        // 2. Privacy manifest
        let hasPrivacyManifest = findFile(in: dir, matching: "PrivacyInfo.xcprivacy")
        checks.append(AppStoreCheck(
            id: "privacy-manifest", title: "Privacy manifest",
            category: .privacy,
            status: hasPrivacyManifest != nil ? .pass : .warning,
            detail: hasPrivacyManifest != nil ? "PrivacyInfo.xcprivacy found" : "No PrivacyInfo.xcprivacy — required for apps using certain APIs"
        ))

        // 3. Info.plist
        let infoPlist = findFile(in: dir, matching: "Info.plist")
        if let plistPath = infoPlist,
           let data = fm.contents(atPath: plistPath),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {

            // Bundle display name
            let hasDisplayName = plist["CFBundleDisplayName"] != nil || plist["CFBundleName"] != nil
            checks.append(AppStoreCheck(
                id: "bundle-name", title: "Bundle display name",
                category: .infoPlist,
                status: hasDisplayName ? .pass : .fail,
                detail: hasDisplayName ? "Bundle name configured" : "Missing CFBundleDisplayName or CFBundleName"
            ))

            // Version
            let hasVersion = plist["CFBundleShortVersionString"] != nil
            checks.append(AppStoreCheck(
                id: "version", title: "Version number",
                category: .infoPlist,
                status: hasVersion ? .pass : .fail,
                detail: hasVersion ? "Version: \(plist["CFBundleShortVersionString"] ?? "?")" : "Missing CFBundleShortVersionString"
            ))

            // Build number
            let hasBuild = plist["CFBundleVersion"] != nil
            checks.append(AppStoreCheck(
                id: "build", title: "Build number",
                category: .infoPlist,
                status: hasBuild ? .pass : .fail,
                detail: hasBuild ? "Build: \(plist["CFBundleVersion"] ?? "?")" : "Missing CFBundleVersion"
            ))
        } else {
            checks.append(AppStoreCheck(
                id: "info-plist", title: "Info.plist",
                category: .infoPlist,
                status: .warning,
                detail: "Could not find or parse Info.plist"
            ))
        }

        // 4. Entitlements
        let entitlements = findFile(in: dir, matching: ".entitlements")
        checks.append(AppStoreCheck(
            id: "entitlements", title: "Entitlements file",
            category: .entitlements,
            status: entitlements != nil ? .pass : .warning,
            detail: entitlements != nil ? "Entitlements file found" : "No .entitlements file — may be needed for capabilities"
        ))

        // 5. Deployment target
        let packageSwift = (dir as NSString).appendingPathComponent("Package.swift")
        if fm.fileExists(atPath: packageSwift),
           let content = try? String(contentsOfFile: packageSwift, encoding: .utf8) {
            let hasMinVersion = content.contains(".macOS(") || content.contains(".iOS(")
            checks.append(AppStoreCheck(
                id: "deployment", title: "Deployment target",
                category: .deployment,
                status: hasMinVersion ? .pass : .warning,
                detail: hasMinVersion ? "Platform deployment targets configured" : "Could not verify deployment targets"
            ))
        }

        return checks
    }

    nonisolated private static func findFile(in dir: String, matching pattern: String) -> String? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return nil }
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" || name == "DerivedData" {
                enumerator.skipDescendants()
                continue
            }
            if path.contains(pattern) || name == pattern {
                return (dir as NSString).appendingPathComponent(path)
            }
        }
        return nil
    }
}

// MARK: - App Store Tools View

struct AppStoreToolsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = AppStoreService()
    @State private var selectedTab: AppStoreTab = .checklist

    enum AppStoreTab: String, CaseIterable {
        case checklist = "Checklist"
        case archive = "Archive"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Picker("", selection: $selectedTab) {
                    ForEach(AppStoreTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                if selectedTab == .checklist {
                    Button(action: { service.runChecks(directory: viewModel.workingDirectory) }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Run Checks")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(service.isRunning)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            switch selectedTab {
            case .checklist:
                checklistView
            case .archive:
                archiveView
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear {
            if !viewModel.workingDirectory.isEmpty && service.checks.isEmpty {
                service.runChecks(directory: viewModel.workingDirectory)
            }
        }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            if !newDir.isEmpty { service.runChecks(directory: newDir) }
        }
    }

    private var checklistView: some View {
        Group {
            if service.isRunning {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Running checks…")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.checks.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("Pre-submission Checklist")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Text("Run checks to validate your app\nbefore submitting to App Store")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(AppStoreCheck.CheckCategory.allCases, id: \.self) { category in
                            let categoryChecks = service.checks.filter { $0.category == category }
                            if !categoryChecks.isEmpty {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: category.icon)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(themeManager.palette.effectiveAccent)
                                    Text(category.rawValue)
                                        .font(Typography.captionSmallSemibold)
                                        .foregroundColor(themeManager.palette.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.xl)
                                .padding(.top, Spacing.xl)
                                .padding(.bottom, Spacing.sm)

                                ForEach(categoryChecks) { check in
                                    HStack(spacing: Spacing.lg) {
                                        Image(systemName: check.status.icon)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(check.status.color)

                                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                                            Text(check.title)
                                                .font(Typography.bodySmallMedium)
                                                .foregroundColor(themeManager.palette.textPrimary)
                                            Text(check.detail)
                                                .font(Typography.captionSmall)
                                                .foregroundColor(themeManager.palette.textMuted)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, Spacing.xl)
                                    .padding(.vertical, Spacing.md)
                                }
                            }
                        }

                        // Summary
                        let passed = service.checks.filter { $0.status == .pass }.count
                        let failed = service.checks.filter { $0.status == .fail }.count
                        let warnings = service.checks.filter { $0.status == .warning }.count

                        HStack(spacing: Spacing.xxl) {
                            Label("\(passed) passed", systemImage: "checkmark.circle.fill")
                                .font(Typography.captionSmallMedium)
                                .foregroundColor(.accentGreen)
                            if failed > 0 {
                                Label("\(failed) failed", systemImage: "xmark.circle.fill")
                                    .font(Typography.captionSmallMedium)
                                    .foregroundColor(.red)
                            }
                            if warnings > 0 {
                                Label("\(warnings) warnings", systemImage: "exclamationmark.triangle.fill")
                                    .font(Typography.captionSmallMedium)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(Spacing.xl)
                    }
                }
            }
        }
    }

    private var archiveView: some View {
        VStack(spacing: Spacing.xxl) {
            if service.isArchiving {
                ScrollView {
                    Text(service.archiveLog)
                        .font(Typography.codeSmall)
                        .foregroundColor(themeManager.palette.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.xl)
                }
            } else {
                Spacer()
                Image(systemName: "archivebox")
                    .font(.system(size: 36, weight: .light))
                    .foregroundColor(themeManager.palette.textMuted)
                Text("Archive & Upload")
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)
                Text("Build an archive for App Store submission")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)

                Button(action: {
                    service.archive(directory: viewModel.workingDirectory, scheme: "GRump")
                }) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 12))
                        Text("Archive")
                            .font(Typography.bodySmallSemibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.vertical, Spacing.xl)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(viewModel.workingDirectory.isEmpty)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
