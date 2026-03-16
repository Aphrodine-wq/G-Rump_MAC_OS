import SwiftUI

// MARK: - Presets & Project Settings Tab Views
// Contains: presetsSection, projectSection
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Workflow Presets

    var presetsSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                HStack {
                    sectionTitle("Workflow Presets", icon: "square.stack.3d.up.fill", accent: themeManager.accentColor)
                    Spacer()
                    Button("Refresh") {
                        workflowPresets = WorkflowPresetsStorage.load()
                    }
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                    if appliedPresetName != nil {
                        Button("Clear preset") {
                            onClearPreset?()
                        }
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                    }
                }
                Text("One-click presets for different tasks. Apply to set model, system prompt, and optional tool subset.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)

                ForEach(workflowPresets) { preset in
                    HStack(spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.sm) {
                                Text(preset.name)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(.textPrimary)
                                if appliedPresetName == preset.name {
                                    Text("Active")
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(themeManager.palette.effectiveAccent.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            if let model = preset.model {
                                Text(model.displayName)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            }
                        }
                        Spacer()
                        Button("Apply") {
                            onApplyPreset?(preset)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.palette.effectiveAccent)
                    }
                    .padding(Spacing.lg)
                    .background(themeManager.palette.bgInput.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
            }
            .onAppear {
                workflowPresets = WorkflowPresetsStorage.load()
            }
        }
    }

    // MARK: - Project (Working Directory)

    var projectSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Working Directory", icon: "folder.fill", accent: themeManager.accentColor)

                HStack(spacing: Spacing.xl) {
                    TextField("/path/to/project", text: $workingDirectory)
                        .font(Typography.bodySmall)
                        .fontDesign(.monospaced)
                        .onSubmit { onSetWorkingDirectory(workingDirectory) }
                    #if os(macOS)
                    Button("Browse…") { runDirectoryPicker() }
                        .font(Typography.captionSmallSemibold)
                    #endif
                    if !workingDirectory.isEmpty {
                        Button(action: {
                            workingDirectory = ""
                            onSetWorkingDirectory("")
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.xl)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                Text("Set a project root so the agent uses relative paths. Tools will resolve paths from here.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)

                if !workingDirectory.isEmpty {
                    Text("Project config (.grump/config.json or grump.json) can override model, system prompt, tools, and max steps for this project.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                        .padding(.top, Spacing.sm)
                }
            }
        }
    }
}
