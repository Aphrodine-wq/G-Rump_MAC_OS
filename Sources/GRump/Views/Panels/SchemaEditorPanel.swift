import SwiftUI

// MARK: - Schema Models

struct SchemaEntity: Identifiable, Hashable {
    let id: String
    let name: String
    var attributes: [SchemaAttribute]
    var relationships: [SchemaRelationship]
    let source: SchemaSource

    enum SchemaSource: String, Hashable {
        case coreData
        case swiftData
    }
}

struct SchemaAttribute: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let isOptional: Bool
    let defaultValue: String?
}

struct SchemaRelationship: Identifiable, Hashable {
    let id: String
    let name: String
    let destination: String
    let isToMany: Bool
    let inverse: String?
}

// MARK: - Schema Service

@MainActor
final class SchemaService: ObservableObject {
    @Published var entities: [SchemaEntity] = []
    @Published var isLoading = false
    @Published var migrationSuggestions: [MigrationSuggestion] = []

    struct MigrationSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let severity: Severity

        enum Severity { case info, warning, breaking }

        var color: Color {
            switch severity {
            case .info: return Color(red: 0.3, green: 0.6, blue: 1.0)
            case .warning: return .orange
            case .breaking: return .red
            }
        }

        var icon: String {
            switch severity {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .breaking: return "xmark.octagon.fill"
            }
        }
    }

    func setDirectory(_ path: String) {
        guard !path.isEmpty else { return }
        isLoading = true
        let dir = path
        Task.detached(priority: .userInitiated) {
            let entities = await Self.discoverEntities(in: dir)
            await MainActor.run {
                self.entities = entities
                self.isLoading = false
            }
        }
    }

    nonisolated private static func discoverEntities(in dir: String) -> [SchemaEntity] {
        var entities: [SchemaEntity] = []

        // Scan for SwiftData @Model classes
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir) else { return [] }

        while let path = enumerator.nextObject() as? String {
            let name = (path as NSString).lastPathComponent
            if name == ".build" || name == "node_modules" || name == ".git" {
                enumerator.skipDescendants()
                continue
            }

            if path.hasSuffix(".swift") {
                let fullPath = (dir as NSString).appendingPathComponent(path)
                guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
                entities.append(contentsOf: parseSwiftDataModels(content))
            }

            // Parse .xcdatamodeld
            if path.hasSuffix(".xcdatamodeld") {
                let fullPath = (dir as NSString).appendingPathComponent(path)
                entities.append(contentsOf: parseCoreDataModel(at: fullPath))
            }
        }

        return entities
    }

    nonisolated private static func parseSwiftDataModels(_ content: String) -> [SchemaEntity] {
        var entities: [SchemaEntity] = []
        let lines = content.components(separatedBy: "\n")
        var currentClass: String?
        var attrs: [SchemaAttribute] = []
        var rels: [SchemaRelationship] = []
        var inModel = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("@Model") {
                inModel = true
                continue
            }

            if inModel && trimmed.hasPrefix("class ") {
                let name = trimmed
                    .replacingOccurrences(of: "class ", with: "")
                    .components(separatedBy: ":").first?
                    .components(separatedBy: "{").first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                currentClass = name
                attrs = []
                rels = []
                continue
            }

            if currentClass != nil {
                if trimmed == "}" {
                    if let cls = currentClass {
                        entities.append(SchemaEntity(
                            id: cls, name: cls, attributes: attrs,
                            relationships: rels, source: .swiftData
                        ))
                    }
                    currentClass = nil
                    inModel = false
                    continue
                }

                // Parse var declarations
                if trimmed.hasPrefix("var ") || trimmed.hasPrefix("@Relationship") {
                    if trimmed.contains("@Relationship") {
                        // Next line should be the var
                        continue
                    }

                    let varLine = trimmed.replacingOccurrences(of: "var ", with: "")
                    let parts = varLine.components(separatedBy: ":")
                    guard parts.count >= 2 else { continue }

                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    var type = parts[1]
                        .components(separatedBy: "=").first?
                        .components(separatedBy: "{").first?
                        .trimmingCharacters(in: .whitespaces) ?? ""

                    let isOptional = type.hasSuffix("?")
                    type = type.replacingOccurrences(of: "?", with: "")

                    // Check if it's a relationship (array or reference to another model)
                    if type.hasPrefix("[") || type.hasPrefix("Array<") {
                        let dest = type
                            .replacingOccurrences(of: "[", with: "")
                            .replacingOccurrences(of: "]", with: "")
                            .replacingOccurrences(of: "Array<", with: "")
                            .replacingOccurrences(of: ">", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        rels.append(SchemaRelationship(
                            id: "\(currentClass ?? "").\(name)",
                            name: name, destination: dest,
                            isToMany: true, inverse: nil
                        ))
                    } else {
                        attrs.append(SchemaAttribute(
                            id: "\(currentClass ?? "").\(name)",
                            name: name, type: type,
                            isOptional: isOptional, defaultValue: nil
                        ))
                    }
                }
            }
        }

        return entities
    }

    nonisolated private static func parseCoreDataModel(at path: String) -> [SchemaEntity] {
        // Find the current version's .xcdatamodel
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        guard let modelDir = contents.first(where: { $0.hasSuffix(".xcdatamodel") }) else { return [] }

        let modelPath = (path as NSString).appendingPathComponent(modelDir)
        let contentsPath = (modelPath as NSString).appendingPathComponent("contents")
        guard let data = fm.contents(atPath: contentsPath),
              let content = String(data: data, encoding: .utf8) else { return [] }

        // Simple XML parsing for entities
        var entities: [SchemaEntity] = []
        let entityPattern = #"<entity name="(\w+)""#
        let attrPattern = #"<attribute name="(\w+)" optional="(YES|NO)" attributeType="(\w+)""#
        let relPattern = #"<relationship name="(\w+)" .* destinationEntity="(\w+)""#

        if let regex = try? NSRegularExpression(pattern: entityPattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: content) {
                    let name = String(content[nameRange])
                    entities.append(SchemaEntity(
                        id: name, name: name, attributes: [],
                        relationships: [], source: .coreData
                    ))
                }
            }
        }

        return entities
    }
}

// MARK: - Schema Editor Panel

struct SchemaEditorPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = SchemaService()
    @State private var selectedEntity: String?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Data Schema")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                Spacer()

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
            } else if service.entities.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(service.entities) { entity in
                            EntityCard(entity: entity, isSelected: selectedEntity == entity.id)
                                .onTapGesture { selectedEntity = entity.id }
                        }
                    }
                    .padding(Spacing.lg)
                }

                // Migration suggestions
                if !service.migrationSuggestions.isEmpty {
                    Rectangle()
                        .fill(themeManager.palette.borderSubtle)
                        .frame(height: Border.thin)

                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Migration Notes")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textSecondary)

                        ForEach(service.migrationSuggestions) { suggestion in
                            HStack(spacing: Spacing.md) {
                                Image(systemName: suggestion.icon)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(suggestion.color)
                                Text(suggestion.title)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(themeManager.palette.textPrimary)
                            }
                        }
                    }
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgCard)
                }
            }
        }
        .background(themeManager.palette.bgDark)
        .onAppear { service.setDirectory(viewModel.workingDirectory) }
        .onChange(of: viewModel.workingDirectory) { _, newDir in
            service.setDirectory(newDir)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("No data models found")
                .font(Typography.bodySmallMedium)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Add @Model classes or .xcdatamodeld")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Entity Card

struct EntityCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let entity: SchemaEntity
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack(spacing: Spacing.md) {
                Image(systemName: entity.source == .swiftData ? "swift" : "cylinder")
                    .font(Typography.bodySmall)
                    .foregroundColor(entity.source == .swiftData ? Color(red: 1.0, green: 0.45, blue: 0.25) : Color(red: 0.3, green: 0.6, blue: 1.0))

                Text(entity.name)
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text(entity.source == .swiftData ? "@Model" : "Core Data")
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, 1)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(Capsule())

                Spacer()
            }

            // Attributes
            if !entity.attributes.isEmpty {
                ForEach(entity.attributes) { attr in
                    HStack(spacing: Spacing.md) {
                        Circle()
                            .fill(Color(red: 0.3, green: 0.8, blue: 0.5))
                            .frame(width: 5, height: 5)

                        Text(attr.name)
                            .font(Typography.captionSmallMedium)
                            .foregroundColor(themeManager.palette.textPrimary)

                        Text(attr.type + (attr.isOptional ? "?" : ""))
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.textMuted)

                        Spacer()
                    }
                    .padding(.leading, Spacing.xl)
                }
            }

            // Relationships
            if !entity.relationships.isEmpty {
                ForEach(entity.relationships) { rel in
                    HStack(spacing: Spacing.md) {
                        Image(systemName: rel.isToMany ? "arrow.right.arrow.left" : "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(red: 0.3, green: 0.6, blue: 1.0))
                            .frame(width: 12)

                        Text(rel.name)
                            .font(Typography.captionSmallMedium)
                            .foregroundColor(themeManager.palette.textPrimary)

                        Text("→ \(rel.destination)\(rel.isToMany ? " (to-many)" : "")")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)

                        Spacer()
                    }
                    .padding(.leading, Spacing.xl)
                }
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgElevated.opacity(isSelected ? 0.8 : 0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderSubtle, lineWidth: isSelected ? Border.medium : Border.hairline)
        )
    }
}
