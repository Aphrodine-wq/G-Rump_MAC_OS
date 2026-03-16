import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ProfileView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss

    var platformUser: PlatformUser?
    var onRefreshPlatformUser: () async -> Void
    var modelName: String
    var workingDirectory: String
    var appliedPresetName: String?
    var totalConversations: Int
    var totalMessages: Int
    var onOpenSettings: () -> Void

    @State private var displayName: String = ""
    @State private var isEditingDisplayName: Bool = false
    @State private var isSavingProfile: Bool = false
    @State private var profileError: String?
    @State private var usage: PlatformService.PlatformUsage?
    @State private var isLoadingUsage: Bool = false
    @State private var usageUnavailable: Bool = false
    @StateObject private var openClaw = OpenClawService.shared
    @StateObject private var costControl = OpenClawCostControl.shared

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.palette.bgDark.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.huge) {
                        if platformUser != nil {
                            identitySection
                            preferencesSection
                            usageSection
                            openClawSection
                        } else {
                            signedOutSection
                            openClawSection
                        }
                    }
                    .padding(Spacing.huge)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            #if os(macOS)
            .frame(minWidth: 440, minHeight: 480)
            #endif
            .onAppear {
                displayName = platformUser?.displayName ?? ""
                if platformUser != nil {
                    Task { await loadUsage() }
                }
            }
            .onChange(of: platformUser) { _, user in
                displayName = user?.displayName ?? ""
            }
        }
    }

    private var identitySection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Identity", icon: "person.crop.circle.fill")
                HStack(spacing: Spacing.xl) {
                    avatarView
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        if isEditingDisplayName {
                            HStack(spacing: Spacing.md) {
                                TextField("Display name", text: $displayName)
                                    .font(Typography.bodySmall)
                                    .textFieldStyle(.plain)
                                    .padding(Spacing.md)
                                    .background(themeManager.palette.bgInput)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                                Button("Save") {
                                    Task { await saveProfile() }
                                }
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .disabled(isSavingProfile)
                                Button("Cancel") {
                                    displayName = platformUser?.displayName ?? ""
                                    isEditingDisplayName = false
                                }
                                .font(Typography.captionSmall)
                                .foregroundColor(.textMuted)
                            }
                        } else {
                            Text(displayName.isEmpty ? (platformUser?.email ?? "") : displayName)
                                .font(Typography.bodySmallMedium)
                                .foregroundColor(.textPrimary)
                            Button("Edit display name") {
                                isEditingDisplayName = true
                            }
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                        if let err = profileError {
                            Text(err)
                                .font(Typography.captionSmall)
                                .foregroundColor(.red)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private var avatarView: some View {
        avatarContent
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let urlString = platformUser?.avatarUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            }
        } else {
            placeholderAvatar
        }
    }

    private var placeholderAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 64))
            .foregroundColor(themeManager.palette.effectiveAccent.opacity(0.5))
    }

    private var preferencesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Preferences", icon: "gearshape.fill")
                VStack(alignment: .leading, spacing: Spacing.md) {
                    prefRow("Model", value: modelName)
                    prefRow("Working directory", value: workingDirectory.isEmpty ? "Not set" : workingDirectory)
                    if let preset = appliedPresetName, !preset.isEmpty {
                        prefRow("Preset", value: preset)
                    }
                }
                Button(action: onOpenSettings) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "arrow.right.circle")
                        Text("Open Settings")
                            .font(Typography.captionSmallSemibold)
                    }
                    .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func prefRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(Typography.captionSmall)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Spacer()
        }
    }

    private var usageSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Usage", icon: "chart.bar.fill")
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if isLoadingUsage, usage == nil {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(themeManager.palette.effectiveAccent)
                    } else {
                        if let u = usage {
                            usageRow("Credits this month", value: "\(u.creditsThisMonth)")
                            usageRow("Total requests", value: "\(u.requestCount)")
                        } else if usageUnavailable {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.orange)
                                Text("Remote stats unavailable")
                                    .font(Typography.micro)
                                    .foregroundColor(.textMuted)
                            }
                        }
                        usageRow("Conversations", value: "\(totalConversations)")
                        usageRow("Total messages", value: "\(totalMessages)")
                    }
                }
            }
        }
    }

    private func usageRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
            Spacer()
            Text(value)
                .font(Typography.captionSmallSemibold)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - OpenClaw Integration

    private var openClawSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("OpenClaw", icon: "network")

                // Connection status
                HStack(spacing: Spacing.lg) {
                    Circle()
                        .fill(openClawStatusColor)
                        .frame(width: 8, height: 8)
                    Text(openClawStatusText)
                        .font(Typography.bodySmall)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if openClaw.isEnabled {
                        Text(openClaw.connectionState.displayName)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                }

                if openClaw.isEnabled {
                    // Active sessions
                    if !openClaw.activeSessions.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            usageRow("Active sessions", value: "\(openClaw.activeSessions.count)")
                            ForEach(openClaw.activeSessions) { session in
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bubble.left.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(themeManager.palette.effectiveAccent)
                                    Text(session.channel)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                    Spacer()
                                    Text("\(session.messageCount) msgs")
                                        .font(Typography.micro)
                                        .foregroundColor(.textMuted)
                                }
                            }
                        }
                    } else {
                        usageRow("Active sessions", value: "0")
                    }

                    // Daily credit usage
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        usageRow("Credits today", value: costControl.usageSummary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(themeManager.palette.bgInput)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: Radius.xs)
                                    .fill(costControl.dailyUsagePercent > 0.8 ? Color.orange : themeManager.palette.effectiveAccent)
                                    .frame(width: geo.size.width * costControl.dailyUsagePercent, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }

                    // Gateway URL
                    prefRow("Gateway", value: openClaw.gatewayURL)

                    // Quick actions
                    HStack(spacing: Spacing.lg) {
                        if openClaw.connectionState != .connected {
                            Button(action: { openClaw.connect() }) {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bolt.fill")
                                    Text("Connect")
                                        .font(Typography.captionSmallSemibold)
                                }
                                .foregroundColor(themeManager.palette.effectiveAccent)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(action: { openClaw.disconnect() }) {
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: "bolt.slash.fill")
                                    Text("Disconnect")
                                        .font(Typography.captionSmallSemibold)
                                }
                                .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        Button(action: onOpenSettings) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "gearshape")
                                Text("Settings")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("OpenClaw is disabled. Enable it in Settings to receive coding tasks from Slack, Discord, iMessage, and other channels.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Button(action: onOpenSettings) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.right.circle")
                            Text("Enable in Settings")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var openClawStatusColor: Color {
        guard openClaw.isEnabled else { return .gray }
        switch openClaw.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .red
        default: return .gray
        }
    }

    private var openClawStatusText: String {
        guard openClaw.isEnabled else { return "OpenClaw Disabled" }
        switch openClaw.connectionState {
        case .connected: return "Connected to Gateway"
        case .connecting: return "Connecting…"
        case .disconnected: return "Disconnected"
        default: return "Unknown"
        }
    }

    private var signedOutSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                sectionTitle("Profile", icon: "person.crop.circle.fill")
                Text("Sign in to view your profile, update your display name, and see usage stats.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                Button(action: onOpenSettings) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text("Open Settings to sign in")
                            .font(Typography.bodySmallSemibold)
                    }
                    .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadUsage() async {
        guard PlatformService.isLoggedIn else {
            usageUnavailable = true
            return
        }
        isLoadingUsage = true
        defer { isLoadingUsage = false }
        do {
            let u = try await PlatformService.fetchUsage()
            await MainActor.run {
                usage = u
                usageUnavailable = false
            }
        } catch {
            await MainActor.run {
                usage = nil
                usageUnavailable = true
            }
        }
    }

    private func saveProfile() async {
        guard !displayName.isEmpty || platformUser?.displayName != nil else { return }
        isSavingProfile = true
        profileError = nil
        defer { isSavingProfile = false }
        do {
            _ = try await PlatformService.updateProfile(displayName: displayName.isEmpty ? nil : displayName)
            await onRefreshPlatformUser()
            await MainActor.run { isEditingDisplayName = false }
        } catch {
            await MainActor.run {
                profileError = error.localizedDescription
            }
        }
    }
}
