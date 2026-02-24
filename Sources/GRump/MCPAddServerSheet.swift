import SwiftUI

struct MCPAddServerSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    var onSave: (MCPServerConfig) -> Void
    var onDismiss: () -> Void

    @State private var serverId = ""
    @State private var serverName = ""
    @State private var transportType = "stdio"
    @State private var stdioCommand = "npx"
    @State private var stdioArgs = "-y @modelcontextprotocol/server-filesystem"
    @State private var httpUrl = "http://localhost:8080"

    private var canSave: Bool {
        let id = serverId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return false }
        if transportType == "stdio" {
            return !stdioCommand.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !httpUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            Text("Add MCP Server")
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)

            TextField("Server ID (e.g. fs, github)", text: $serverId)
                .textFieldStyle(.roundedBorder)
            Text("Short identifier. Used as mcp_<id>_<toolName>. Letters, numbers, underscore only.")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)

            TextField("Display name", text: $serverName)
                .textFieldStyle(.roundedBorder)

            Picker("Transport", selection: $transportType) {
                Text("Stdio (command)").tag("stdio")
                Text("HTTP").tag("http")
            }
            .pickerStyle(.segmented)

            if transportType == "stdio" {
                TextField("Command (e.g. npx)", text: $stdioCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments (e.g. -y @modelcontextprotocol/server-filesystem /path)", text: $stdioArgs)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("URL", text: $httpUrl)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    let id = serverId.trimmingCharacters(in: .whitespaces)
                    let name = serverName.trimmingCharacters(in: .whitespaces).isEmpty ? id : serverName.trimmingCharacters(in: .whitespaces)
                    let transport: MCPServerConfig.Transport
                    if transportType == "stdio" {
                        let cmd = stdioCommand.trimmingCharacters(in: .whitespaces)
                        let argsList = stdioArgs.split(separator: " ").map(String.init)
                        transport = .stdio(command: cmd, args: argsList)
                    } else {
                        transport = .http(url: httpUrl.trimmingCharacters(in: .whitespaces))
                    }
                    onSave(MCPServerConfig(id: id, name: name, enabled: true, transport: transport))
                }
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.colossal)
        .frame(minWidth: 400)
        .background(themeManager.palette.bgDark)
        .environmentObject(themeManager)
    }
}

struct MCPEditServerSheet: View {
    @EnvironmentObject var themeManager: ThemeManager
    let server: MCPServerConfig
    var onSave: (MCPServerConfig) -> Void
    var onDismiss: () -> Void

    @State private var serverName = ""
    @State private var enabled = true
    @State private var transportType = "stdio"
    @State private var stdioCommand = ""
    @State private var stdioArgs = ""
    @State private var httpUrl = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            Text("Edit MCP Server")
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)

            Text("ID: \(server.id)")
                .font(Typography.codeSmall)
                .foregroundColor(.textMuted)

            TextField("Display name", text: $serverName)
                .textFieldStyle(.roundedBorder)

            Toggle("Enabled", isOn: $enabled)

            Picker("Transport", selection: $transportType) {
                Text("Stdio").tag("stdio")
                Text("HTTP").tag("http")
            }
            .pickerStyle(.segmented)

            if transportType == "stdio" {
                TextField("Command", text: $stdioCommand)
                    .textFieldStyle(.roundedBorder)
                TextField("Arguments (space-separated)", text: $stdioArgs)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("URL", text: $httpUrl)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let transport: MCPServerConfig.Transport
                    if transportType == "stdio" {
                        let argsList = stdioArgs.split(separator: " ").map(String.init)
                        transport = .stdio(command: stdioCommand, args: argsList)
                    } else {
                        transport = .http(url: httpUrl)
                    }
                    onSave(MCPServerConfig(
                        id: server.id,
                        name: serverName.isEmpty ? server.id : serverName,
                        enabled: enabled,
                        transport: transport
                    ))
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.colossal)
        .frame(minWidth: 400)
        .background(themeManager.palette.bgDark)
        .onAppear {
            serverName = server.name
            enabled = server.enabled
            switch server.transport {
            case .stdio(let cmd, let args):
                transportType = "stdio"
                stdioCommand = cmd
                stdioArgs = args.joined(separator: " ")
            case .http(let url):
                transportType = "http"
                httpUrl = url
            }
        }
        .environmentObject(themeManager)
    }
}
