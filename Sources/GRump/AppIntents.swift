import AppIntents
import SwiftUI

// MARK: - App Intents for Siri Shortcuts & Spotlight
//
// Exposes G-Rump actions to the system so users can:
// - Ask G-Rump a question via Shortcuts/Siri
// - Start a new coding session
// - Run an agent task on a file/folder
// These show up in Shortcuts.app and Spotlight suggestions.

// MARK: - Ask G-Rump Intent

struct AskGRumpIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask G-Rump"
    static var description = IntentDescription(
        "Send a prompt to G-Rump and get an AI response.",
        categoryName: "AI"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Prompt", description: "The question or task to send to G-Rump")
    var prompt: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        NotificationCenter.default.post(
            name: Notification.Name("GRumpShortcutAsk"),
            object: nil,
            userInfo: ["prompt": prompt]
        )
        return .result(dialog: IntentDialog(stringLiteral: "Sent to G-Rump: \(prompt)"))
    }
}

// MARK: - New Chat Intent

struct NewChatIntent: AppIntent {
    static var title: LocalizedStringResource = "New G-Rump Chat"
    static var description = IntentDescription(
        "Start a new conversation in G-Rump.",
        categoryName: "AI"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Initial Message", description: "Optional first message for the chat", default: "")
    var initialMessage: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var userInfo: [String: Any] = [:]
        if !initialMessage.isEmpty {
            userInfo["prompt"] = initialMessage
        }
        NotificationCenter.default.post(
            name: Notification.Name("GRumpNewChat"),
            object: nil,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
        return .result(dialog: IntentDialog(stringLiteral: initialMessage.isEmpty ? "New chat started" : "New chat: \(initialMessage)"))
    }
}

// MARK: - Run Agent Task Intent

struct RunAgentTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Run G-Rump Agent Task"
    static var description = IntentDescription(
        "Run an AI agent task on a file or directory.",
        categoryName: "AI"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Task Description", description: "What the agent should do")
    var taskDescription: String

    @Parameter(title: "Working Directory", description: "Optional path to the project directory", default: "")
    var workingDirectory: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var userInfo: [String: Any] = ["prompt": taskDescription]
        if !workingDirectory.isEmpty {
            userInfo["workingDirectory"] = workingDirectory
        }
        NotificationCenter.default.post(
            name: Notification.Name("GRumpAgentTask"),
            object: nil,
            userInfo: userInfo
        )
        return .result(dialog: IntentDialog(stringLiteral: "Agent task started: \(taskDescription)"))
    }
}

// MARK: - App Shortcuts Provider

struct GRumpShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskGRumpIntent(),
            phrases: [
                "Ask \(.applicationName) a question",
                "Ask \(.applicationName) something",
                "Send a prompt to \(.applicationName)"
            ],
            shortTitle: "Ask G-Rump",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "Start a new \(.applicationName) chat",
                "New \(.applicationName) conversation"
            ],
            shortTitle: "New Chat",
            systemImageName: "plus.bubble"
        )
        AppShortcut(
            intent: RunAgentTaskIntent(),
            phrases: [
                "Run \(.applicationName) agent task",
                "\(.applicationName) run agent"
            ],
            shortTitle: "Run Agent Task",
            systemImageName: "bolt.circle"
        )
    }
}
