// MARK: - Onboarding Step 5: Security & Permissions
//
// Security posture picker with preset cards (Locked-down, Balanced, Permissive).

import SwiftUI

extension OnboardingView {

    // MARK: - Step 5: Security & Permissions

    var stepSecurityPermissions: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Security posture")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Choose how G-Rump handles shell commands and system access. You can change this anytime in Settings.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: Spacing.lg) {
                ForEach(ExecSecurityPreset.allCases) { preset in
                    Button {
                        selectedSecurityPreset = preset
                        #if os(macOS)
                        ExecApprovalsStorage.save(preset.toConfig())
                        #endif
                    } label: {
                        HStack(spacing: Spacing.xl) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(selectedSecurityPreset == preset ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                                .frame(width: 32)

                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(preset.displayName)
                                    .font(Typography.bodySemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                                Text(preset.description)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(themeManager.palette.textSecondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if selectedSecurityPreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(themeManager.palette.effectiveAccent)
                            }
                        }
                        .padding(Spacing.xl)
                        .frame(maxWidth: 440)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(selectedSecurityPreset == preset
                                      ? themeManager.palette.effectiveAccent.opacity(0.1)
                                      : themeManager.palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(selectedSecurityPreset == preset
                                        ? themeManager.palette.effectiveAccent.opacity(0.5)
                                        : themeManager.palette.borderCrisp, lineWidth: Border.thin)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.displayName) security preset")
                    .accessibilityHint(preset.description)
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
    }
}
