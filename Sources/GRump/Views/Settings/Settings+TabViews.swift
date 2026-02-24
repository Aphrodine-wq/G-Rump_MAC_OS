import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Settings Tab Content Views
// Extracted from SettingsView.swift for maintainability.

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

    // MARK: - Notifications

    var notificationsSection: some View {
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
        if let url = URL(string: "https://grump.app/releases") {
            NSWorkspace.shared.open(url)
        }
        #else
        if let url = URL(string: "https://grump.app/releases") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Tools

    var toolsSection: some View {
        settingsCard {
            HStack(spacing: 0) {
                List(selection: $selectedToolCategory) {
                    ForEach(ToolDefinitions.ToolCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: toolCategoryIcon(cat))
                            .tag(cat)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(themeManager.palette.bgSidebar)
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 180)

                Rectangle()
                    .fill(themeManager.palette.borderSubtle)
                    .frame(width: 1)

                VStack(alignment: .leading, spacing: Spacing.xl) {
                    sectionTitle("Active Tools", icon: "wrench.and.screwdriver.fill", accent: themeManager.accentColor)
                    Toggle("Compact tool results", isOn: $compactToolResults)
                    HStack(spacing: Spacing.md) {
                        Button("Enable All") {
                            toolsDenylist = []
                            ToolsSettingsStorage.saveDenylist([])
                        }
                        .font(Typography.captionSmallSemibold)
                        Button("Disable All") {
                            toolsDenylist = Set(ToolDefinitions.toolDisplayInfo.map(\.name))
                            ToolsSettingsStorage.saveDenylist(toolsDenylist)
                        }
                        .font(Typography.captionSmallSemibold)
                    }
                    ScrollView {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(ToolDefinitions.toolsByCategory(selectedToolCategory), id: \.name) { tool in
                                HStack(spacing: Spacing.md) {
                                    Image(systemName: tool.icon)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                                        .frame(width: 20, alignment: .center)
                                    Text(tool.name)
                                        .font(Typography.codeSmall)
                                        .foregroundColor(.textSecondary)
                                    Spacer()
                                    Toggle("", isOn: toolEnabledBinding(tool.name))
                                        .labelsHidden()
                                }
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .background(themeManager.palette.bgInput)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                toolsDenylist = ToolsSettingsStorage.loadDenylist()
            }
        }
    }

    func toolCategoryIcon(_ cat: ToolDefinitions.ToolCategory) -> String {
        switch cat {
        case .file: return "folder"
        case .shell: return "terminal"
        case .clipboard: return "doc.on.clipboard"
        case .screen: return "rectangle.dashed.badge.record"
        case .web: return "globe"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .git: return "vault"
        case .database: return "cylinder.split.1x2"
        case .image: return "photo"
        case .apiDevOps: return "arrow.triangle.2.circlepath"
        case .docker: return "shippingbox.fill"
        case .browser: return "safari"
        case .ai: return "brain"
        case .cloud: return "icloud.and.arrow.up"
        case .apple: return "apple.logo"
        case .media: return "play.rectangle.fill"
        case .network: return "network"
        case .utilities: return "wrench.and.screwdriver"
        }
    }

    func toolEnabledBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !toolsDenylist.contains(name) },
            set: { enabled in
                var next = toolsDenylist
                if enabled {
                    next.remove(name)
                } else {
                    next.insert(name)
                }
                toolsDenylist = next
                ToolsSettingsStorage.saveDenylist(next)
            }
        )
    }

    // MARK: - MCP Servers

    var mcpSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("MCP Servers", icon: "cylinder.split.1x2.fill", accent: themeManager.accentColor)
                Text("Add external Model Context Protocol servers to give the agent access to their tools. Tools are prefixed with mcp_<serverId>_")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
                Text("Some servers require your own credentials (for example GitHub token, Brave API key, Slack token, database URLs). Add those in your shell environment before testing.")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
                if mcpServers.isEmpty {
                    Text("No MCP servers configured. Add one to extend the agent with external tools.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                        .padding(.vertical, Spacing.lg)
                } else {
                    ForEach(mcpServers) { server in
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.lg) {
                                Toggle("", isOn: Binding(
                                    get: { server.enabled },
                                    set: { enabled in
                                        var list = mcpServers
                                        if let idx = list.firstIndex(where: { $0.id == server.id }) {
                                            list[idx].enabled = enabled
                                            MCPServerConfigStorage.save(list)
                                            mcpServers = MCPServerConfigStorage.load()
                                        }
                                    }
                                ))
                                .labelsHidden()
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(server.name)
                                        .font(Typography.bodySmallSemibold)
                                        .foregroundColor(.textPrimary)
                                    Text(server.id)
                                        .font(Typography.codeSmall)
                                        .foregroundColor(.textMuted)
                                }
                                Spacer()
                                Button {
                                    Task { await testMCPServer(server) }
                                } label: {
                                    if mcpTestingServerIDs.contains(server.id) {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Text("Test")
                                            .font(Typography.captionSmallSemibold)
                                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(mcpTestingServerIDs.contains(server.id))
                                Button(action: { mcpEditServer = server }) {
                                    Image(systemName: "pencil")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textMuted)
                                }
                                .buttonStyle(.plain)
                                Button(role: .destructive, action: {
                                    mcpServers = mcpServers.filter { $0.id != server.id }
                                    mcpServerTestMessages.removeValue(forKey: server.id)
                                    MCPServerConfigStorage.save(mcpServers)
                                }) {
                                    Image(systemName: "trash")
                                        .font(Typography.captionSmall)
                                }
                                .buttonStyle(.plain)
                            }

                            if let status = mcpServerTestMessages[server.id] {
                                Text(status)
                                    .font(Typography.micro)
                                    .foregroundColor(status.hasPrefix("OK:") ? .accentGreen : .textMuted)
                                    .padding(.leading, Spacing.colossal)
                            }
                        }
                        .padding(Spacing.lg)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    }
                }
                if !MCPServerPreset.all.filter({ !Set(mcpServers.map(\.id)).contains($0.id) }).isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Quick add")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textSecondary)
                        ForEach(MCPServerPreset.all.filter { !Set(mcpServers.map(\.id)).contains($0.id) }) { preset in
                            HStack(spacing: Spacing.lg) {
                                Image(systemName: preset.icon)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                                    .frame(width: 24, alignment: .center)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(Typography.bodySmallSemibold)
                                        .foregroundColor(.textPrimary)
                                    Text(preset.description)
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textMuted)
                                    if let hint = mcpCredentialHint(for: preset.id) {
                                        Text(hint)
                                            .font(Typography.micro)
                                            .foregroundColor(.textMuted)
                                    }
                                }
                                Spacer()
                                Button("Add") {
                                    var list = MCPServerConfigStorage.load()
                                    list.append(preset.toConfig())
                                    MCPServerConfigStorage.save(list)
                                    mcpServers = list
                                }
                                .font(Typography.captionSmallSemibold)
                                .buttonStyle(.borderedProminent)
                                .tint(themeManager.palette.effectiveAccent)
                            }
                            .padding(Spacing.lg)
                            .background(themeManager.palette.bgInput)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                        }
                    }
                }

                Button(action: { mcpShowAddSheet = true }) {
                    Label("Add MCP Server", systemImage: "plus.circle.fill")
                        .font(Typography.bodySmallMedium)
                }
                .buttonStyle(.borderedProminent)
                .tint(themeManager.palette.effectiveAccent)
            }
            .onAppear {
                mcpServers = MCPServerConfigStorage.load()
            }
            .onChange(of: mcpShowAddSheet) { _, showing in
                if !showing { mcpServers = MCPServerConfigStorage.load() }
            }
            .sheet(isPresented: $mcpShowAddSheet) {
                MCPAddServerSheet(
                    onSave: { cfg in
                        var list = MCPServerConfigStorage.load()
                        list.append(cfg)
                        MCPServerConfigStorage.save(list)
                        mcpServers = list
                        mcpShowAddSheet = false
                    },
                    onDismiss: { mcpShowAddSheet = false }
                )
            }
            .sheet(item: $mcpEditServer) { server in
                MCPEditServerSheet(
                    server: server,
                    onSave: { updated in
                        var list = MCPServerConfigStorage.load()
                        if let idx = list.firstIndex(where: { $0.id == updated.id }) {
                            list[idx] = updated
                            MCPServerConfigStorage.save(list)
                            mcpServers = list
                        }
                        mcpEditServer = nil
                    },
                    onDismiss: { mcpEditServer = nil }
                )
            }
        }
    }

    // MARK: - Data (Export / Import)

    var dataSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Export & Import", icon: "square.and.arrow.up", accent: themeManager.accentColor)
                #if os(macOS)
                if let exportJSON = onExportJSON, let exportMD = onExportMarkdown, let importConv = onImport {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("Export conversations")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textSecondary)
                        HStack(spacing: Spacing.md) {
                            Button(action: exportJSON) {
                                Label("Export JSON…", systemImage: "doc.text")
                                    .font(Typography.bodySmallMedium)
                            }
                            .buttonStyle(.bordered)
                            Button(action: { exportMD() }) {
                                Label("Export Markdown…", systemImage: "doc.plaintext")
                                    .font(Typography.bodySmallMedium)
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Import conversations from a JSON file.")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textSecondary)
                        Button(action: importConv) {
                            Label("Import…", systemImage: "square.and.arrow.down")
                                .font(Typography.bodySmallMedium)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Export and import are available when opened from the main window.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                }
                #else
                Text("Export and import are available on macOS.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                #endif
            }
        }
    }

    // MARK: - Project Memory

    var memorySection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Project Memory", icon: "brain.head.profile", accent: themeManager.accentColor)
                Text("Stores conversation context in the project directory and injects relevant past memories into the agent prompt for cross-session awareness.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)

                Toggle("Enable Project Memory", isOn: $projectMemoryEnabled)

                if projectMemoryEnabled {
                    Divider()

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Toggle("Semantic Memory (On-Device RAG)", isOn: $semanticMemoryEnabled)
                            .font(Typography.bodySmall)
                        Text("Uses Apple's NaturalLanguage framework to embed memories as vectors and retrieve only the most relevant ones via cosine similarity. Fully on-device — no API calls, works offline.")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }

                    if workingDirectory.isEmpty {
                        Text("Set a working directory in Workspace to store memory.")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    } else {
                        HStack(spacing: Spacing.lg) {
                            VStack(alignment: .leading, spacing: 2) {
                                if memoryCountLoading {
                                    Text("Counting…")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                } else {
                                    Text("\(memoryEntryCount) plain-text entries")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                    Text("\(semanticMemoryCount) semantic vectors")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            Spacer()
                            Button("Clear all") {
                                let dir = workingDirectory
                                Task.detached(priority: .userInitiated) {
                                    MemoryStore(baseDirectory: dir).clear()
                                    SemanticMemoryStore(baseDirectory: dir).clear()
                                    await MainActor.run {
                                        memoryEntryCount = 0
                                        semanticMemoryCount = 0
                                    }
                                }
                            }
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                        }
                    }
                }
            }
            .onAppear {
                refreshMemoryCount()
            }
            .onChange(of: workingDirectory) { _, _ in
                refreshMemoryCount()
            }
        }
    }

    func refreshMemoryCount() {
        if workingDirectory.isEmpty {
            memoryEntryCount = 0
            semanticMemoryCount = 0
            memoryCountLoading = false
            return
        }
        memoryCountLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let count = MemoryStore(baseDirectory: dir).count()
            let semanticCount = SemanticMemoryStore(baseDirectory: dir).count()
            await MainActor.run {
                memoryEntryCount = count
                semanticMemoryCount = semanticCount
                memoryCountLoading = false
            }
        }
    }

    #if os(macOS)
    // MARK: - Security (Exec approvals)

    var securitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
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
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    sectionTitle("Commands This Session", icon: "list.bullet.rectangle", accent: themeManager.accentColor)
                    Text("system_run attempts this session — allowed and denied. Helps you audit what the agent tried to run.")
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
        .onAppear {
            execConfig = ExecApprovalsStorage.load()
        }
    }
    #endif

    // MARK: - About

    var aboutSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(spacing: Spacing.xxl) {
                    FrownyFaceLogo(size: 36)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("G-Rump")
                            .font(Typography.sidebarTitle)
                            .foregroundColor(.textPrimary)
                        Text("AI coding agent with file system, shell, and system control")
                            .font(Typography.caption)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                }
                HStack(spacing: Spacing.lg) {
                    Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(Typography.codeSmall)
                        .foregroundColor(.textMuted)
                    if let url = URL(string: "https://grump.app") {
                        Link(destination: url) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "arrow.up.right.square")
                                Text("GitHub")
                                    .font(Typography.captionSmallMedium)
                            }
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                    }
                }
                if let onRestart = onRestartOnboarding {
                    Button(action: onRestart) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Restart onboarding")
                        }
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.md)
                        .background(themeManager.palette.effectiveAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Skills (Settings Tab)

    var skillsSettingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    sectionTitle("Skills", icon: "brain.head.profile", accent: themeManager.accentColor)
                    Text("Skills teach the agent specific workflows via SKILL.md files. Toggle skills on/off to control which are injected into the system prompt.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)

                    if settingsSkills.isEmpty {
                        VStack(spacing: Spacing.lg) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 32))
                                .foregroundColor(.textMuted)
                            Text("No skills yet")
                                .font(Typography.bodySmallSemibold)
                                .foregroundColor(.textPrimary)
                            Text("Add SKILL.md files to ~/.grump/skills/ (global) or .grump/skills/ (project).")
                                .font(Typography.captionSmall)
                                .foregroundColor(.textMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.xl)
                    } else {
                        let builtIn = settingsSkills.filter { $0.isBuiltIn }
                        let userAdded = settingsSkills.filter { !$0.isBuiltIn }

                        if !builtIn.isEmpty {
                            Text("Built-in")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(.textSecondary)
                            ForEach(builtIn) { skill in
                                settingsSkillRow(skill)
                            }
                        }
                        if !userAdded.isEmpty {
                            Text("User-added")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(.textSecondary)
                                .padding(.top, builtIn.isEmpty ? 0 : Spacing.md)
                            ForEach(userAdded) { skill in
                                settingsSkillRow(skill)
                            }
                        }
                    }

                    Button(action: { settingsShowAddSkillSheet = true }) {
                        Label("Add Skill", systemImage: "plus.circle.fill")
                            .font(Typography.bodySmallMedium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.palette.effectiveAccent)
                }
            }
        }
        .onAppear {
            settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
            settingsSkillEnabledIds = SkillsSettingsStorage.loadAllowlist()
        }
        .sheet(isPresented: $settingsShowAddSkillSheet) {
            AddSkillSheet(
                workingDirectory: workingDirectory,
                onCreated: {
                    settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
                    settingsShowAddSkillSheet = false
                },
                onCancel: { settingsShowAddSkillSheet = false }
            )
        }
        .sheet(item: $settingsSkillToEdit) { skill in
            EditSkillSheet(
                skill: skill,
                onSaved: {
                    settingsSkills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
                    settingsSkillToEdit = nil
                },
                onCancel: { settingsSkillToEdit = nil }
            )
            .environmentObject(themeManager)
        }
    }

    func settingsSkillRow(_ skill: Skill) -> some View {
        HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text(skill.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.textPrimary)
                    if skill.isBuiltIn {
                        Text("Built-in")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.effectiveAccent.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                        .lineLimit(2)
                }
                Text(skill.scope == .global ? "Global" : "Project")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }
            Spacer()
            if !skill.isBuiltIn {
                Button(action: { settingsSkillToEdit = skill }) {
                    Image(systemName: "pencil")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
                .buttonStyle(.plain)
            }
            Toggle("", isOn: Binding(
                get: { settingsSkillEnabledIds.contains(skill.id) },
                set: { enabled in
                    if enabled {
                        settingsSkillEnabledIds.insert(skill.id)
                    } else {
                        settingsSkillEnabledIds.remove(skill.id)
                    }
                    SkillsSettingsStorage.saveAllowlist(settingsSkillEnabledIds)
                }
            ))
            .labelsHidden()
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
