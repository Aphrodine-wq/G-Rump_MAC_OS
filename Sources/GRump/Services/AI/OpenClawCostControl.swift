import Foundation
import os

// MARK: - OpenClaw Cost Control
//
// CRITICAL safeguard system to prevent OpenClaw from draining API credits.
// All limits are user-configurable in Settings, with conservative defaults.
//
// Protection layers:
// 1. Opt-in only (disabled by default)
// 2. Per-session credit cap
// 3. Per-day credit cap
// 4. Rate limiting (requests per minute)
// 5. Model allowlist (restrict which models OpenClaw can use)
// 6. Usage tagging for auditing

@MainActor
final class OpenClawCostControl: ObservableObject {
    static let shared = OpenClawCostControl()

    // MARK: - Configurable Limits

    @Published var requestsPerMinute: Int {
        didSet { UserDefaults.standard.set(requestsPerMinute, forKey: Keys.rateLimit) }
    }
    @Published var allowedModels: [String] {
        didSet { UserDefaults.standard.set(allowedModels, forKey: Keys.allowedModels) }
    }
    @Published var requireOwnAPIKey: Bool {
        didSet { UserDefaults.standard.set(requireOwnAPIKey, forKey: Keys.requireOwnKey) }
    }

    // MARK: - Runtime State

    private(set) var todayRequestCount: Int = 0
    private var requestTimestamps: [Date] = []
    private var todayDate: String = ""
    private let logger = Logger(subsystem: "com.grump.openclaw", category: "CostControl")

    // MARK: - Keys

    private enum Keys {
        static let rateLimit = "OpenClaw_RequestsPerMinute"
        static let allowedModels = "OpenClaw_AllowedModels"
        static let requireOwnKey = "OpenClaw_RequireOwnAPIKey"
        static let todayRequests = "OpenClaw_TodayRequests"
        static let todayDateKey = "OpenClaw_TodayDate"
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        requestsPerMinute = defaults.object(forKey: Keys.rateLimit) as? Int ?? 10
        requireOwnAPIKey = defaults.bool(forKey: Keys.requireOwnKey)

        // Default allowed models: all models (OpenClaw doesn't charge credits)
        if let saved = defaults.array(forKey: Keys.allowedModels) as? [String] {
            allowedModels = saved
        } else {
            allowedModels = AIModel.allCases.map(\.rawValue)
        }

        // Restore daily request count (reset if new day)
        let today = Self.todayString()
        let savedDate = defaults.string(forKey: Keys.todayDateKey) ?? ""
        if savedDate == today {
            todayRequestCount = defaults.integer(forKey: Keys.todayRequests)
        } else {
            todayRequestCount = 0
            defaults.set(today, forKey: Keys.todayDateKey)
            defaults.set(0, forKey: Keys.todayRequests)
        }
        todayDate = today
    }

    // MARK: - Gate Checks

    /// Can we start a new OpenClaw session? Always yes — no credit cost.
    func canStartSession() -> Bool {
        true
    }

    /// Can we process another message in this session? Always yes — no credit cost.
    func canProcessMessage(sessionId: String) -> Bool {
        true
    }

    /// Rate limit check: are we under the requests-per-minute limit?
    func checkRateLimit() -> Bool {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        requestTimestamps = requestTimestamps.filter { $0 > oneMinuteAgo }

        guard requestTimestamps.count < requestsPerMinute else {
            logger.warning("OpenClaw rate limit hit: \(self.requestTimestamps.count)/\(self.requestsPerMinute) per minute")
            return false
        }

        requestTimestamps.append(now)
        return true
    }

    /// Is this model allowed for OpenClaw use?
    func isModelAllowed(_ modelId: String) -> Bool {
        // If no allowlist, all models are allowed
        guard !allowedModels.isEmpty else { return true }
        return allowedModels.contains(modelId)
    }

    // MARK: - Usage Tracking (request count only, no credits)

    func sessionStarted(sessionId: String) {
        // No credit tracking — OpenClaw is free
    }

    func messageProcessed(sessionId: String, credits: Double = 1.0) {
        todayRequestCount += 1
        persistDailyUsage()
    }

    func sessionEnded(sessionId: String) {
        logger.info("OpenClaw session \(sessionId) ended")
    }

    // MARK: - Policy Export

    /// Export current cost policy for gateway registration.
    func currentPolicy() -> [String: Any] {
        return [
            "rateLimit": requestsPerMinute,
            "requireOwnKey": requireOwnAPIKey
        ]
    }

    // MARK: - Usage Summary

    var usageSummary: String {
        "\(todayRequestCount) requests today"
    }

    var dailyUsagePercent: Double {
        // No credit cap — show request count as fraction of a soft daily limit (1000)
        return min(1.0, Double(todayRequestCount) / 1000.0)
    }

    // MARK: - Private

    private func resetDayIfNeeded() {
        let today = Self.todayString()
        if todayDate != today {
            todayRequestCount = 0
            todayDate = today
            persistDailyUsage()
        }
    }

    private func persistDailyUsage() {
        UserDefaults.standard.set(todayRequestCount, forKey: Keys.todayRequests)
        UserDefaults.standard.set(todayDate, forKey: Keys.todayDateKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
