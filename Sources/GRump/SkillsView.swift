import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SkillsView: View {
    let workingDirectory: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager
    @State private var skills: [Skill] = []
    @State private var enabledIds: Set<String> = []
    @State private var showAddSkillSheet = false
    @State private var skillToEdit: Skill?
    @State private var searchText = ""
    @State private var previewSkill: Skill?

    private enum SkillCategory: String, CaseIterable {
        case codeQuality = "Code Quality"
        case appleEcosystem = "Apple Ecosystem"
        case aiMl = "AI / ML"
        case devOps = "DevOps"
        case business = "Business"
        case specialized = "Specialized"
        case other = "Other"

        var icon: String {
            switch self {
            case .codeQuality: return "checkmark.seal"
            case .appleEcosystem: return "apple.logo"
            case .aiMl: return "brain"
            case .devOps: return "server.rack"
            case .business: return "briefcase"
            case .specialized: return "star"
            case .other: return "folder"
            }
        }

        static func category(for baseId: String) -> SkillCategory {
            switch baseId {
            case "code-review", "code-review-pr", "debugging", "refactoring", "testing", "test-generation",
                 "documentation", "technical-writing", "performance", "api-design", "database-design",
                 "accessibility", "security-audit", "writing":
                return .codeQuality
            case "swift-ios", "swiftui-migration", "swiftdata", "async-await", "app-store-prep", "privacy-manifest":
                return .appleEcosystem
            case "coreml-conversion", "prompt-engineering", "mlx-training",
                 "fine-tuning", "rag-pipeline", "llm-observability", "mcp-server", "ai-agent-design":
                return .aiMl
            case "devops", "ci-cd", "docker-deploy", "terraform", "kubernetes", "monorepo", "code-migration",
                 "platform-engineering", "observability", "edge-computing":
                return .devOps
            case "pitch-deck", "technical-dd", "competitive-analysis",
                 "competitive-intel", "product-strategy", "pricing-monetization", "growth-analytics", "cost-optimization":
                return .business
            case "pentesting", "exploit-analysis", "incident-response", "network-forensics", "reverse-engineering":
                return .specialized
            case "combo-architect", "combo-deep-dive", "combo-red-team", "combo-ship-it", "combo-teacher", "combo-war-room":
                return .specialized
            case "regex", "graphql", "rapid-prototype", "plan", "full-stack", "spec", "argue",
                 "react-nextjs", "python-fastapi", "rust-systems", "flutter-dart", "unity-gamedev",
                 "data-science", "aws-serverless", "system-design", "research":
                return .specialized
            default:
                return .other
            }
        }
    }

    private var filteredSkills: [Skill] {
        guard !searchText.isEmpty else { return skills }
        let query = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.baseId.lowercased().contains(query)
        }
    }

    private func builtInByCategory() -> [(SkillCategory, [Skill])] {
        let builtIn = filteredSkills.filter { $0.isBuiltIn }
        let grouped = Dictionary(grouping: builtIn) { SkillCategory.category(for: $0.baseId) }
        return SkillCategory.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                    TextField("Search skills...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Typography.bodySmall)
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)

                if filteredSkills.isEmpty {
                    if searchText.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: Spacing.xl) {
                            Spacer()
                            Text("No skills match \"\(searchText)\"")
                                .font(Typography.bodySmall)
                                .foregroundColor(.textMuted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    List {
                        // Built-in skills grouped by category
                        let categories = builtInByCategory()
                        ForEach(categories, id: \.0) { (category, categorySkills) in
                            Section {
                                ForEach(categorySkills) { skill in
                                    skillRow(skill)
                                }
                            } header: {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: category.icon)
                                        .font(Typography.micro)
                                    Text(category.rawValue)
                                    Spacer()
                                    // Bulk toggle
                                    let allEnabled = categorySkills.allSatisfy { enabledIds.contains($0.id) }
                                    Button(allEnabled ? "Disable All" : "Enable All") {
                                        for skill in categorySkills {
                                            if allEnabled {
                                                enabledIds.remove(skill.id)
                                            } else {
                                                enabledIds.insert(skill.id)
                                            }
                                        }
                                        SkillsSettingsStorage.saveAllowlist(enabledIds)
                                    }
                                    .font(Typography.micro)
                                    .foregroundColor(themeManager.palette.effectiveAccent)
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // User-added skills
                        let userAdded = filteredSkills.filter { !$0.isBuiltIn }
                        if !userAdded.isEmpty {
                            Section {
                                ForEach(userAdded) { skill in
                                    skillRow(skill)
                                }
                            } header: {
                                Text("User-added")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeManager.palette.bgDark)
            .navigationTitle("Skills")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showAddSkillSheet = true }) {
                        Image(systemName: "plus.circle.fill")
                            .font(Typography.bodyMedium)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .help("Add skill")
                }
            }
            .sheet(isPresented: $showAddSkillSheet) {
                AddSkillSheet(
                    workingDirectory: workingDirectory,
                    onCreated: {
                        refreshSkills()
                        showAddSkillSheet = false
                    },
                    onCancel: { showAddSkillSheet = false }
                )
            }
            .sheet(item: $skillToEdit) { skill in
                EditSkillSheet(
                    skill: skill,
                    onSaved: {
                        refreshSkills()
                        skillToEdit = nil
                    },
                    onCancel: { skillToEdit = nil }
                )
                .environmentObject(themeManager)
            }
            .sheet(item: $previewSkill) { skill in
                SkillPreviewSheet(skill: skill)
                    .environmentObject(themeManager)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 500)
        #endif
        .onAppear { refreshSkills() }
        .onChange(of: showAddSkillSheet) { _, isShowing in
            if !isShowing { refreshSkills() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 48))
                .foregroundColor(.textMuted)
            Text("No skills yet")
                .font(Typography.heading3)
                .foregroundColor(.textPrimary)
            Text("Skills teach the agent specific workflows. Add SKILL.md files to ~/.grump/skills/ (global) or .grump/skills/ (project).")
                .font(Typography.bodySmall)
                .foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.huge)
            Button(action: { showAddSkillSheet = true }) {
                Label("Add Skill", systemImage: "plus.circle.fill")
                    .font(Typography.bodySmallSemibold)
            }
            .buttonStyle(.borderedProminent)
            .tint(themeManager.palette.effectiveAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refreshSkills() {
        skills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
        enabledIds = SkillsSettingsStorage.loadAllowlist()
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(skill.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.textPrimary)
                    if skill.isBuiltIn {
                        Text("Built-in")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.effectiveAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                        .lineLimit(2)
                }
                Text(skill.scope == .global ? "Global" : "Project")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            Button(action: { previewSkill = skill }) {
                Image(systemName: "eye")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(.plain)
            .help("Preview skill")
            if !skill.isBuiltIn {
                Button(action: { skillToEdit = skill }) {
                    Image(systemName: "pencil")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
                .help("Edit skill")
            }
            Toggle("", isOn: Binding(
                get: { enabledIds.contains(skill.id) },
                set: { enabled in
                    if enabled {
                        enabledIds.insert(skill.id)
                    } else {
                        enabledIds.remove(skill.id)
                    }
                    SkillsSettingsStorage.saveAllowlist(enabledIds)
                }
            ))
            .labelsHidden()
            #if os(macOS)
            Button(action: { openInFinder(skill) }) {
                Image(systemName: "folder")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
            .help("Open in Finder")
            #endif
        }
        .padding(.vertical, Spacing.sm)
    }

    #if os(macOS)
    private func openInFinder(_ skill: Skill) {
        NSWorkspace.shared.selectFile(
            skill.path.appendingPathComponent("SKILL.md").path,
            inFileViewerRootedAtPath: skill.path.path
        )
    }
    #endif
}

struct AddSkillSheet: View {
    let workingDirectory: String
    let onCreated: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @State private var name = ""
    @State private var description = ""
    @State private var scope: Skill.Scope = .global
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Add Skill")
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .help("Skill name (e.g. code-review)")

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)
                .help("Brief description for when to use this skill")

            Picker("Scope", selection: $scope) {
                Text("Global").tag(Skill.Scope.global)
                Text("Project").tag(Skill.Scope.project)
            }
            .pickerStyle(.segmented)
            .disabled(workingDirectory.isEmpty)
            if workingDirectory.isEmpty {
                Text("Set a project root in Settings → Project to add project skills.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }

            if let err = errorMessage {
                Text(err)
                    .font(Typography.captionSmall)
                    .foregroundColor(.red)
            }

            HStack(spacing: Spacing.lg) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    createSkill()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.huge)
        .frame(minWidth: 360)
        .background(themeManager.palette.bgDark)
    }

    private func createSkill() {
        let id = name.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !id.isEmpty else {
            errorMessage = "Name must contain letters, numbers, or hyphens."
            return
        }
        if scope == .project && workingDirectory.isEmpty {
            errorMessage = "Set a project root first."
            return
        }
        if SkillsStorage.createSkill(id: id, name: name.trimmingCharacters(in: .whitespaces), description: description.trimmingCharacters(in: .whitespaces), scope: scope, workingDirectory: workingDirectory) != nil {
            onCreated()
        } else {
            errorMessage = "Could not create skill. Check permissions."
        }
    }
}

struct EditSkillSheet: View {
    let skill: Skill
    let onSaved: () -> Void
    let onCancel: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    @State private var name: String
    @State private var description: String
    @State private var promptBody: String
    @State private var errorMessage: String?

    init(skill: Skill, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.skill = skill
        self.onSaved = onSaved
        self.onCancel = onCancel
        _name = State(initialValue: skill.name)
        _description = State(initialValue: skill.description)
        _promptBody = State(initialValue: skill.body)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Edit Skill")
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $description)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Prompt")
                    .font(Typography.captionSemibold)
                    .foregroundColor(.textSecondary)

                TextEditor(text: $promptBody)
                    .font(Typography.code)
                    .frame(minHeight: 200)
                    .padding(Spacing.sm)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
                    )
            }

            if let err = errorMessage {
                Text(err)
                    .font(Typography.captionSmall)
                    .foregroundColor(.red)
            }

            HStack(spacing: Spacing.lg) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveChanges() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Spacing.huge)
        .frame(minWidth: 480, minHeight: 400)
        .background(themeManager.palette.bgDark)
    }

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name cannot be empty."
            return
        }
        if SkillsStorage.updateSkill(
            skill,
            newName: trimmedName,
            newDescription: description.trimmingCharacters(in: .whitespaces),
            newBody: promptBody
        ) {
            onSaved()
        } else {
            errorMessage = "Failed to save. Check file permissions."
        }
    }
}

struct SkillPreviewSheet: View {
    let skill: Skill
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(skill.name)
                        .font(Typography.heading2)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: Spacing.md) {
                        if skill.isBuiltIn {
                            Text("Built-in")
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 2)
                                .background(themeManager.palette.effectiveAccent.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        Text(skill.scope == .global ? "Global" : "Project")
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(Typography.bodySmall)
                            .foregroundColor(.textSecondary)
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundColor(themeManager.palette.effectiveAccent)
            }
            .padding(Spacing.xl)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            ScrollView {
                Text(skill.body)
                    .font(Typography.code)
                    .foregroundColor(.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.xl)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(themeManager.palette.bgDark)
    }
}
