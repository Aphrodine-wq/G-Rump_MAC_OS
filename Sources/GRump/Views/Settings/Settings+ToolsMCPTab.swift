import SwiftUI

// MARK: - Tools & MCP Servers Settings Tab Views
// Contains: toolsSection, toolCategoryIcon, toolEnabledBinding, mcpSection
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Tools

    var toolsSection: some View {
        settingsCard {
            HStack(spacing: 0) {
                Group {
                #if os(macOS)
                List(selection: $selectedToolCategory) {
                    ForEach(ToolDefinitions.ToolCategory.allCases) { cat in
                        Label(cat.rawValue, systemImage: toolCategoryIcon(cat))
                            .tag(cat)
                    }
                }
                #else
                List {
                    ForEach(ToolDefinitions.ToolCategory.allCases) { cat in
                        Button {
                            selectedToolCategory = cat
                        } label: {
                            Label(cat.rawValue, systemImage: toolCategoryIcon(cat))
                        }
                    }
                }
                #endif
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
                HStack {
                    sectionTitle("MCP Servers", icon: "cylinder.split.1x2.fill", accent: themeManager.accentColor)
                    Spacer()
                    Text("\(mcpServers.filter(\.enabled).count) active")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
                Text("Add external Model Context Protocol servers to give the agent access to their tools, resources, and prompts. Connections are persistent and reused across tool calls.")
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
                                    HStack(spacing: Spacing.sm) {
                                        Text(server.id)
                                            .font(Typography.codeSmall)
                                            .foregroundColor(.textMuted)
                                        Text("·")
                                            .foregroundColor(.textMuted)
                                        Text(server.transport.displayName)
                                            .font(Typography.micro)
                                            .foregroundColor(.textMuted)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(themeManager.palette.bgInput.opacity(0.5))
                                            .clipShape(Capsule())
                                    }
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
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: status.hasPrefix("OK:") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(status.hasPrefix("OK:") ? .accentGreen : .orange)
                                    Text(status)
                                        .font(Typography.micro)
                                        .foregroundColor(status.hasPrefix("OK:") ? .accentGreen : .textMuted)
                                }
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
}
