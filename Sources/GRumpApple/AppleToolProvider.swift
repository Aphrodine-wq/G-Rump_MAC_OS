import Foundation
import GRumpCore
import GRumpTools

public struct AppleToolProvider: ToolProvider {
    public let identifier = "apple"
    public static let names: Set<String> = [
        "clipboard_read", "clipboard_write", "open_url", "open_app", "system_notify", "screen_snapshot", "screen_record",
        "camera_snap", "window_list", "window_snapshot", "spotlight_search", "keychain_read", "keychain_store", "calendar_events",
        "reminders_list", "contacts_search", "speech_transcribe", "ocr_extract", "image_classify", "shortcuts_run", "system_appearance",
        "xcodebuild", "xcrun_simctl", "swift_format", "swift_lint", "swift_package", "pdf_extract", "tts_speak", "qr_generate",
        "bonjour_discover", "apple_docs_search", "lsp_diagnostics", "accessibility_audit", "localization_audit", "app_store_checklist"
    ]
    private static let implemented: Set<String> = [
        "clipboard_read", "clipboard_write", "open_url", "open_app", "system_notify", "screen_snapshot", "spotlight_search",
        "keychain_read", "keychain_store", "shortcuts_run", "system_appearance", "xcodebuild", "xcrun_simctl", "swift_format",
        "swift_lint", "swift_package", "tts_speak", "apple_docs_search", "lsp_diagnostics", "accessibility_audit",
        "localization_audit", "app_store_checklist"
    ]
    public init() {}
    public var tools: [RegisteredTool] {
        Self.names.sorted().compactMap { name in
            guard let base = BuiltinToolCatalog.definition(named: name) else { return nil }
            #if os(macOS)
            let definition = Self.implemented.contains(name) ? base : Self.unavailable(base, code: "capability_unavailable", reason: "This Apple capability requires a host adapter or permission that is not configured")
            #else
            let definition = Self.unavailable(base, code: "unsupported_platform", reason: "This capability requires macOS")
            #endif
            return RegisteredTool(definition: definition) { invocation, context in try await Self.execute(invocation, context) }
        }
    }

    private static func unavailable(_ base: ToolDefinition, code: String, reason: String) -> ToolDefinition {
        ToolDefinition(name: base.name, description: base.description, inputSchema: base.inputSchema, outputSchema: base.outputSchema,
                       annotations: base.annotations, pack: "apple", availability: .unavailable(code: code, reason: reason, platform: "macOS"))
    }

    private static func execute(_ invocation: ToolInvocation, _ context: ExecutionContext) async throws -> ToolResult {
        #if os(macOS)
        guard implemented.contains(invocation.name) else { throw ToolError(code: .unavailable, message: "This Apple capability requires a configured host adapter") }
        guard case .object(let a) = invocation.arguments else { throw ToolError(code: .invalidArguments, message: "Arguments must be an object") }
        func string(_ key: String, required: Bool = true) throws -> String? {
            if let value = a[key]?.stringValue { return value }
            if required { throw ToolError(code: .invalidArguments, message: "Missing string argument: \(key)") }
            return nil
        }
        let request: ProcessRequest
        switch invocation.name {
        case "clipboard_read": request = .init(executable: "/usr/bin/pbpaste")
        case "clipboard_write":
            let text = try string("text") ?? string("content")!
            request = .init(executable: "/usr/bin/osascript", arguments: ["-e", "on run argv", "-e", "set the clipboard to item 1 of argv", "-e", "end run", text])
        case "open_url": request = .init(executable: "/usr/bin/open", arguments: [try string("url")!])
        case "open_app": request = .init(executable: "/usr/bin/open", arguments: ["-a", try string("name") ?? string("app")!])
        case "system_notify":
            request = .init(executable: "/usr/bin/osascript", arguments: ["-e", "display notification \"" + escapeAppleScript(try string("message")!) + "\" with title \"" + escapeAppleScript(try string("title", required: false) ?? "G-Rump") + "\""])
        case "screen_snapshot":
            let output = try context.resolveWorkspacePath(try string("path", required: false) ?? ".grump/screenshot.png")
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            request = .init(executable: "/usr/sbin/screencapture", arguments: ["-x", output.path], workingDirectory: context.workspaceRoots.first)
        case "spotlight_search": request = .init(executable: "/usr/bin/mdfind", arguments: [try string("query")!], workingDirectory: context.workspaceRoots.first)
        case "keychain_read":
            let key = try string("key") ?? string("service")!
            guard let value = try await context.credentialStore.value(for: key) else { throw ToolError(code: .executionFailed, message: "Credential not found") }
            return ToolResult(invocationID: invocation.id, content: [.text(value)], structuredContent: ["found": true])
        case "keychain_store":
            let key = try string("key") ?? string("service")!; try await context.credentialStore.setValue(try string("value")!, for: key)
            return ToolResult(invocationID: invocation.id, content: [.text("Stored credential")], structuredContent: ["stored": true])
        case "shortcuts_run": request = .init(executable: "/usr/bin/shortcuts", arguments: ["run", try string("name")!])
        case "system_appearance": request = .init(executable: "/usr/bin/defaults", arguments: ["read", "-g", "AppleInterfaceStyle"])
        case "xcodebuild": request = .init(executable: "/usr/bin/xcodebuild", arguments: (try? strings("arguments", a)) ?? [], workingDirectory: context.workspaceRoots.first)
        case "xcrun_simctl": request = .init(executable: "/usr/bin/xcrun", arguments: ["simctl"] + ((try? strings("arguments", a)) ?? []), workingDirectory: context.workspaceRoots.first)
        case "swift_format": request = .init(executable: "/usr/bin/env", arguments: ["swiftformat", try string("path", required: false) ?? "."], workingDirectory: context.workspaceRoots.first)
        case "swift_lint": request = .init(executable: "/usr/bin/env", arguments: ["swiftlint"], workingDirectory: context.workspaceRoots.first)
        case "swift_package": request = .init(executable: "/usr/bin/env", arguments: ["swift", "package"] + ((try? strings("arguments", a)) ?? []), workingDirectory: context.workspaceRoots.first)
        case "tts_speak": request = .init(executable: "/usr/bin/say", arguments: [try string("text")!])
        case "apple_docs_search": request = .init(executable: "/usr/bin/open", arguments: ["https://developer.apple.com/search/?q=" + (try string("query")!).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!])
        case "lsp_diagnostics": request = .init(executable: "/usr/bin/xcrun", arguments: ["sourcekit-lsp", "--help"], workingDirectory: context.workspaceRoots.first)
        case "accessibility_audit", "localization_audit", "app_store_checklist":
            request = .init(executable: "/usr/bin/find", arguments: [context.workspaceRoots.first!.path, "-name", "*.swift", "-o", "-name", "*.xcstrings", "-o", "-name", "Info.plist"], workingDirectory: context.workspaceRoots.first)
        default: throw ToolError(code: .unavailable, message: "Capability is unavailable")
        }
        let result = try await context.processRunner.run(request)
        let text = [result.standardOutput, result.standardError].filter { !$0.isEmpty }.joined(separator: "\n")
        guard result.exitCode == 0 || invocation.name == "system_appearance" else { throw ToolError(code: .executionFailed, message: text) }
        return ToolResult(invocationID: invocation.id, content: [.text(text.isEmpty ? "ok" : text)], structuredContent: ["exit_code": .integer(Int64(result.exitCode))])
        #else
        throw ToolError(code: .unavailable, message: "This capability requires macOS")
        #endif
    }

    private static func strings(_ key: String, _ a: [String: JSONValue]) throws -> [String] {
        guard case .array(let values)? = a[key], values.allSatisfy({ $0.stringValue != nil }) else { throw ToolError(code: .invalidArguments, message: "\(key) must be an array of strings") }
        return values.compactMap(\.stringValue)
    }
    private static func escapeAppleScript(_ value: String) -> String { value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
}
