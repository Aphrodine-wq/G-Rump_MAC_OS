import Foundation
import OSLog

// MARK: - Intent Continuity System
//
// Persists high-level user goals across sessions. Not just facts
// (memory already does that) — but *intent*: "building a payment system",
// "migrating from UIKit to SwiftUI", "preparing for App Store submission".
//
// When the user returns to a project:
//   - Surfaces the active intent with progress
//   - Tracks completion against the original goal
//   - Can resume mid-task with full context
//
// Every AI tool today is session-scoped for intent. Memory stores facts,
// but no tool stores and tracks goals with progress.

// MARK: - Intent Status

enum IntentStatus: String, Codable, CaseIterable {
    case active = "active"
    case paused = "paused"
    case completed = "completed"
    case abandoned = "abandoned"

    var icon: String {
        switch self {
        case .active:    return "bolt.fill"
        case .paused:    return "pause.circle"
        case .completed: return "checkmark.circle.fill"
        case .abandoned: return "xmark.circle"
        }
    }
}

// MARK: - Intent Milestone

struct IntentMilestone: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    var completedAt: Date?
    var conversationId: String?

    init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        conversationId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.conversationId = conversationId
    }
}

// MARK: - User Intent

struct UserIntent: Identifiable, Codable, Equatable {
    let id: UUID
    var goal: String
    var context: String
    var status: IntentStatus
    var milestones: [IntentMilestone]
    var createdAt: Date
    var updatedAt: Date
    var lastSessionAt: Date
    var sessionCount: Int
    var tags: [String]

    static func == (lhs: UserIntent, rhs: UserIntent) -> Bool {
        lhs.id == rhs.id
    }

    init(
        id: UUID = UUID(),
        goal: String,
        context: String = "",
        status: IntentStatus = .active,
        milestones: [IntentMilestone] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastSessionAt: Date = Date(),
        sessionCount: Int = 1,
        tags: [String] = []
    ) {
        self.id = id
        self.goal = goal
        self.context = context
        self.status = status
        self.milestones = milestones
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastSessionAt = lastSessionAt
        self.sessionCount = sessionCount
        self.tags = tags
    }

    /// Progress as a fraction (0.0–1.0).
    var progress: Double {
        guard !milestones.isEmpty else { return 0.0 }
        let completed = milestones.filter(\.isCompleted).count
        return Double(completed) / Double(milestones.count)
    }

    /// Human-readable progress string.
    var progressSummary: String {
        if milestones.isEmpty {
            return "No milestones defined yet"
        }
        let completed = milestones.filter(\.isCompleted).count
        let remaining = milestones.count - completed
        if remaining == 0 {
            return "All \(milestones.count) milestones completed"
        }
        return "\(completed)/\(milestones.count) milestones done — \(remaining) remaining"
    }

    /// Time since last session, human readable.
    var timeSinceLastSession: String {
        let interval = Date().timeIntervalSince(lastSessionAt)
        if interval < 3600 {
            return "\(Int(interval / 60)) minutes ago"
        } else if interval < 86400 {
            return "\(Int(interval / 3600)) hours ago"
        } else {
            return "\(Int(interval / 86400)) days ago"
        }
    }

    /// System prompt fragment for context injection.
    var promptFragment: String {
        var lines: [String] = []
        lines.append("# Active Intent")
        lines.append("**Goal:** \(goal)")
        if !context.isEmpty {
            lines.append("**Context:** \(context)")
        }
        lines.append("**Progress:** \(progressSummary)")
        lines.append("**Sessions:** \(sessionCount) (last: \(timeSinceLastSession))")

        if !milestones.isEmpty {
            lines.append("\n**Milestones:**")
            for m in milestones {
                let check = m.isCompleted ? "[x]" : "[ ]"
                lines.append("- \(check) \(m.title)")
            }
        }

        let remaining = milestones.filter { !$0.isCompleted }
        if let next = remaining.first {
            lines.append("\n**Next milestone:** \(next.title)")
        }

        lines.append("\nContinue working toward this goal. Update milestones as they are completed.")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Intent Store

struct IntentStore: Codable {
    var intents: [UserIntent]
    var version: Int = 1
}

// MARK: - Intent Continuity Service

@MainActor
final class IntentContinuityService: ObservableObject {

    @Published private(set) var activeIntent: UserIntent?
    @Published private(set) var allIntents: [UserIntent] = []

    private var workingDirectory: String = ""
    private let logger = GRumpLogger.general

    // MARK: - Lifecycle

    /// Load intents for a project directory.
    func load(workingDirectory: String) {
        self.workingDirectory = workingDirectory
        guard !workingDirectory.isEmpty else {
            activeIntent = nil
            allIntents = []
            return
        }

        let store = loadStore()
        allIntents = store.intents
        activeIntent = store.intents.first { $0.status == .active }
    }

    // MARK: - Intent Management

    /// Create a new intent from the agent's analysis of the conversation.
    func createIntent(goal: String, context: String = "", milestones: [String] = []) {
        var intent = UserIntent(goal: goal, context: context)
        intent.milestones = milestones.map { IntentMilestone(title: $0) }

        allIntents.insert(intent, at: 0)
        activeIntent = intent
        save()
        logger.info("IntentContinuity: Created intent '\(goal)' with \(milestones.count) milestones")
    }

    /// Update the active intent's context and milestones based on conversation.
    func updateActiveIntent(
        newContext: String? = nil,
        completedMilestones: [String] = [],
        newMilestones: [String] = [],
        conversationId: String? = nil
    ) {
        guard var intent = activeIntent else { return }

        if let ctx = newContext {
            intent.context = ctx
        }

        // Mark milestones as completed (fuzzy match on title)
        for milestoneTitle in completedMilestones {
            let lower = milestoneTitle.lowercased()
            if let idx = intent.milestones.firstIndex(where: {
                !$0.isCompleted && $0.title.lowercased().contains(lower)
            }) {
                intent.milestones[idx].isCompleted = true
                intent.milestones[idx].completedAt = Date()
                intent.milestones[idx].conversationId = conversationId
            }
        }

        // Add new milestones
        for title in newMilestones {
            if !intent.milestones.contains(where: { $0.title.lowercased() == title.lowercased() }) {
                intent.milestones.append(IntentMilestone(title: title))
            }
        }

        // Check if all milestones are completed
        if !intent.milestones.isEmpty && intent.milestones.allSatisfy(\.isCompleted) {
            intent.status = .completed
        }

        intent.updatedAt = Date()
        intent.lastSessionAt = Date()
        intent.sessionCount += 1

        // Update in list
        if let idx = allIntents.firstIndex(where: { $0.id == intent.id }) {
            allIntents[idx] = intent
        }

        activeIntent = intent.status == .active ? intent : nil
        save()
    }

    /// Pause the active intent.
    func pauseActiveIntent() {
        guard var intent = activeIntent else { return }
        intent.status = .paused
        intent.updatedAt = Date()
        if let idx = allIntents.firstIndex(where: { $0.id == intent.id }) {
            allIntents[idx] = intent
        }
        activeIntent = nil
        save()
    }

    /// Resume a paused intent.
    func resumeIntent(_ intentId: UUID) {
        guard let idx = allIntents.firstIndex(where: { $0.id == intentId }) else { return }
        // Pause any currently active intent
        if let activeIdx = allIntents.firstIndex(where: { $0.status == .active }) {
            allIntents[activeIdx].status = .paused
        }
        allIntents[idx].status = .active
        allIntents[idx].lastSessionAt = Date()
        allIntents[idx].sessionCount += 1
        activeIntent = allIntents[idx]
        save()
    }

    /// Abandon an intent.
    func abandonIntent(_ intentId: UUID) {
        guard let idx = allIntents.firstIndex(where: { $0.id == intentId }) else { return }
        allIntents[idx].status = .abandoned
        allIntents[idx].updatedAt = Date()
        if activeIntent?.id == intentId { activeIntent = nil }
        save()
    }

    /// Extract an intent from the first user message in a conversation.
    /// Returns a goal string and suggested milestones if the message describes a multi-step task.
    static func extractIntent(from message: String) -> (goal: String, milestones: [String])? {
        let lower = message.lowercased()

        // Look for multi-step task indicators
        let taskIndicators = [
            "build", "create", "implement", "develop", "design", "set up",
            "migrate", "convert", "refactor", "add", "integrate", "deploy",
            "prepare", "configure", "establish"
        ]

        guard taskIndicators.contains(where: { lower.contains($0) }) else { return nil }

        // Don't create intents for simple one-shot tasks
        let simpleIndicators = ["fix", "typo", "rename", "delete", "remove", "update version"]
        if simpleIndicators.contains(where: { lower.contains($0) }) && message.count < 100 {
            return nil
        }

        // Extract the goal (first sentence or up to 150 chars)
        let goal: String
        if let period = message.firstIndex(of: "."), message.distance(from: message.startIndex, to: period) < 150 {
            goal = String(message[...period]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            goal = String(message.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract numbered steps or bullet points as milestones
        var milestones: [String] = []
        let lines = message.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match numbered lists (1. xxx, 1) xxx) or bullet lists (- xxx, * xxx)
            if trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil {
                let content = trimmed.replacingOccurrences(of: #"^\d+[\.\)]\s+"#, with: "", options: .regularExpression)
                milestones.append(String(content.prefix(100)))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2))
                milestones.append(String(content.prefix(100)))
            }
        }

        return (goal: goal, milestones: milestones)
    }

    // MARK: - Persistence

    private var storeURL: URL {
        let grumpDir = (workingDirectory as NSString).appendingPathComponent(".grump")
        return URL(fileURLWithPath: grumpDir).appendingPathComponent("intents.json")
    }

    private func loadStore() -> IntentStore {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(IntentStore.self, from: data) else {
            return IntentStore(intents: [])
        }
        return store
    }

    private func save() {
        let store = IntentStore(intents: allIntents)
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }
}
