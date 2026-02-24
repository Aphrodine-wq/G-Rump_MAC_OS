import SwiftUI

struct SoulSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let workingDirectory: String

    @State private var scope: Soul.Scope = .global
    @State private var editorContent: String = ""
    @State private var hasGlobalSoul = false
    @State private var hasProjectSoul = false
    @State private var statusMessage: String?
    @State private var showDeleteConfirm = false
    @State private var showTemplates = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            headerCard
            scopePickerCard
            editorCard
            actionsCard
        }
        .onAppear { loadState() }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(themeManager.palette.effectiveAccent)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("SOUL.md")
                        .font(Typography.heading2)
                        .foregroundColor(.textPrimary)
                    Text("Define your agent's identity, expertise, rules, and tone.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                }
            }

            Text("The soul is injected into every conversation as the foundation layer — before skills, modes, and project context. Global soul applies everywhere. Project soul overrides it per-workspace.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Scope Picker

    private var scopePickerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Picker("Scope", selection: $scope) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "globe")
                    Text("Global")
                }.tag(Soul.Scope.global)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "folder")
                    Text("Project")
                }.tag(Soul.Scope.project)
            }
            .pickerStyle(.segmented)
            .disabled(workingDirectory.isEmpty)
            .onChange(of: scope) { _, _ in loadEditorContent() }

            if workingDirectory.isEmpty && scope == .project {
                Text("Set a project root in Settings → Project to use project-scoped souls.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }

            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(currentSoulExists ? Color.accentGreen : Color.accentOrange)
                    .frame(width: 8, height: 8)
                Text(currentSoulExists ? "\(scope == .global ? "Global" : "Project") soul active" : "No \(scope == .global ? "global" : "project") soul configured")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(currentSoulExists ? .accentGreen : .textMuted)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Editor

    private var wordCount: Int {
        editorContent.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var charCount: Int {
        editorContent.count
    }

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Editor")
                    .font(Typography.captionSemibold)
                    .foregroundColor(.textSecondary)

                Text("\(wordCount) words · \(charCount) chars")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)

                Spacer()

                #if os(macOS)
                Button {
                    importFromFile()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.bordered)
                .help("Import from .md file")

                Button {
                    exportToFile()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.bordered)
                .help("Export to .md file")
                #endif

                Button {
                    showTemplates = true
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "doc.on.doc")
                        Text("Templates")
                    }
                    .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showTemplates) {
                    templatePopover
                }
            }

            TextEditor(text: $editorContent)
                .font(Typography.code)
                .frame(minHeight: 480)
                .padding(Spacing.sm)
                .background(Color.white.opacity(0.001))
                .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
                )
                .scrollContentBackground(.hidden)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.lg) {
                Button {
                    save()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark.circle")
                        Text("Save")
                    }
                    .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(editorContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    editorContent = SoulStorage.defaultSoulContent
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Default")
                    }
                    .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.bordered)

                if currentSoulExists {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(Typography.captionSmallSemibold)
                    }
                    .buttonStyle(.bordered)
                    .alert("Delete SOUL.md?", isPresented: $showDeleteConfirm) {
                        Button("Cancel", role: .cancel) {}
                        Button("Delete", role: .destructive) { deleteSoul() }
                    } message: {
                        Text("This will remove the \(scope == .global ? "global" : "project") SOUL.md file. You can always recreate it.")
                    }
                }

                Spacer()
            }

            if let status = statusMessage {
                Text(status)
                    .font(Typography.captionSmall)
                    .foregroundColor(status.hasPrefix("Saved") ? .accentGreen : .textMuted)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Template Popover

    private var templatePopover: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Soul Templates")
                .font(Typography.heading3)
                .foregroundColor(.textPrimary)

            ForEach(SoulTemplate.allCases, id: \.self) { template in
                Button {
                    editorContent = template.content
                    showTemplates = false
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(template.name)
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text(template.description)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .background(themeManager.palette.bgDark)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.xl)
        .frame(width: 320)
        .background(themeManager.palette.bgInput)
        .environmentObject(themeManager)
    }

    // MARK: - Helpers

    private var currentSoulExists: Bool {
        scope == .global ? hasGlobalSoul : hasProjectSoul
    }

    private func loadState() {
        hasGlobalSoul = SoulStorage.soulExists(scope: .global)
        hasProjectSoul = SoulStorage.soulExists(scope: .project, workingDirectory: workingDirectory)
        loadEditorContent()
    }

    private func loadEditorContent() {
        let content = SoulStorage.rawContent(scope: scope, workingDirectory: workingDirectory)
        editorContent = content ?? SoulStorage.defaultSoulContent
    }

    private func save() {
        let success = SoulStorage.saveSoul(content: editorContent, scope: scope, workingDirectory: workingDirectory)
        if success {
            statusMessage = "Saved \(scope == .global ? "global" : "project") SOUL.md."
            loadState()
        } else {
            statusMessage = "Failed to save. Check file permissions."
        }
    }

    private func deleteSoul() {
        _ = SoulStorage.deleteSoul(scope: scope, workingDirectory: workingDirectory)
        statusMessage = "Deleted \(scope == .global ? "global" : "project") SOUL.md."
        loadState()
    }

    #if os(macOS)
    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import SOUL.md"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if let content = try? String(contentsOf: url, encoding: .utf8) {
                    editorContent = content
                    statusMessage = "Imported from \(url.lastPathComponent)"
                } else {
                    statusMessage = "Failed to read file."
                }
            }
        }
    }

    private func exportToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "SOUL.md"
        panel.title = "Export SOUL.md"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try editorContent.write(to: url, atomically: true, encoding: .utf8)
                    statusMessage = "Exported to \(url.lastPathComponent)"
                } catch {
                    statusMessage = "Failed to export: \(error.localizedDescription)"
                }
            }
        }
    }
    #endif
}

// MARK: - Soul Templates

enum SoulTemplate: String, CaseIterable {
    case standard
    case minimal
    case creative
    case enterprise

    var name: String {
        switch self {
        case .standard: return "Standard (Default)"
        case .minimal: return "Minimal"
        case .creative: return "Creative"
        case .enterprise: return "Enterprise"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Direct, opinionated full-stack engineer. The default G-Rump personality."
        case .minimal: return "Bare-bones. Just the rules, no personality."
        case .creative: return "Playful, experimental, loves pushing boundaries."
        case .enterprise: return "Formal, compliance-aware, documentation-heavy."
        }
    }

    var content: String {
        switch self {
        case .standard:
            return SoulStorage.defaultSoulContent
        case .minimal:
            return """
---
name: Rump
version: 1
---

# Rules

- Be concise. No filler.
- Write tests for all logic.
- Never hardcode secrets.
- Prefer modern language idioms.
- Suggest file splits at 500+ lines.
"""
        case .creative:
            return """
---
name: Rump
version: 1
---

# Identity

You are a creative technologist who sees code as art. You love elegant abstractions, novel architectures, and pushing what's possible. You prototype fast, iterate faster, and aren't afraid to throw away code that doesn't spark joy.

# Expertise

Full-stack generalist with deep love for Swift, Rust, and TypeScript. Obsessed with developer experience, beautiful APIs, and performance.

# Rules

- Favor readability over cleverness, but don't shy from clever when it's genuinely better.
- Prototype first, optimize later.
- Always suggest at least one unconventional approach.
- Tests are documentation. Write them expressively.

# Tone

Enthusiastic, curious, sometimes playfully irreverent. Like a brilliant friend who happens to be a 10x engineer.
"""
        case .enterprise:
            return """
---
name: Rump
version: 1
---

# Identity

You are a senior enterprise architect focused on reliability, compliance, and maintainability. Every decision is documented. Every risk is assessed.

# Expertise

Enterprise Java, .NET, cloud infrastructure (AWS/Azure/GCP), SOC 2 compliance, HIPAA, GDPR, microservices, event-driven architectures.

# Rules

- All changes require clear justification and rollback plan.
- Security review before any external API integration.
- Follow established coding standards strictly.
- Document all architectural decisions as ADRs.
- Error handling is mandatory, not optional.
- Logging must include correlation IDs.

# Tone

Professional, thorough, measured. Like a principal engineer at a Fortune 500 who takes pride in systems that never go down.
"""
        }
    }
}
