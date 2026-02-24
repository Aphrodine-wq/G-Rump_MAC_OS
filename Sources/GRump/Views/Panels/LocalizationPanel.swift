import SwiftUI

// MARK: - Localization Models

struct LocalizationEntry: Identifiable, Hashable {
    let id: String // key
    let key: String
    var baseValue: String
    var translations: [String: String] // locale → value
    var comment: String
    var state: EntryState

    enum EntryState: String, Hashable {
        case translated
        case needsReview
        case missing
        case stale

        var color: Color {
            switch self {
            case .translated: return .accentGreen
            case .needsReview: return .orange
            case .missing: return .red
            case .stale: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }

        var icon: String {
            switch self {
            case .translated: return "checkmark.circle.fill"
            case .needsReview: return "exclamationmark.circle.fill"
            case .missing: return "xmark.circle.fill"
            case .stale: return "clock.fill"
            }
        }
    }
}

// MARK: - Localization Service

@MainActor
final class LocalizationService: ObservableObject {
    @Published var entries: [LocalizationEntry] = []
    @Published var locales: [String] = ["en"]
    @Published var selectedLocale: String = "en"
    @Published var catalogPath: String = ""
    @Published var isLoading = false
    @Published var hardcodedStrings: [HardcodedString] = []

    struct HardcodedString: Identifiable {
        let id = UUID()
        let file: String
        let line: Int
        let text: String
    }

    func setDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        isLoading = true
        let dir = path
        Task.detached(priority: .userInitiated) {
            let (catalog, entries, locales) = await Self.findAndParse(dir: dir)
            let hardcoded = await Self.scanForHardcodedStrings(dir: dir)
            await MainActor.run {
                self.catalogPath = catalog
                self.entries = entries
                self.locales = locales
                self.hardcodedStrings = hardcoded
                self.isLoading = false
            }
        }
    }

    func addEntry(key: String, value: String) {
        let entry = LocalizationEntry(
            id: key, key: key, baseValue: value,
            translations: [:], comment: "", state: .missing
        )
        entries.append(entry)
    }

    func updateTranslation(key: String, locale: String, value: String) {
        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx].translations[locale] = value
            entries[idx].state = .translated
        }
    }

    nonisolated static func findAndParse(dir: String) -> (String, [LocalizationEntry], [String]) {
        let fm = FileManager.default
        // Look for .xcstrings files
        guard let enumerator = fm.enumerator(atPath: dir) else { return ("", [], ["en"]) }

        var catalogPath = ""
        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" {
                enumerator.skipDescendants()
                continue
            }
            if path.hasSuffix(".xcstrings") {
                catalogPath = (dir as NSString).appendingPathComponent(path)
                break
            }
        }

        guard !catalogPath.isEmpty,
              let data = fm.contents(atPath: catalogPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: Any] else {
            // Fall back to .strings files
            return (catalogPath, scanStringsFiles(dir: dir), ["en"])
        }

        let sourceLanguage = json["sourceLanguage"] as? String ?? "en"
        var entries: [LocalizationEntry] = []
        var allLocales: Set<String> = [sourceLanguage]

        for (key, value) in strings {
            guard let info = value as? [String: Any] else { continue }
            let comment = info["comment"] as? String ?? ""
            let localizations = info["localizations"] as? [String: Any] ?? [:]

            var translations: [String: String] = [:]
            for (locale, locValue) in localizations {
                allLocales.insert(locale)
                if let locDict = locValue as? [String: Any],
                   let stringUnit = locDict["stringUnit"] as? [String: Any],
                   let val = stringUnit["value"] as? String {
                    translations[locale] = val
                }
            }

            let baseValue = translations[sourceLanguage] ?? key
            let state: LocalizationEntry.EntryState = translations.count >= allLocales.count ? .translated : .missing

            entries.append(LocalizationEntry(
                id: key, key: key, baseValue: baseValue,
                translations: translations, comment: comment, state: state
            ))
        }

        entries.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        return (catalogPath, entries, Array(allLocales).sorted())
    }

    nonisolated private static func scanStringsFiles(dir: String) -> [LocalizationEntry] {
        let fm = FileManager.default
        let stringsPath = (dir as NSString).appendingPathComponent("en.lproj/Localizable.strings")
        guard let content = try? String(contentsOfFile: stringsPath, encoding: .utf8) else { return [] }

        var entries: [LocalizationEntry] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\"") else { continue }
            let parts = trimmed.components(separatedBy: "\" = \"")
            guard parts.count == 2 else { continue }
            let key = String(parts[0].dropFirst())
            let value = String(parts[1].dropLast(2)) // remove ";
            entries.append(LocalizationEntry(
                id: key, key: key, baseValue: value,
                translations: ["en": value], comment: "", state: .translated
            ))
        }
        return entries
    }

    nonisolated static func scanForHardcodedStrings(dir: String) -> [HardcodedString] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return [] }

        var results: [HardcodedString] = []

        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" || name == "Tests" {
                enumerator.skipDescendants()
                continue
            }
            guard path.hasSuffix(".swift") else { continue }

            let fullPath = (dir as NSString).appendingPathComponent(path)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            for (lineNum, line) in content.components(separatedBy: "\n").enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Look for Text("hardcoded string") patterns
                if trimmed.contains("Text(\"") && !trimmed.contains("String(localized:") &&
                   !trimmed.contains("LocalizedStringKey") && !trimmed.hasPrefix("//") {
                    // Extract the string
                    if let start = trimmed.range(of: "Text(\""),
                       let end = trimmed[start.upperBound...].firstIndex(of: "\"") {
                        let text = String(trimmed[start.upperBound..<end])
                        if text.count > 1 && !text.allSatisfy({ $0.isNumber || $0 == "." }) {
                            results.append(HardcodedString(file: path, line: lineNum + 1, text: text))
                        }
                    }
                }
            }
        }
        return results
    }
}

// MARK: - Localization Panel

struct LocalizationPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = LocalizationService()
    @State private var searchText = ""
    @State private var selectedTab: LocalizationTab = .strings
    @State private var showAddEntry = false
    @State private var newKey = ""
    @State private var newValue = ""

    enum LocalizationTab: String, CaseIterable {
        case strings = "Strings"
        case hardcoded = "Hardcoded"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Picker("", selection: $selectedTab) {
                    ForEach(LocalizationTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                if selectedTab == .strings {
                    // Locale picker
                    Menu {
                        ForEach(service.locales, id: \.self) { locale in
                            Button(locale.uppercased()) { service.selectedLocale = locale }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "globe")
                                .font(Typography.captionSmall)
                            Text(service.selectedLocale.uppercased())
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.textMuted)
                    }
                    .menuStyle(.borderlessButton)

                    Button(action: { showAddEntry = true }) {
                        Image(systemName: "plus")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Add string entry")
                }

                if selectedTab == .hardcoded {
                    Text("\(service.hardcodedStrings.count) found")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Search
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Filter…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            switch selectedTab {
            case .strings:
                stringsView
            case .hardcoded:
                hardcodedView
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
        .alert("Add String", isPresented: $showAddEntry) {
            TextField("Key", text: $newKey)
            TextField("Base value", text: $newValue)
            Button("Add") {
                if !newKey.isEmpty {
                    service.addEntry(key: newKey, value: newValue)
                    newKey = ""
                    newValue = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filteredEntries: [LocalizationEntry] {
        guard !searchText.isEmpty else { return service.entries }
        return service.entries.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.baseValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var stringsView: some View {
        Group {
            if service.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if service.entries.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "globe")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("No string catalogs found")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            LocalizationEntryRow(entry: entry, locale: service.selectedLocale)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }

    private var hardcodedView: some View {
        Group {
            if service.hardcodedStrings.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(.accentGreen)
                    Text("No hardcoded strings detected")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(filteredHardcoded) { item in
                            HStack(spacing: Spacing.lg) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.orange)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("\"\(item.text)\"")
                                        .font(Typography.captionSmallMedium)
                                        .foregroundColor(themeManager.palette.textPrimary)
                                        .lineLimit(1)

                                    HStack(spacing: Spacing.sm) {
                                        Text(item.file)
                                            .font(Typography.micro)
                                            .foregroundColor(themeManager.palette.effectiveAccent)
                                        Text("line \(item.line)")
                                            .font(Typography.micro)
                                            .foregroundColor(themeManager.palette.textMuted)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
    }

    private var filteredHardcoded: [LocalizationService.HardcodedString] {
        guard !searchText.isEmpty else { return service.hardcodedStrings }
        return service.hardcodedStrings.filter {
            $0.text.localizedCaseInsensitiveContains(searchText) ||
            $0.file.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Localization Entry Row

struct LocalizationEntryRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entry: LocalizationEntry
    let locale: String

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: entry.state.icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(entry.state.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.key)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Text(entry.translations[locale] ?? entry.baseValue)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }
}
