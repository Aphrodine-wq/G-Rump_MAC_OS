import SwiftUI

// MARK: - OpenClaw Settings View
//
// Settings tab for OpenClaw integration.
// Disabled by default — user must explicitly opt in.

struct OpenClawSettingsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var openClaw = OpenClawService.shared
    @StateObject private var costControl = OpenClawCostControl.shared

    @State private var showModelPicker = false
    @State private var gatewayURLInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("OpenClaw Integration")
                        .font(Typography.heading2)
                        .foregroundColor(.textPrimary)
                    Text("Connect G-Rump to OpenClaw's gateway to receive coding tasks from any channel.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
                Spacer()
            }

            // Enable Toggle
            toggleCard

            if openClaw.isEnabled {
                // Connection
                connectionCard

                // Cost Controls
                costControlCard

                // Model Allowlist
                modelAllowlistCard

                // Active Sessions
                if !openClaw.activeSessions.isEmpty {
                    activeSessionsCard
                }

                // Usage
                usageCard
            }
        }
        .padding(Spacing.xl)
        .onAppear {
            gatewayURLInput = openClaw.gatewayURL
        }
    }

    // MARK: - Toggle Card

    private var toggleCard: some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title2)
                .foregroundColor(openClaw.isEnabled ? themeManager.palette.effectiveAccent : .textMuted)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Enable OpenClaw")
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(.textPrimary)
                Text("When enabled, G-Rump registers as a device node on the OpenClaw gateway and can receive tasks from Slack, Discord, iMessage, and other channels.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { openClaw.isEnabled },
                set: { enabled in
                    openClaw.isEnabled = enabled
                    UserDefaults.standard.set(enabled, forKey: "OpenClaw_Enabled")
                    if enabled {
                        openClaw.connect()
                    } else {
                        openClaw.disconnect()
                    }
                }
            ))
            .labelsHidden()
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: openClaw.connectionState.icon)
                    .foregroundColor(openClaw.connectionState == .connected ? .accentGreen : .orange)
                Text(openClaw.connectionState.displayName)
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(.textPrimary)
                Spacer()
                if openClaw.connectionState != .connected {
                    Button("Connect") { openClaw.connect() }
                        .font(Typography.captionSmallSemibold)
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.palette.effectiveAccent)
                } else {
                    Button("Disconnect") { openClaw.disconnect() }
                        .font(Typography.captionSmallSemibold)
                        .buttonStyle(.bordered)
                }
            }

            HStack {
                Text("Gateway URL")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
                TextField("ws://127.0.0.1:18789", text: $gatewayURLInput)
                    .font(Typography.codeSmall)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        openClaw.gatewayURL = gatewayURLInput
                        UserDefaults.standard.set(gatewayURLInput, forKey: "OpenClaw_GatewayURL")
                    }
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    // MARK: - Cost Control Card

    private var costControlCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(.orange)
                Text("Cost Controls")
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(.textPrimary)
            }

            Text("Protect your API credits from excessive OpenClaw usage. These limits apply only to requests coming through OpenClaw.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)

            // Per-session cap
            HStack {
                Text("Per-session credit cap")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("100", value: $costControl.perSessionCreditCap, format: .number)
                    .font(Typography.codeSmall)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            // Per-day cap
            HStack {
                Text("Per-day credit cap")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("500", value: $costControl.perDayCreditCap, format: .number)
                    .font(Typography.codeSmall)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            // Rate limit
            HStack {
                Text("Max requests per minute")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textSecondary)
                Spacer()
                TextField("10", value: $costControl.requestsPerMinute, format: .number)
                    .font(Typography.codeSmall)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }

            // Require own API key
            Toggle(isOn: $costControl.requireOwnAPIKey) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Require own API key")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textSecondary)
                    Text("OpenClaw users must provide their own API keys.")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    // MARK: - Model Allowlist Card

    private var modelAllowlistCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Text("Allowed Models")
                    .font(Typography.bodySmallSemibold)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(costControl.allowedModels.count) selected")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }

            Text("Only these models can be used by OpenClaw sessions. Restricting to free models is safest.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)

            let freeModels: [AIModel] = [.qwen3Coder, .deepseekR1, .deepseekChat, .gemini31Flash]
            let paidModels: [AIModel] = [.claudeSonnet4, .codex53, .gemini31Pro]

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Free models")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
                ForEach(freeModels, id: \.rawValue) { model in
                    modelToggleRow(model)
                }

                Text("Paid models")
                    .font(Typography.micro)
                    .foregroundColor(.orange)
                    .padding(.top, Spacing.sm)
                ForEach(paidModels, id: \.rawValue) { model in
                    modelToggleRow(model)
                }
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    private func modelToggleRow(_ model: AIModel) -> some View {
        Toggle(isOn: Binding(
            get: { costControl.allowedModels.contains(model.rawValue) },
            set: { enabled in
                if enabled {
                    costControl.allowedModels.append(model.rawValue)
                } else {
                    costControl.allowedModels.removeAll { $0 == model.rawValue }
                }
            }
        )) {
            Text(model.displayName)
                .font(Typography.captionSmall)
                .foregroundColor(.textPrimary)
        }
    }

    // MARK: - Active Sessions Card

    private var activeSessionsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Active Sessions")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(.textPrimary)

            ForEach(openClaw.activeSessions) { session in
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.channel)
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textPrimary)
                        Text("User: \(session.user)")
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Text("\(session.messageCount) msgs")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
                .padding(Spacing.md)
                .background(themeManager.palette.bgInput)
                .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
            }
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }

    // MARK: - Usage Card

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Today's Usage")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(.textPrimary)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(themeManager.palette.bgInput)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(costControl.dailyUsagePercent > 0.8 ? Color.red : themeManager.palette.effectiveAccent)
                        .frame(width: geo.size.width * costControl.dailyUsagePercent, height: 8)
                }
            }
            .frame(height: 8)

            Text(costControl.usageSummary)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
    }
}
