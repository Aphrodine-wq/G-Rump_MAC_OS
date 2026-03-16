import Foundation
#if os(macOS)
import AppKit

// MARK: - macOS Services Provider
//
// Registers G-Rump as a macOS Services provider so users can:
//   - Select text in any app → right-click → Services → "Ask G-Rump"
//   - Select file paths → Services → "Ask G-Rump About This File"
//
// Also provides Finder integration via URL scheme handling:
//   grump://ask?text=...
//   grump://open?file=...

@MainActor
final class GRumpServicesProvider: NSObject {

    static let shared = GRumpServicesProvider()

    private override init() {
        super.init()
    }

    /// Register as macOS Services provider. Call once from app launch.
    func register() {
        NSApp.servicesProvider = self
        // Force Services menu to update
        NSUpdateDynamicServices()
    }

    // MARK: - Service: Ask G-Rump (text selection)

    /// Receives selected text from any app via Services menu.
    /// The method name must match the NSMessage in Info.plist:
    ///   sendToGRump:userData:error:
    @objc func sendToGRump(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text selected." as NSString
            return
        }

        // Bring app to front
        NSApp.activate(ignoringOtherApps: true)

        // Post notification to create new chat with this text
        NotificationCenter.default.post(
            name: .init("GRumpServiceAsk"),
            object: nil,
            userInfo: ["text": text]
        )
    }

    // MARK: - Service: Ask About File (file selection from Finder)

    @objc func askAboutFile(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        // Try to get file URLs from pasteboard
        let fileURLs = pboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] ?? []

        // Also try string paths
        let textPaths = pboard.string(forType: .string)?
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { FileManager.default.fileExists(atPath: $0) } ?? []

        let allPaths = fileURLs.map { $0.path } + textPaths

        guard !allPaths.isEmpty else {
            error.pointee = "No file paths found." as NSString
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.post(
            name: .init("GRumpServiceFile"),
            object: nil,
            userInfo: ["paths": allPaths]
        )
    }
}

// MARK: - URL Scheme Handler

enum GRumpURLSchemeHandler {

    /// Handle grump:// URL scheme.
    /// Supported URLs:
    ///   grump://ask?text=Hello
    ///   grump://open?conversation=UUID
    ///   grump://file?path=/path/to/file
    static func handle(_ url: URL) {
        guard url.scheme == "grump" else { return }

        switch url.host {
        case "ask":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let text = components.queryItems?.first(where: { $0.name == "text" })?.value {
                NotificationCenter.default.post(
                    name: .init("GRumpServiceAsk"),
                    object: nil,
                    userInfo: ["text": text]
                )
            }

        case "open":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let idString = components.queryItems?.first(where: { $0.name == "conversation" })?.value {
                NotificationCenter.default.post(
                    name: .init("GRumpOpenConversation"),
                    object: nil,
                    userInfo: ["conversationId": idString]
                )
            }

        case "file":
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let path = components.queryItems?.first(where: { $0.name == "path" })?.value {
                NotificationCenter.default.post(
                    name: .init("GRumpServiceFile"),
                    object: nil,
                    userInfo: ["paths": [path]]
                )
            }

        default:
            break
        }
    }
}

// MARK: - Dock Menu

extension GRumpServicesProvider {

    /// Build the Dock right-click menu.
    func buildDockMenu() -> NSMenu {
        let menu = NSMenu()

        let newChat = NSMenuItem(title: "New Chat", action: #selector(dockNewChat), keyEquivalent: "")
        newChat.target = self
        menu.addItem(newChat)

        let settings = NSMenuItem(title: "Settings…", action: #selector(dockOpenSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        return menu
    }

    @objc private func dockNewChat() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .init("GRumpNewChat"), object: nil)
    }

    @objc private func dockOpenSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .init("GRumpOpenSettings"), object: nil)
    }
}

#endif
