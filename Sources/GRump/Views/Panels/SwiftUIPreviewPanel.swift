import SwiftUI
#if os(macOS)
import AppKit
#endif

/// SwiftUI Preview canvas panel — renders preview snapshots of SwiftUI views.
struct SwiftUIPreviewPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var selectedDevice = "iPhone 15 Pro"
    @State private var colorSchemePreview: ColorScheme = .dark
    @State private var dynamicTypeSize: DynamicTypeSize = .medium
    @State private var previewImage: Image?
    @State private var isBuilding = false
    @State private var buildError: String?
    @State private var lastPreviewFile: String = ""

    private let devices = [
        "iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 16", "iPhone 16 Plus",
        "iPhone 15 Pro", "iPhone SE (3rd gen)",
        "iPad Pro 13\"", "iPad Pro 11\"", "iPad Air 11\"", "iPad mini (6th gen)",
        "Apple Watch Ultra 2 (49mm)", "Apple Watch Series 10 (46mm)",
        "Apple TV 4K",
        "Mac"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Preview")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                Spacer()

                // Device picker
                Menu {
                    ForEach(devices, id: \.self) { device in
                        Button(device) { selectedDevice = device }
                    }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: deviceIcon)
                            .font(Typography.captionSmall)
                        Text(selectedDevice)
                            .font(Typography.captionSmall)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(themeManager.palette.textMuted)
                }
                .menuStyle(.borderlessButton)

                // Color scheme toggle
                Button(action: {
                    colorSchemePreview = colorSchemePreview == .dark ? .light : .dark
                }) {
                    Image(systemName: colorSchemePreview == .dark ? "moon.fill" : "sun.max.fill")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Toggle light/dark")

                // Refresh
                Button(action: refreshPreview) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Refresh preview")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Preview canvas
            if isBuilding {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Building preview…")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = buildError {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.accentOrange)
                    Text("Preview failed")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text(error)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.huge)
                    Button("Retry") { refreshPreview() }
                        .buttonStyle(ScaleButtonStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let image = previewImage {
                ScrollView([.horizontal, .vertical]) {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 8)
                        .padding(Spacing.huge)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }

            // Dynamic Type slider
            HStack(spacing: Spacing.lg) {
                Image(systemName: "textformat.size.smaller")
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                Slider(value: dynamicTypeSizeBinding, in: 0...6, step: 1)
                    .frame(maxWidth: 200)
                Image(systemName: "textformat.size.larger")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgCard)
        }
        .background(themeManager.palette.bgDark)
        .onAppear {
            if !viewModel.workingDirectory.isEmpty && previewImage == nil && buildError == nil {
                scanForPreviewFiles()
            }
        }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            if !newDir.isEmpty { scanForPreviewFiles() }
        }
    }

    private func scanForPreviewFiles() {
        guard !viewModel.workingDirectory.isEmpty else { return }
        let dir = viewModel.workingDirectory
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: dir) else { return }
            var previewFiles: [String] = []
            while let path = enumerator.nextObject() as? String {
                let name = (path as NSString).lastPathComponent
                if name == ".build" || name == "node_modules" || name == ".git" || name == "DerivedData" {
                    enumerator.skipDescendants()
                    continue
                }
                guard path.hasSuffix(".swift") else { continue }
                let fullPath = (dir as NSString).appendingPathComponent(path)
                if let content = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                    if content.contains("#Preview") || content.contains("PreviewProvider") {
                        previewFiles.append(path)
                    }
                }
            }
            await MainActor.run {
                if let first = previewFiles.first {
                    self.lastPreviewFile = first
                }
            }
        }
    }

    private var deviceIcon: String {
        if selectedDevice.contains("iPad") { return "ipad" }
        if selectedDevice.contains("Mac") { return "macbook" }
        if selectedDevice.contains("Watch") { return "applewatch" }
        if selectedDevice.contains("TV") { return "appletv" }
        return "iphone"
    }

    private var dynamicTypeSizeBinding: Binding<Double> {
        Binding(
            get: {
                switch dynamicTypeSize {
                case .xSmall: return 0
                case .small: return 1
                case .medium: return 2
                case .large: return 3
                case .xLarge: return 4
                case .xxLarge: return 5
                case .xxxLarge: return 6
                default: return 2
                }
            },
            set: { val in
                switch Int(val) {
                case 0: dynamicTypeSize = .xSmall
                case 1: dynamicTypeSize = .small
                case 2: dynamicTypeSize = .medium
                case 3: dynamicTypeSize = .large
                case 4: dynamicTypeSize = .xLarge
                case 5: dynamicTypeSize = .xxLarge
                case 6: dynamicTypeSize = .xxxLarge
                default: dynamicTypeSize = .medium
                }
            }
        )
    }

    private func refreshPreview() {
        isBuilding = true
        buildError = nil
        previewImage = nil

        let workDir = viewModel.workingDirectory
        let previewFile = lastPreviewFile

        guard !workDir.isEmpty else {
            isBuilding = false
            buildError = "No project open. Open a Swift project to enable previews."
            return
        }
        guard !previewFile.isEmpty else {
            isBuilding = false
            buildError = "No SwiftUI preview file found. Add a #Preview or PreviewProvider to a .swift file."
            return
        }

        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let projectType = detectProjectType(in: workDir, fm: fm)

            let process = Process()
            process.currentDirectoryURL = URL(fileURLWithPath: workDir)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            switch projectType {
            case .xcodeworkspace(let path):
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                process.arguments = [
                    "-workspace", path,
                    "-scheme", defaultScheme(in: workDir, fm: fm),
                    "build",
                    "-destination", "platform=macOS",
                    "-quiet"
                ]
            case .xcodeproj(let path):
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
                process.arguments = [
                    "-project", path,
                    "-scheme", defaultScheme(in: workDir, fm: fm),
                    "build",
                    "-destination", "platform=macOS",
                    "-quiet"
                ]
            case .spm:
                process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
                process.arguments = ["build"]
            case .none:
                await MainActor.run {
                    self.isBuilding = false
                    self.buildError = "No Xcode project, workspace, or Package.swift found in \(workDir)."
                }
                return
            }

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    self.isBuilding = false
                    self.buildError = "Failed to launch build: \(error.localizedDescription)"
                }
                return
            }

            // Read stderr asynchronously to avoid deadlocks
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode != 0 {
                let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
                let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                let combined = (stderrStr + "\n" + stdoutStr).trimmingCharacters(in: .whitespacesAndNewlines)
                // Extract the most relevant error lines
                let errorSummary = extractBuildErrors(from: combined)
                await MainActor.run {
                    self.isBuilding = false
                    self.buildError = errorSummary.isEmpty
                        ? "Build failed with exit code \(exitCode)."
                        : errorSummary
                }
                return
            }

            // Build succeeded — look for a preview snapshot in DerivedData
            let snapshotImage = findPreviewSnapshot(workDir: workDir, previewFile: previewFile, fm: fm)

            await MainActor.run {
                self.isBuilding = false
                if let snapshotImage {
                    #if os(macOS)
                    self.previewImage = Image(nsImage: snapshotImage)
                    #else
                    self.previewImage = Image(uiImage: snapshotImage)
                    #endif
                } else {
                    self.buildError = "Build succeeded but no preview snapshot was generated. Ensure the file contains a #Preview macro or PreviewProvider."
                }
            }
        }
    }

    private enum ProjectType {
        case xcodeworkspace(String)
        case xcodeproj(String)
        case spm
        case none
    }

    private func detectProjectType(in dir: String, fm: FileManager) -> ProjectType {
        if let contents = try? fm.contentsOfDirectory(atPath: dir) {
            // Prefer workspace over project
            if let ws = contents.first(where: { $0.hasSuffix(".xcworkspace") && !$0.hasPrefix(".") }) {
                return .xcodeworkspace((dir as NSString).appendingPathComponent(ws))
            }
            if let proj = contents.first(where: { $0.hasSuffix(".xcodeproj") }) {
                return .xcodeproj((dir as NSString).appendingPathComponent(proj))
            }
            if contents.contains("Package.swift") {
                return .spm
            }
        }
        return .none
    }

    private func defaultScheme(in dir: String, fm: FileManager) -> String {
        // Use the directory name as the default scheme (Xcode convention)
        return URL(fileURLWithPath: dir).lastPathComponent
    }

    private func extractBuildErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        let errorLines = lines.filter { line in
            let lower = line.lowercased()
            return lower.contains("error:") || lower.contains("fatal error")
        }
        if errorLines.isEmpty {
            // Return last meaningful lines if no explicit error markers
            let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return meaningful.suffix(5).joined(separator: "\n")
        }
        return errorLines.prefix(10).joined(separator: "\n")
    }

    #if os(macOS)
    private func findPreviewSnapshot(workDir: String, previewFile: String, fm: FileManager) -> NSImage? {
        // Check DerivedData locations for preview snapshots
        let derivedDataPaths = [
            (workDir as NSString).appendingPathComponent("DerivedData"),
            NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
        ]

        let projectName = URL(fileURLWithPath: workDir).lastPathComponent

        for basePath in derivedDataPaths {
            guard fm.fileExists(atPath: basePath) else { continue }
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

            // Find the DerivedData subfolder matching our project
            let matching = entries.filter { $0.hasPrefix(projectName) }
            for entry in matching {
                let previewsDir = (basePath as NSString)
                    .appendingPathComponent(entry)
                    .appending("/Build/Intermediates.noindex/Previews")

                guard fm.fileExists(atPath: previewsDir) else { continue }

                // Recursively search for .png snapshots
                if let enumerator = fm.enumerator(atPath: previewsDir) {
                    var newest: (path: String, date: Date)?
                    while let file = enumerator.nextObject() as? String {
                        guard file.hasSuffix(".png") || file.hasSuffix(".jpg") else { continue }
                        let fullPath = (previewsDir as NSString).appendingPathComponent(file)
                        if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                           let modDate = attrs[.modificationDate] as? Date {
                            if newest == nil || modDate > newest!.date {
                                newest = (fullPath, modDate)
                            }
                        }
                    }
                    if let newest, let image = NSImage(contentsOfFile: newest.path) {
                        return image
                    }
                }
            }
        }
        return nil
    }
    #else
    private func findPreviewSnapshot(workDir: String, previewFile: String, fm: FileManager) -> UIImage? {
        // Preview snapshots are generated by Xcode on macOS; on iOS this is a no-op
        return nil
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "eye.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("SwiftUI Preview")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(themeManager.palette.textSecondary)

            if !lastPreviewFile.isEmpty {
                Text("Found preview: \(lastPreviewFile)")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .multilineTextAlignment(.center)
                Text("Press Refresh to build preview snapshot")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            } else if viewModel.workingDirectory.isEmpty {
                Text("Open a project folder first")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                    .multilineTextAlignment(.center)
            } else {
                Text("No SwiftUI files with #Preview\nor PreviewProvider found")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
