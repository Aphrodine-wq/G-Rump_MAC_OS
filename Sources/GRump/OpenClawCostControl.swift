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

    @Published var perSessionCreditCap: Double {
        didSet { UserDefaults.standard.set(perSessionCreditCap, forKey: Keys.perSessionCap) }
    }
    @Published var perDayCreditCap: Double {
        didSet { UserDefaults.standard.set(perDayCreditCap, forKey: Keys.perDayCap) }
    }
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

    private(set) var todayCreditsUsed: Double = 0
    private(set) var sessionCredits: [String: Double] = [:]
    private var requestTimestamps: [Date] = []
    private var todayDate: String = ""
    private let logger = Logger(subsystem: "com.grump.openclaw", category: "CostControl")

    // MARK: - Keys

    private enum Keys {
        static let perSessionCap = "OpenClaw_PerSessionCreditCap"
        static let perDayCap = "OpenClaw_PerDayCreditCap"
        static let rateLimit = "OpenClaw_RequestsPerMinute"
        static let allowedModels = "OpenClaw_AllowedModels"
        static let requireOwnKey = "OpenClaw_RequireOwnAPIKey"
        static let todayUsed = "OpenClaw_TodayCreditsUsed"
        static let todayDateKey = "OpenClaw_TodayDate"
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Conservative defaults
        perSessionCreditCap = defaults.object(forKey: Keys.perSessionCap) as? Double ?? 100.0
        perDayCreditCap = defaults.object(forKey: Keys.perDayCap) as? Double ?? 500.0
        requestsPerMinute = defaults.object(forKey: Keys.rateLimit) as? Int ?? 10
        requireOwnAPIKey = defaults.bool(forKey: Keys.requireOwnKey)

        // Default allowed models: free models only (safest default)
        if let saved = defaults.array(forKey: Keys.allowedModels) as? [String] {
            allowedModels = saved
        } else {
            allowedModels = [
                AIModel.qwen3Coder.rawValue,
                AIModel.deepseekR1.rawValue,
                AIModel.deepseekChat.rawValue,
                AIModel.gemini31Flash.rawValue,
            ]
        }

        // Restore daily usage (reset if new day)
        let today = Self.todayString()
        let savedDate = defaults.string(forKey: Keys.todayDateKey) ?? ""
        if savedDate == today {
            todayCreditsUsed = defaults.double(forKey: Keys.todayUsed)
        } else {
            todayCreditsUsed = 0
            defaults.set(today, forKey: Keys.todayDateKey)
            defaults.set(0.0, forKey: Keys.todayUsed)
        }
        todayDate = today
    }

    // MARK: - Gate Checks

    /// Can we start a new OpenClaw session?
    func canStartSession() -> Bool {
        resetDayIfNeeded()
        return todayCreditsUsed < perDayCreditCap
    }

    /// Can we process another message in this session?
    func canProcessMessage(sessionId: String) -> Bool {
        resetDayIfNeeded()

        // Day cap check
        guard todayCreditsUsed < perDayCreditCap else {
            logger.warning("OpenClaw day cap reached: \(self.todayCreditsUsed)/\(self.perDayCreditCap)")
            return false
        }

        // Session cap check
        let sessionUsed = sessionCredits[sessionId] ?? 0
        guard sessionUsed < perSessionCreditCap else {
            logger.warning("OpenClaw session cap reached for \(sessionId): \(sessionUsed)/\(self.perSessionCreditCap)")
            return false
        }

        return true
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

    // MARK: - Usage Tracking

    func sessionStarted(sessionId: String) {
        sessionCredits[sessionId] = 0
    }

    func messageProcessed(sessionId: String, credits: Double = 1.0) {
        sessionCredits[sessionId, default: 0] += credits
        todayCreditsUsed += credits
        persistDailyUsage()
    }

    func sessionEnded(sessionId: String) {
        let used = sessionCredits.removeValue(forKey: sessionId) ?? 0
        logger.info("OpenClaw session \(sessionId) used \(used) credits")
    }

    // MARK: - Policy Export

    /// Export current cost policy for gateway registration.
    func currentPolicy() -> [String: Any] {
        return [
            "perSessionCap": perSessionCreditCap,
            "perDayCap": perDayCreditCap,
            "rateLimit": requestsPerMinute,
            "requireOwnKey": requireOwnAPIKey
        ]
    }

    // MARK: - Usage Summary

    var usageSummary: String {
        let sessionCount = sessionCredits.count
        return "\(Int(todayCreditsUsed))/\(Int(perDayCreditCap)) credits today, \(sessionCount) active session\(sessionCount == 1 ? "" : "s")"
    }

    var dailyUsagePercent: Double {
        guard perDayCreditCap > 0 else { return 0 }
        return min(1.0, todayCreditsUsed / perDayCreditCap)
    }

    // MARK: - Private

    private func resetDayIfNeeded() {
        let today = Self.todayString()
        if todayDate != today {
            todayCreditsUsed = 0
            todayDate = today
            persistDailyUsage()
        }
    }

    private func persistDailyUsage() {
        UserDefaults.standard.set(todayCreditsUsed, forKey: Keys.todayUsed)
        UserDefaults.standard.set(todayDate, forKey: Keys.todayDateKey)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
