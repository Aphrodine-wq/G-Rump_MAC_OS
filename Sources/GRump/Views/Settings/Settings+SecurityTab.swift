import SwiftUI

// MARK: - Security Settings Tab View (macOS only)
// Contains: securitySection (Exec approvals, Commands history, Biometric Lock, Permissions)
// Extracted from Settings+TabViews.swift for maintainability.

#if os(macOS)
extension SettingsView {

    var securitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            securityExecCard
            securityHistoryCard
            securityBiometricCard
            securityPermissionsCard
        }
        .onAppear {
            execConfig = ExecApprovalsStorage.load()
        }
    }

    private var securityExecCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Exec approvals", icon: "lock.shield.fill", accent: themeManager.accentColor)
                Text("Controls which commands system_run can execute. Allowlist entries are glob patterns for resolved binary paths.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                Text("Config file: \(ExecApprovalsStorage.fileURL.path)")
                    .font(Typography.codeSmall)
                    .foregroundColor(.textSecondary)
                    .textSelection(.enabled)
                Picker("Default security", selection: Binding(
                    get: { execConfig.security },
                    set: { new in
                        execConfig.security = new
                        ExecApprovalsStorage.save(execConfig)
                    }
                )) {
                    ForEach(ExecSecurityLevel.allCases, id: \.self) { level in
                        Text(level.rawValue.capitalized).tag(level)
                    }
                }
                .pickerStyle(.menu)
                Toggle("Ask on miss (when not in allowlist)", isOn: Binding(
                    get: { execConfig.askOnMiss },
                    set: { new in
                        execConfig.askOnMiss = new
                        ExecApprovalsStorage.save(execConfig)
                    }
                ))
                if !execConfig.allowlist.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack {
                            Text("Allowlist (\(execConfig.allowlist.count))")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Button(action: {
                                execConfig.allowlist.removeAll()
                                ExecApprovalsStorage.save(execConfig)
                            }) {
                                Text("Clear All")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.accentOrange)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(execConfig.allowlist) { entry in
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                                Text(entry.pattern)
                                    .font(Typography.codeSmall)
                                    .foregroundColor(.textPrimary)
                                Text(entry.source)
                                    .font(Typography.micro)
                                    .foregroundColor(.textMuted)
                                Spacer()
                                Button(action: {
                                    execConfig.allowlist.removeAll { $0.pattern == entry.pattern }
                                    ExecApprovalsStorage.save(execConfig)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Remove from allowlist")
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var securityHistoryCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Commands This Session", icon: "list.bullet.rectangle", accent: themeManager.accentColor)
                Text("system_run attempts this session — allowed and denied.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
                if systemRunHistory.isEmpty {
                    Text("No system_run commands this session.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                        .padding(.vertical, Spacing.lg)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(systemRunHistory.reversed()) { entry in
                            HStack(alignment: .top, spacing: Spacing.md) {
                                Image(systemName: entry.allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(entry.allowed ? Color.accentGreen : Color.accentOrange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.resolvedPath)
                                        .font(Typography.codeSmall)
                                        .foregroundColor(.textPrimary)
                                    Text(entry.command)
                                        .font(Typography.micro)
                                        .foregroundColor(.textMuted)
                                        .lineLimit(2)
                                }
                                Spacer()
                                Text(entry.allowed ? "Allowed" : "Denied")
                                    .font(Typography.micro)
                                    .foregroundColor(entry.allowed ? .accentGreen : .textMuted)
                            }
                            .padding(Spacing.md)
                            .background(themeManager.palette.bgInput.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    private var securityBiometricCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Biometric Lock", icon: "faceid", accent: themeManager.accentColor)
                Text("Require Touch ID or Apple Watch to unlock G-Rump. API keys are stored in the Secure Enclave.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                HStack(spacing: Spacing.xl) {
                    Image(systemName: SecureEnclaveService.shared.isAvailable ? "checkmark.shield.fill" : "xmark.shield.fill")
                        .font(.system(size: 20))
                        .foregroundColor(SecureEnclaveService.shared.isAvailable ? .accentGreen : .textMuted)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(SecureEnclaveService.shared.isAvailable ? "Secure Enclave Available" : "Secure Enclave Unavailable")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text("Biometric: \(SecureEnclaveService.shared.biometricTypeDescription)")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                }
                .padding(Spacing.lg)
                .background(themeManager.palette.bgInput.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private var securityPermissionsCard: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Permissions", icon: "hand.raised.fill", accent: themeManager.accentColor)
                Text("Grant these in System Settings as needed: Notifications (system_notify), Screen Recording (screen_snapshot), Camera (camera_snap), Accessibility (window_snapshot).")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_All") {
                    Link(destination: url) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "gear")
                            Text("Open Privacy & Security")
                                .font(Typography.bodySmallMedium)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                }
            }
        }
    }
}
#endif
