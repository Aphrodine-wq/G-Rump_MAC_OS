import SwiftUI

// MARK: - Behavior Settings Tab View
// Contains: behaviorSection (System Prompt, Agent, Input, Parallel Agents), routingRow
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Behavior (System Prompt + Agent)

    var behaviorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    HStack {
                        sectionTitle("System Prompt", icon: "text.bubble.fill", accent: themeManager.accentColor)
                        Spacer()
                        Button("Reset to Default") {
                            systemPrompt = GRumpDefaults.defaultSystemPrompt
                        }
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                    }

                    TextEditor(text: $systemPrompt)
                    .font(Typography.code)
                    .frame(minHeight: 160)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Agent", icon: "gearshape.2.fill", accent: themeManager.accentColor)
                    Text("Maximum number of agent steps (tool + reply cycles) per turn. Higher values allow longer autonomous runs.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    HStack(spacing: Spacing.xl) {
                        Text("Max agent steps")
                            .font(Typography.bodySmallMedium)
                            .foregroundColor(.textPrimary)
                        Stepper(value: $maxAgentStepsStorage, in: 5...1000, step: 5) {
                            Text("\(maxAgentStepsStorage)")
                                .font(Typography.bodySmall)
                                .foregroundColor(.textSecondary)
                                .frame(minWidth: 28, alignment: .trailing)
                        }
                        .onChange(of: maxAgentStepsStorage) { _, v in
                            maxAgentStepsStorage = min(1000, max(5, v))
                        }
                        .onAppear {
                            if maxAgentStepsStorage < 5 || maxAgentStepsStorage > 1000 {
                                maxAgentStepsStorage = 200
                            }
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Input", icon: "keyboard", accent: themeManager.accentColor)
                    Toggle("Return to send", isOn: $returnToSendSetting)
                    Text(returnToSendSetting
                         ? "Press Return to send a message. Shift+Return for a new line."
                         : "Press ⌘Return to send a message. Return for a new line.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Parallel Agents", icon: "arrow.triangle.branch", accent: themeManager.accentColor)
                    Text("When enabled, selecting Parallel mode decomposes complex tasks into concurrent sub-agents, each auto-routed to the optimal model for its task type. Results stream inline and are synthesized into a final response.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)

                    Toggle("Enable Parallel Agent Mode", isOn: $parallelAgentsEnabled)

                    if parallelAgentsEnabled {
                        Divider()
                        HStack(spacing: Spacing.xl) {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text("Max concurrent agents")
                                    .font(Typography.bodySmallMedium)
                                    .foregroundColor(.textPrimary)
                                Text("How many sub-agents can run simultaneously per wave.")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            }
                            Spacer()
                            Stepper(value: $parallelAgentsMax, in: 2...5, step: 1) {
                                Text("\(parallelAgentsMax)")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(.textSecondary)
                                    .frame(minWidth: 20, alignment: .trailing)
                            }
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Model routing")
                                .font(Typography.bodySmallMedium)
                                .foregroundColor(.textPrimary)
                            VStack(alignment: .leading, spacing: 4) {
                                routingRow(type: "Reasoning / Planning", model: "DeepSeek R1", icon: "brain")
                                routingRow(type: "File Ops / Search", model: "Gemini 2.5 Flash", icon: "doc.text")
                                routingRow(type: "Code Generation", model: "Qwen3 Coder 480B", icon: "chevron.left.forwardslash.chevron.right")
                                routingRow(type: "Synthesis / Writing", model: "Claude 3.7 Sonnet", icon: "arrow.triangle.merge")
                                routingRow(type: "Web / Research", model: "Gemini 2.5 Flash", icon: "globe")
                            }
                            .padding(Spacing.lg)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    func routingRow(type: String, model: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.textMuted)
                .frame(width: 16)
            Text(type)
                .font(Typography.captionSmall)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(model)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
        }
    }
}
