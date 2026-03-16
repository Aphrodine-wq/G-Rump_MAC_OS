import SwiftUI

// MARK: - Skill Picker View
//
// Compact picker accessible from the chat input area.
// Shows active skills (toggleable), suggested skills based on context,
// skill packs, and a search bar.

struct SkillPickerView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let workingDirectory: String
    let onDismiss: () -> Void

    @State private var skills: [Skill] = []
    @State private var enabledIds: Set<String> = []
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Skills")
                    .font(Typography.heading3)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(enabledIds.count) active")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.lg)

            // Search
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textMuted)
                    .font(.system(size: 12))
                TextField("Search skills...", text: $searchText)
                    .font(Typography.captionSmall)
                    .textFieldStyle(.plain)
            }
            .padding(Spacing.md)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
            .padding(.horizontal, Spacing.lg)

            Divider().padding(.vertical, Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Skill Packs
                    if searchText.isEmpty {
                        packSection
                    }

                    // Active Skills
                    if !activeSkills.isEmpty {
                        skillSection(title: "Active", skills: activeSkills)
                    }

                    // Available Skills
                    if !availableSkills.isEmpty {
                        skillSection(title: "Available", skills: availableSkills)
                    }

                    // Built-in
                    if !builtInSkills.isEmpty && searchText.isEmpty {
                        skillSection(title: "Built-in", skills: builtInSkills)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.lg)
            }
        }
        .frame(width: 320, height: 440)
        .background(themeManager.palette.bgSidebar)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
        .onAppear { reload() }
    }

    // MARK: - Filtered Lists

    private var filteredSkills: [Skill] {
        if searchText.isEmpty { return skills }
        let q = searchText.lowercased()
        return skills.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.baseId.lowercased().contains(q)
        }
    }

    private var activeSkills: [Skill] {
        filteredSkills.filter { enabledIds.contains($0.id) }
    }

    private var availableSkills: [Skill] {
        filteredSkills.filter { !enabledIds.contains($0.id) && !$0.isBuiltIn }
    }

    private var builtInSkills: [Skill] {
        filteredSkills.filter { !enabledIds.contains($0.id) && $0.isBuiltIn }
    }

    // MARK: - Pack Section

    private var packSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Skill Packs")
                .font(Typography.captionSmallSemibold)
                .foregroundColor(.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(SkillPack.builtInPacks) { pack in
                        Button {
                            pack.enable(allSkills: skills)
                            reload()
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: pack.icon)
                                    .font(.system(size: 12))
                                Text(pack.name)
                                    .font(Typography.captionSmallSemibold)
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(themeManager.palette.bgInput)
                            .foregroundColor(.textPrimary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Skill Section

    private func skillSection(title: String, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(Typography.captionSmallSemibold)
                .foregroundColor(.textSecondary)

            ForEach(skills) { skill in
                skillRow(skill)
            }
        }
    }

    private func skillRow(_ skill: Skill) -> some View {
        HStack(spacing: Spacing.md) {
            Button {
                toggleSkill(skill)
            } label: {
                Image(systemName: enabledIds.contains(skill.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(enabledIds.contains(skill.id) ? themeManager.palette.effectiveAccent : .textMuted)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.sm) {
                    Text(skill.name)
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.textPrimary)
                    if skill.isBuiltIn {
                        Text("Built-in")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(themeManager.palette.effectiveAccent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if skill.scope == .project {
                        Text("Project")
                            .font(Typography.micro)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(Spacing.sm)
        .background(enabledIds.contains(skill.id) ? themeManager.palette.effectiveAccent.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    // MARK: - Actions

    private func toggleSkill(_ skill: Skill) {
        SkillsSettingsStorage.toggle(skill.id)
        reload()
    }

    private func reload() {
        skills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
        enabledIds = SkillsSettingsStorage.loadAllowlist()
    }
}
