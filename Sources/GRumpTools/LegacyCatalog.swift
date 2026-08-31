import Foundation
import GRumpCore

/// Converts the historical schemas once at the package boundary. The resulting
/// public catalog is fully typed; there is no second MCP schema table.
public enum BuiltinToolCatalog {
    public static let definitions: [ToolDefinition] = ToolDefinitions.allTools.compactMap(convert)

    public static var snapshotDigest: String {
        let fields: [JSONValue] = definitions.sorted { $0.name < $1.name }.map {
            ["name": .string($0.name), "description": .string($0.description), "schema": $0.inputSchema,
             "risk": .string($0.annotations.riskLevel.rawValue), "pack": .string($0.pack)]
        }
        guard let data = try? JSONValue.array(fields).encoded() else { return "invalid" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }

    public static func definition(named name: String) -> ToolDefinition? { definitions.first { $0.name == name } }

    private static func convert(_ legacy: [String: Any]) -> ToolDefinition? {
        guard let function = legacy["function"] as? [String: Any],
              let name = function["name"] as? String,
              let description = function["description"] as? String,
              let parameters = function["parameters"],
              let schema = jsonValue(parameters) else { return nil }
        let pack = packName(for: name)
        let risk = riskLevel(for: name, pack: pack)
        let availability: CapabilityAvailability
        if pack == "apple" {
            #if os(macOS)
            availability = .available
            #else
            availability = .unavailable(code: "unsupported_platform", reason: "This capability requires macOS", platform: "macOS")
            #endif
        } else { availability = .available }
        return ToolDefinition(
            name: name, description: description, inputSchema: schema,
            annotations: ToolAnnotations(readOnlyHint: risk == .read, destructiveHint: risk == .destructive,
                                         idempotentHint: risk == .read, openWorldHint: risk == .network,
                                         riskLevel: risk),
            pack: pack, availability: availability
        )
    }

    private static func jsonValue(_ value: Any) -> JSONValue? {
        guard JSONSerialization.isValidJSONObject(["value": value]),
              let data = try? JSONSerialization.data(withJSONObject: ["value": value]),
              let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        return decoded["value"]
    }

    private static func packName(for name: String) -> String {
        let category = ToolDefinitions.ToolCategory.category(for: name)
        switch category {
        case .file: return "workspace"
        case .shell, .clipboard, .screen, .image, .media, .apple: return isAppleTool(name) ? "apple" : "shell"
        case .web, .network, .browser: return "web"
        case .code: return "build"
        case .git: return "git"
        case .database: return "database"
        case .docker: return "containers"
        case .cloud: return "cloud"
        case .ai: return "agent"
        case .apiDevOps: return name.hasPrefix("docker_") ? "containers" : "web"
        case .utilities: return utilityPack(name)
        }
    }

    private static func utilityPack(_ name: String) -> String {
        if ["record_lesson", "remember_tool", "reflect", "propose_skill", "add_goal"].contains(name) { return "learning" }
        if name == "update_plan" { return "agent" }
        return "workspace"
    }

    private static func isAppleTool(_ name: String) -> Bool {
        let names: Set<String> = ["clipboard_read", "clipboard_write", "open_url", "open_app", "system_notify",
            "screen_snapshot", "screen_record", "camera_snap", "window_list", "window_snapshot", "spotlight_search",
            "keychain_read", "keychain_store", "calendar_events", "reminders_list", "contacts_search", "speech_transcribe",
            "ocr_extract", "image_classify", "shortcuts_run", "system_appearance", "xcodebuild", "xcrun_simctl",
            "swift_format", "swift_lint", "pdf_extract", "tts_speak", "qr_generate", "bonjour_discover", "apple_docs_search",
            "lsp_diagnostics", "accessibility_audit", "localization_audit", "app_store_checklist"]
        return names.contains(name)
    }

    private static func riskLevel(for name: String, pack: String) -> ToolRiskLevel {
        let destructive: Set<String> = ["delete_file", "git_reset", "docker_compose_down", "kill_process"]
        let credentials: Set<String> = ["keychain_read", "keychain_store", "read_env_file", "write_env_file"]
        let writes: Set<String> = ["write_file", "edit_file", "create_file", "move_file", "copy_file", "find_and_replace",
            "append_file", "create_directory", "compress_files", "extract_archive", "backup_file", "git_add", "git_commit",
            "git_stash", "git_checkout", "npm_install", "pip_install", "cargo_add", "kubectl_apply", "docker_build",
            "docker_run", "docker_compose_up", "vercel_deploy", "netlify_deploy", "fly_deploy", "add_goal",
            "record_lesson", "remember", "propose_skill", "update_plan", "image_convert", "image_resize"]
        let shell: Set<String> = ["run_command", "run_build", "run_tests", "run_linter", "run_format", "type_check", "spm_resolve", "xcodebuild", "xcrun_simctl", "swift_format", "swift_lint", "system_run", "run_background"]
        let network: Set<String> = ["git_push", "git_pull", "npm_install", "pip_install", "cargo_add", "ping_host", "resolve_dns", "browser_open", "browser_evaluate", "browser_screenshot", "websocket_send", "port_scan", "ssl_check", "generate_embeddings"]
        if destructive.contains(name) { return .destructive }
        if credentials.contains(name) { return .credentials }
        if writes.contains(name) { return .write }
        if shell.contains(name) || name == "system_run" { return .shell }
        if network.contains(name) { return .network }
        if ["web", "cloud", "containers"].contains(pack) { return .network }
        return .read
    }
}

public struct CatalogPlaceholderProvider: ToolProvider {
    public let identifier = "builtin-catalog"
    private let implementedNames: Set<String>
    public init(excluding implementedNames: Set<String> = []) { self.implementedNames = implementedNames }
    public var tools: [RegisteredTool] {
        BuiltinToolCatalog.definitions.filter { !implementedNames.contains($0.name) }.map { definition in
            let unavailable = ToolDefinition(
                name: definition.name, description: definition.description, inputSchema: definition.inputSchema,
                outputSchema: definition.outputSchema, annotations: definition.annotations, pack: definition.pack,
                availability: .unavailable(code: "provider_not_installed", reason: "No provider for this capability is installed in this host", platform: nil)
            )
            return RegisteredTool(definition: unavailable) { invocation, _ in
                switch definition.availability {
                case .available:
                    throw ToolError(code: .unavailable, message: "Tool '\(definition.name)' is discoverable but its provider is not installed")
                case .unavailable(_, let reason, _):
                    throw ToolError(code: .unavailable, message: reason)
                }
            }
        }
    }
}
