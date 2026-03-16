import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Notifications, Shortcuts & Updates Settings Tab Views
// Contains: notificationsSection, shortcutsSection, shortcutRow, updatesSection, openUpdatesURL
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Notifications

    var notificationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("System Notifications", icon: "bell.badge.fill", accent: themeManager.accentColor)
                    Text("When the agent uses the system_notify tool, notifications can appear in Notification Center.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Toggle("Allow system notifications", isOn: $allowSystemNotifications)
                    Toggle("Sound for notifications", isOn: $notificationSoundEnabled)
                    #if os(iOS)
                    Toggle("Haptic feedback", isOn: $hapticFeedbackEnabled)
                    #endif
                    #if os(macOS)
                    Toggle("Show menu bar extra", isOn: $showMenuBarExtra)
                    #endif
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Focus Filters", icon: "moon.fill", accent: themeManager.accentColor)
                    Text("Integrates with macOS Focus modes. When a Focus is active, G-Rump can suppress notifications and adjust behavior automatically.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    HStack(spacing: Spacing.xl) {
                        Image(systemName: FocusFilterService.shared.isFocusModeActive ? "moon.fill" : "moon")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(FocusFilterService.shared.isFocusModeActive ? themeManager.palette.effectiveAccent : .textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(FocusFilterService.shared.isFocusModeActive ? "Focus Active" : "No Focus Active")
                                .font(Typography.bodySmallSemibold)
                                .foregroundColor(.textPrimary)
                            Text(FocusFilterService.shared.isFocusModeActive
                                 ? "Notifications are suppressed per your Focus settings."
                                 : "G-Rump will send notifications normally.")
                                .font(Typography.captionSmall)
                                .foregroundColor(.textMuted)
                        }
                        Spacer()
                        if FocusFilterService.shared.isFocusModeActive {
                            Text("Active")
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, 3)
                                .background(themeManager.palette.effectiveAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(Spacing.lg)
                    .background(themeManager.palette.bgInput.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
            }
        }
    }

    // MARK: - Shortcuts (Keyboard)

    var shortcutsSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Keyboard Shortcuts", icon: "command", accent: themeManager.accentColor)
                Text("These shortcuts are available in the main window.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                VStack(alignment: .leading, spacing: Spacing.md) {
                    shortcutRow("New Chat", "⌘N")
                    shortcutRow("Settings", "⌘,")
                    shortcutRow("Stop generation", "⌘.")
                    shortcutRow("Focus message input", "⌘L")
                    #if os(macOS)
                    shortcutRow("Toggle sidebar", "⌘\\")
                    shortcutRow("Export current as Markdown", "⌘E")
                    #endif
                }
            }
        }
    }

    func shortcutRow(_ action: String, _ keys: String) -> some View {
        HStack(spacing: Spacing.xxl) {
            Text(action)
                .font(Typography.bodySmallMedium)
                .foregroundColor(.textPrimary)
            Spacer()
            Text(keys)
                .font(Typography.codeSmall)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Updates

    var updatesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Updates", icon: "arrow.down.circle.fill", accent: themeManager.accentColor)
                Text("Check for new versions of G-Rump.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                Button(action: openUpdatesURL) {
                    Label("Check for updates", systemImage: "arrow.down.circle")
                        .font(Typography.bodySmallMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.palette.effectiveAccent)
                Toggle("Check for updates on launch", isOn: $checkUpdatesOnLaunch)
            }
        }
    }

    func openUpdatesURL() {
        #if os(macOS)
        // Post notification to trigger Sparkle check from GRumpApp where the service lives
        NotificationCenter.default.post(name: .init("GRumpCheckForUpdates"), object: nil)
        #else
        if let url = URL(string: "https://www.g-rump.com/releases") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
