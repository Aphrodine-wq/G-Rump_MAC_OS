import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Asset Models

struct AssetCatalogItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let type: AssetType

    enum AssetType: String, Hashable {
        case imageSet
        case colorSet
        case appIcon
        case dataSet
        case symbolSet
        case unknown

        var icon: String {
            switch self {
            case .imageSet: return "photo"
            case .colorSet: return "paintpalette"
            case .appIcon: return "app.badge"
            case .dataSet: return "doc"
            case .symbolSet: return "star.square"
            case .unknown: return "questionmark.square"
            }
        }

        var color: Color {
            switch self {
            case .imageSet: return Color(red: 0.85, green: 0.3, blue: 0.9)
            case .colorSet: return Color(red: 0.3, green: 0.8, blue: 0.5)
            case .appIcon: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .dataSet: return Color(red: 0.6, green: 0.6, blue: 0.7)
            case .symbolSet: return .orange
            case .unknown: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

// MARK: - Asset Service

@MainActor
final class AssetCatalogService: ObservableObject {
    @Published var catalogs: [String] = []
    @Published var items: [AssetCatalogItem] = []
    @Published var selectedCatalog: String = ""
    @Published var isLoading = false

    func setDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        isLoading = true
        let dir = path
        Task.detached(priority: .userInitiated) {
            let catalogs = await Self.findCatalogs(in: dir)
            let items: [AssetCatalogItem]
            if let first = catalogs.first {
                items = await Self.parseCatalog(at: first)
            } else {
                items = []
            }
            await MainActor.run {
                self.catalogs = catalogs
                self.selectedCatalog = catalogs.first ?? ""
                self.items = items
                self.isLoading = false
            }
        }
    }

    func selectCatalog(_ path: String) {
        selectedCatalog = path
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let items = await Self.parseCatalog(at: path)
            await MainActor.run {
                self.items = items
                self.isLoading = false
            }
        }
    }

    func generateAppIcons(from sourceURL: URL) {
        #if os(macOS)
        guard let image = NSImage(contentsOf: sourceURL) else { return }
        let sizes: [(String, CGFloat)] = [
            ("Icon-20@2x", 40), ("Icon-20@3x", 60),
            ("Icon-29@2x", 58), ("Icon-29@3x", 87),
            ("Icon-40@2x", 80), ("Icon-40@3x", 120),
            ("Icon-60@2x", 120), ("Icon-60@3x", 180),
            ("Icon-76", 76), ("Icon-76@2x", 152),
            ("Icon-83.5@2x", 167),
            ("Icon-1024", 1024)
        ]

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcons")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        for (name, size) in sizes {
            let resized = NSImage(size: NSSize(width: size, height: size))
            resized.lockFocus()
            image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            resized.unlockFocus()

            if let tiff = resized.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiff),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let fileURL = outputDir.appendingPathComponent("\(name).png")
                try? pngData.write(to: fileURL)
            }
        }

        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: outputDir.path)
        #endif
    }

    nonisolated private static func findCatalogs(in dir: String) -> [String] {
        var results: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return [] }
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".xcassets") {
                results.append((dir as NSString).appendingPathComponent(path))
            }
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == "DerivedData" || name == ".git" {
                enumerator.skipDescendants()
            }
        }
        return results
    }

    nonisolated private static func parseCatalog(at path: String) -> [AssetCatalogItem] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        return contents.compactMap { name -> AssetCatalogItem? in
            let fullPath = (path as NSString).appendingPathComponent(name)
            let ext = (name as NSString).pathExtension.lowercased()
            let baseName = (name as NSString).deletingPathExtension

            let type: AssetCatalogItem.AssetType
            switch ext {
            case "imageset": type = .imageSet
            case "colorset": type = .colorSet
            case "appiconset": type = .appIcon
            case "dataset": type = .dataSet
            case "symbolset": type = .symbolSet
            default: return nil
            }

            return AssetCatalogItem(id: fullPath, name: baseName, path: fullPath, type: type)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Asset Manager Panel

struct AssetManagerPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = AssetCatalogService()
    @State private var searchText = ""
    @State private var filterType: AssetCatalogItem.AssetType?
    @State private var showSFSymbolBrowser = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Assets")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                if !service.catalogs.isEmpty {
                    Menu {
                        ForEach(service.catalogs, id: \.self) { catalog in
                            Button((catalog as NSString).lastPathComponent) {
                                service.selectCatalog(catalog)
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Text((service.selectedCatalog as NSString).lastPathComponent)
                                .font(Typography.captionSmall)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(themeManager.palette.textMuted)
                    }
                    .menuStyle(.borderlessButton)
                }

                Spacer()

                Button(action: { showSFSymbolBrowser.toggle() }) {
                    Image(systemName: "star.square")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("SF Symbol Browser")

                #if os(macOS)
                Button(action: openIconGenerator) {
                    Image(systemName: "app.badge")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Generate App Icons from image")
                #endif
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Search
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Filter assets…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            // Type filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    filterChip(nil, label: "All")
                    filterChip(.imageSet, label: "Images")
                    filterChip(.colorSet, label: "Colors")
                    filterChip(.appIcon, label: "App Icons")
                    filterChip(.dataSet, label: "Data")
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.md)
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: Spacing.lg)], spacing: Spacing.lg) {
                        ForEach(filteredItems) { item in
                            AssetItemView(item: item)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
        .sheet(isPresented: $showSFSymbolBrowser) {
            SFSymbolBrowserSheet()
        }
    }

    private var filteredItems: [AssetCatalogItem] {
        var result = service.items
        if let type = filterType {
            result = result.filter { $0.type == type }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    private func filterChip(_ type: AssetCatalogItem.AssetType?, label: String) -> some View {
        let isSelected = filterType == type
        return Button(action: { filterType = type }) {
            Text(label)
                .font(Typography.micro)
                .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(isSelected ? themeManager.palette.effectiveAccent.opacity(0.12) : themeManager.palette.bgElevated)
                .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    #if os(macOS)
    private func openIconGenerator() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.message = "Select a 1024×1024 source image for App Icon generation"
        if panel.runModal() == .OK, let url = panel.url {
            service.generateAppIcons(from: url)
        }
    }
    #endif

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "photo.stack")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("No asset catalogs found")
                .font(Typography.bodySmallMedium)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Add .xcassets to your project")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Asset Item View

struct AssetItemView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let item: AssetCatalogItem
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(item.type.color.opacity(0.1))
                    .frame(width: 60, height: 60)

                Image(systemName: item.type.icon)
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(item.type.color)
            }

            Text(item.name)
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 80)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHovered ? themeManager.palette.bgElevated.opacity(0.5) : Color.clear)
        )
        .onHover { isHovered = $0 }
    }
}

// MARK: - SF Symbol Browser Sheet

struct SFSymbolBrowserSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var copiedSymbol: String?

    private let commonSymbols = [
        "star", "heart", "bell", "gear", "person", "house", "magnifyingglass",
        "pencil", "trash", "folder", "doc", "paperplane", "envelope",
        "phone", "bubble.left", "camera", "photo", "film", "music.note",
        "play", "pause", "stop", "forward", "backward",
        "bolt", "flame", "drop", "leaf", "globe",
        "lock", "key", "shield", "eye", "hand.raised",
        "checkmark", "xmark", "plus", "minus", "arrow.right",
        "square", "circle", "triangle", "diamond", "hexagon",
        "cpu", "memorychip", "wifi", "antenna.radiowaves.left.and.right",
        "iphone", "ipad", "macbook", "applewatch", "airpods",
        "swift", "terminal", "hammer", "wrench", "paintbrush"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SF Symbols")
                    .font(Typography.heading3)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding()

            TextField("Search symbols…", text: $searchText)
                .font(Typography.bodySmall)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: Spacing.lg)], spacing: Spacing.lg) {
                    ForEach(filteredSymbols, id: \.self) { symbol in
                        Button(action: { copySymbol(symbol) }) {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: symbol)
                                    .font(.system(size: 22))
                                    .foregroundColor(copiedSymbol == symbol ? .accentGreen : themeManager.palette.textPrimary)
                                    .frame(width: 44, height: 44)

                                Text(symbol)
                                    .font(Typography.micro)
                                    .foregroundColor(themeManager.palette.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private var filteredSymbols: [String] {
        guard !searchText.isEmpty else { return commonSymbols }
        return commonSymbols.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func copySymbol(_ name: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Image(systemName: \"\(name)\")", forType: .string)
        #endif
        copiedSymbol = name
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            copiedSymbol = nil
        }
    }
}
