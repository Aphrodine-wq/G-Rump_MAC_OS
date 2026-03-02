import Foundation
import Combine
#if os(macOS)
import AppKit
#endif

// MARK: - Ambient Context Event

/// Events captured by the ambient monitor for context-aware features.
struct AmbientContextEvent: Identifiable {
    let id = UUID()
    let type: EventType
    let timestamp: Date
    let data: [String: String]

    enum EventType: String {
        case appSwitch
        case clipboardChange
        case windowTitleChange
        case workspaceFileChange
    }
}

// MARK: - Ambient Monitor

/// Extends ambient awareness beyond code files to track active apps, clipboard content,
/// workspace file events, and window titles. All processing on-device.
/// Each monitor type is independently toggleable via UserDefaults.
@MainActor
final class AmbientMonitor: ObservableObject {

    static let shared = AmbientMonitor()

    // MARK: - Published State

    @Published var currentApp: String = ""
    @Published var currentWindowTitle: String = ""
    @Published var recentEvents: [AmbientContextEvent] = []
    @Published var isMonitoring = false

    // MARK: - Settings

    @Published var appTrackingEnabled: Bool = UserDefaults.standard.object(forKey: "AmbientAppTrackingEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(appTrackingEnabled, forKey: "AmbientAppTrackingEnabled") }
    }
    @Published var clipboardMonitorEnabled: Bool = UserDefaults.standard.object(forKey: "AmbientClipboardEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(clipboardMonitorEnabled, forKey: "AmbientClipboardEnabled") }
    }
    @Published var windowTitleTrackingEnabled: Bool = UserDefaults.standard.object(forKey: "AmbientWindowTitleEnabled") as? Bool ?? false {
        didSet { UserDefaults.standard.set(windowTitleTrackingEnabled, forKey: "AmbientWindowTitleEnabled") }
    }

    // MARK: - Private

    private let maxRecentEvents = 50
    private var cancellables = Set<AnyCancellable>()
    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = 0
    #if os(macOS)
    private var workspaceObserver: NSObjectProtocol?
    #endif

    /// Callback for when context events occur — wired to ProactiveEngine hooks.
    var onContextEvent: ((AmbientContextEvent) -> Void)?

    private init() {}

    // MARK: - Start / Stop

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        #if os(macOS)
        startAppTracking()
        startClipboardMonitoring()
        #endif

        GRumpLogger.memory.info("AmbientMonitor started")
    }

    func stopMonitoring() {
        isMonitoring = false

        #if os(macOS)
        stopAppTracking()
        stopClipboardMonitoring()
        #endif

        GRumpLogger.memory.info("AmbientMonitor stopped")
    }

    // MARK: - App Tracking

    #if os(macOS)
    private func startAppTracking() {
        guard appTrackingEnabled else { return }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }

            let appName = app.localizedName ?? "Unknown"
            let bundleId = app.bundleIdentifier ?? ""

            let previousApp = self.currentApp
            self.currentApp = appName

            // Only emit event if actually switching apps
            if previousApp != appName && !previousApp.isEmpty {
                let event = AmbientContextEvent(
                    type: .appSwitch,
                    timestamp: Date(),
                    data: [
                        "from": previousApp,
                        "to": appName,
                        "bundleId": bundleId
                    ]
                )
                self.recordEvent(event)
            }
        }

        // Capture initial app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            currentApp = frontApp.localizedName ?? "Unknown"
        }
    }

    private func stopAppTracking() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
    }
    #endif

    // MARK: - Clipboard Monitoring

    #if os(macOS)
    private func startClipboardMonitoring() {
        guard clipboardMonitorEnabled else { return }

        lastClipboardChangeCount = NSPasteboard.general.changeCount

        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    private func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount

        // Only capture if it looks like code or an error message
        guard let content = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count >= 10, trimmed.count <= 2000 else { return }

        // Privacy: only store if content matches code/error patterns
        let isCodeLike = looksLikeCode(trimmed)
        let isErrorLike = looksLikeError(trimmed)
        guard isCodeLike || isErrorLike else { return }

        // Store a hash of the content, not the raw content
        let contentHash = String(trimmed.hashValue)
        let preview = String(trimmed.prefix(100))

        let event = AmbientContextEvent(
            type: .clipboardChange,
            timestamp: Date(),
            data: [
                "hash": contentHash,
                "preview": preview,
                "type": isErrorLike ? "error" : "code",
                "length": "\(trimmed.count)"
            ]
        )
        recordEvent(event)
    }
    #endif

    // MARK: - Pattern Detection

    private func looksLikeCode(_ text: String) -> Bool {
        let codeIndicators = [
            "func ", "class ", "struct ", "enum ", "import ",
            "var ", "let ", "const ", "def ", "return ",
            "if ", "for ", "while ", "switch ",
            "->", "=>", "{ ", "};", "()", "[]",
            "self.", "this.", "@Published", "@State"
        ]
        let lowered = text.lowercased()
        let matchCount = codeIndicators.filter { lowered.contains($0.lowercased()) }.count
        return matchCount >= 2
    }

    private func looksLikeError(_ text: String) -> Bool {
        let errorIndicators = [
            "error:", "Error:", "ERROR",
            "failed", "Failed", "FAILED",
            "exception", "Exception",
            "stack trace", "Traceback",
            "fatal", "Fatal",
            "cannot find", "undefined",
            "compilation error", "build failed"
        ]
        return errorIndicators.contains { text.contains($0) }
    }

    // MARK: - Event Recording

    private func recordEvent(_ event: AmbientContextEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(maxRecentEvents))
        }
        onContextEvent?(event)
    }

    // MARK: - Context Summary

    /// Build a summary of recent ambient context for injection into prompts or proactive suggestions.
    func contextSummary(maxItems: Int = 5) -> String? {
        let recent = recentEvents.prefix(maxItems)
        guard !recent.isEmpty else { return nil }

        var parts: [String] = []
        for event in recent {
            switch event.type {
            case .appSwitch:
                if let from = event.data["from"], let to = event.data["to"] {
                    parts.append("Switched from \(from) to \(to)")
                }
            case .clipboardChange:
                if let preview = event.data["preview"], let type = event.data["type"] {
                    parts.append("Copied \(type): \(preview)")
                }
            case .windowTitleChange:
                if let title = event.data["title"] {
                    parts.append("Window: \(title)")
                }
            case .workspaceFileChange:
                if let path = event.data["path"] {
                    parts.append("File changed: \(path)")
                }
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
