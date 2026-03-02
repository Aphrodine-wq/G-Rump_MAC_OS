import Foundation
import OSLog

// MARK: - Preference Record

/// A single interaction record for learning user preferences.
struct PreferenceRecord: Codable {
    let type: String
    let action: UserAction
    let timestamp: Date
    let hourOfDay: Int

    enum UserAction: String, Codable {
        case accepted
        case snoozed
        case dismissed
    }
}

// MARK: - Preference Learner
//
// Tracks accept/dismiss/snooze patterns per suggestion type.
// Adjusts urgency score multipliers over time.
// Mirrors OpenClaw's temporal decay from `temporal-decay.ts`
// and Swabble's `HookExecutor.swift` cooldown pattern.

actor PreferenceLearner {

    private var records: [PreferenceRecord] = []
    private var cooldowns: [String: Date] = [:]
    private let persistencePath: String
    private let logger = GRumpLogger.proactive

    // Configuration
    private let maxRecords = 1000
    private let confidenceDecayDays: Double = 30
    private let defaultCooldownSeconds: TimeInterval = 300

    init(globalDirectory: String? = nil) {
        let home = globalDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.persistencePath = (home as NSString).appendingPathComponent(".grump/preference_learner.json")
        loadRecords()
    }

    // MARK: - Recording

    /// Record a user action on a suggestion.
    func record(type: ProactiveSuggestionType, action: PreferenceRecord.UserAction) {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)

        let record = PreferenceRecord(
            type: type.rawValue,
            action: action,
            timestamp: now,
            hourOfDay: hour
        )
        records.append(record)

        // Prune oldest records
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }

        // Set cooldown for this type
        cooldowns[type.rawValue] = now

        saveRecords()
        logger.debug("Preference recorded: \(type.rawValue) → \(action.rawValue)")
    }

    // MARK: - Urgency Multiplier

    /// Compute urgency multiplier for a suggestion type based on historical patterns.
    /// Returns a value 0.0–2.0: <1.0 suppresses, >1.0 promotes.
    func urgencyMultiplier(for type: ProactiveSuggestionType) -> Float {
        let typeRecords = records.filter { $0.type == type.rawValue }
        guard !typeRecords.isEmpty else { return 1.0 }

        let now = Date()
        var weightedAccepted: Float = 0
        var weightedTotal: Float = 0

        for record in typeRecords {
            // Temporal decay: recent records matter more
            let ageDays = Float(now.timeIntervalSince(record.timestamp)) / 86400.0
            let weight = 1.0 / (1.0 + ageDays / Float(confidenceDecayDays))

            weightedTotal += weight
            if record.action == .accepted {
                weightedAccepted += weight
            } else if record.action == .dismissed {
                weightedAccepted -= weight * 0.5
            }
            // snoozed is neutral (no weight change)
        }

        guard weightedTotal > 0 else { return 1.0 }

        let acceptRate = weightedAccepted / weightedTotal
        // Map accept rate to multiplier: -1.0→0.2, 0.0→0.8, 0.5→1.0, 1.0→1.5
        let multiplier = 0.8 + acceptRate * 0.7
        return max(0.1, min(2.0, multiplier))
    }

    // MARK: - Time-of-Day Learning

    /// Check if the current hour is a good time for a suggestion type.
    /// Returns a multiplier (0.5 if historically dismissed at this hour, 1.0 if neutral, 1.2 if historically accepted).
    func timeOfDayMultiplier(for type: ProactiveSuggestionType) -> Float {
        let currentHour = Calendar.current.component(.hour, from: Date())
        let hourRecords = records.filter { $0.type == type.rawValue && $0.hourOfDay == currentHour }

        guard hourRecords.count >= 3 else { return 1.0 }

        let accepted = hourRecords.filter { $0.action == .accepted }.count
        let dismissed = hourRecords.filter { $0.action == .dismissed }.count
        let total = hourRecords.count

        if dismissed > accepted * 2 { return 0.5 }
        if accepted > dismissed * 2 { return 1.2 }
        return Float(accepted) / Float(max(1, total))
    }

    // MARK: - Cooldown

    /// Check if a suggestion type is in cooldown.
    /// Mirrors Swabble's `HookExecutor.shouldRun()` pattern.
    func isInCooldown(type: ProactiveSuggestionType, cooldownSeconds: TimeInterval? = nil) -> Bool {
        let cooldown = cooldownSeconds ?? defaultCooldownSeconds
        guard let lastFired = cooldowns[type.rawValue] else { return false }
        return Date().timeIntervalSince(lastFired) < cooldown
    }

    /// Set a custom cooldown for a suggestion type.
    func setCooldown(type: ProactiveSuggestionType) {
        cooldowns[type.rawValue] = Date()
    }

    // MARK: - Stats

    func stats(for type: ProactiveSuggestionType) -> (accepted: Int, snoozed: Int, dismissed: Int, multiplier: Float) {
        let typeRecords = records.filter { $0.type == type.rawValue }
        let accepted = typeRecords.filter { $0.action == .accepted }.count
        let snoozed = typeRecords.filter { $0.action == .snoozed }.count
        let dismissed = typeRecords.filter { $0.action == .dismissed }.count
        let mult = urgencyMultiplier(for: type)
        return (accepted, snoozed, dismissed, mult)
    }

    func allTypeStats() -> [(type: String, accepted: Int, dismissed: Int, multiplier: Float)] {
        var grouped: [String: (accepted: Int, dismissed: Int)] = [:]
        for record in records {
            var current = grouped[record.type, default: (0, 0)]
            if record.action == .accepted { current.accepted += 1 }
            if record.action == .dismissed { current.dismissed += 1 }
            grouped[record.type] = current
        }
        return grouped.map { typeStr, stats in
            let type = ProactiveSuggestionType(rawValue: typeStr)
            let mult = type.map { urgencyMultiplier(for: $0) } ?? 1.0
            return (typeStr, stats.accepted, stats.dismissed, mult)
        }.sorted { $0.0 < $1.0 }
    }

    // MARK: - Persistence

    private func loadRecords() {
        let url = URL(fileURLWithPath: persistencePath)
        guard FileManager.default.fileExists(atPath: persistencePath),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([PreferenceRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func saveRecords() {
        let url = URL(fileURLWithPath: persistencePath)
        let dir = (persistencePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url)
        }
    }
}
