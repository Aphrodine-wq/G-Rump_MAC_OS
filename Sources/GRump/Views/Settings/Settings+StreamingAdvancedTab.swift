import SwiftUI

// MARK: - Streaming & Advanced Settings Tab Views
// Contains: streamingSection, advancedSection
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Streaming

    var streamingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Streaming Animation", icon: "waveform", accent: themeManager.accentColor)
                    Text("How assistant responses appear as they stream. Smooth shows content immediately; typewriter reveals character by character.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Picker("Style", selection: Binding(
                        get: { StreamingAnimationStyle(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.streamingAnimationStyle) ?? "smooth") ?? .smooth },
                        set: { UserDefaults.standard.set($0.rawValue, forKey: SettingsKeys.streamingAnimationStyle) }
                    )) {
                        ForEach(StreamingAnimationStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Stream Debounce", icon: "timer", accent: themeManager.accentColor)
                    Text("Delay (ms) before parsing markdown during streaming. Lower = more responsive; higher = less CPU when streaming fast.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Picker("Debounce", selection: Binding(
                        get: { UserDefaults.standard.integer(forKey: SettingsKeys.streamDebounceMs) },
                        set: { UserDefaults.standard.set($0, forKey: SettingsKeys.streamDebounceMs) }
                    )) {
                        Text("0 ms").tag(0)
                        Text("8 ms").tag(8)
                        Text("16 ms").tag(16)
                        Text("33 ms").tag(33)
                    }
                    .pickerStyle(.segmented)
                    .onAppear {
                        if UserDefaults.standard.object(forKey: SettingsKeys.streamDebounceMs) == nil {
                            UserDefaults.standard.set(0, forKey: SettingsKeys.streamDebounceMs)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Advanced

    var advancedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Model Temperature", icon: "thermometer", accent: themeManager.accentColor)
                    Text("Higher = more creative; lower = more deterministic. 0 is best for code.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Picker("Temperature", selection: Binding(
                        get: { UserDefaults.standard.double(forKey: SettingsKeys.modelTemperature) },
                        set: { UserDefaults.standard.set($0, forKey: SettingsKeys.modelTemperature) }
                    )) {
                        Text("0").tag(0.0)
                        Text("0.3").tag(0.3)
                        Text("0.7").tag(0.7)
                    }
                    .pickerStyle(.segmented)
                    .onAppear {
                        if UserDefaults.standard.object(forKey: SettingsKeys.modelTemperature) == nil {
                            UserDefaults.standard.set(0.0, forKey: SettingsKeys.modelTemperature)
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Display", icon: "eye", accent: themeManager.accentColor)
                    Toggle("Show token count in UI", isOn: $showTokenCount)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Auto-scroll", icon: "arrow.down.doc", accent: themeManager.accentColor)
                    Picker("Behavior", selection: Binding(
                        get: { UserDefaults.standard.string(forKey: SettingsKeys.autoScrollBehavior) ?? "always" },
                        set: { UserDefaults.standard.set($0, forKey: SettingsKeys.autoScrollBehavior) }
                    )) {
                        Text("Always").tag("always")
                        Text("Last message").tag("last-message")
                        Text("Manual").tag("manual")
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Ambient Code Awareness", icon: "lightbulb.fill", accent: .orange)
                    Text("Passively watches your project for TODOs, unused imports, missing tests, large files, and security issues. Shows a badge in the top bar when insights are available.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Toggle("Enable Ambient Code Awareness", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "AmbientCodeAwarenessEnabled") },
                        set: { UserDefaults.standard.set($0, forKey: "AmbientCodeAwarenessEnabled") }
                    ))
                }
            }
        }
    }
}
