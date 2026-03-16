import Foundation
import OSLog

// MARK: - Dispatch Result

enum DispatchResult: Sendable {
    case delivered([DeliveryResult])
    case skipped(SkipReason)

    enum SkipReason: String, Sendable {
        case duplicate
        case focusSuppressed
        case belowThreshold
        case disabled
    }
}

// MARK: - Suggestion Dispatcher
//
// Adapted from OpenClaw's `src/auto-reply/reply/dispatch-from-config.ts` and `route-reply.ts`.
// Central dispatch pipeline: dedup → focus check → preference adjustment → channel routing → hooks.

actor SuggestionDispatcher {

    private let channelRegistry: SuggestionChannelRegistry
    private let hookRegistry: ProactiveHookRegistry
    private let logger = GRumpLogger.proactive

    // Dedup window: prevent same suggestion type from dispatching within this window
    private var recentDispatches: [String: Date] = [:]
    private let dedupWindowSeconds: TimeInterval = 300

    // Minimum urgency threshold (user-configurable)
    private var minimumThreshold: Int = 20

    // Focus mode state
    private var focusModeActive = false

    init(channelRegistry: SuggestionChannelRegistry, hookRegistry: ProactiveHookRegistry) {
        self.channelRegistry = channelRegistry
        self.hookRegistry = hookRegistry
    }

    // MARK: - Configuration

    func setMinimumThreshold(_ threshold: Int) {
        minimumThreshold = max(0, min(100, threshold))
    }

    func setFocusMode(_ active: Bool) {
        focusModeActive = active
    }

    // MARK: - Dispatch

    /// Main dispatch pipeline mirroring OpenClaw's `dispatchReplyFromConfig`.
    func dispatch(
        _ suggestion: ProactiveSuggestion,
        preferenceLearner: PreferenceLearner,
        appInForeground: Bool = true
    ) async -> DispatchResult {

        // 1. Dedup check (mirrors shouldSkipDuplicateInbound)
        let dedupKey = suggestion.type.rawValue
        if let lastDispatch = recentDispatches[dedupKey],
           Date().timeIntervalSince(lastDispatch) < dedupWindowSeconds {
            logger.debug("Dispatch skipped (duplicate): \(suggestion.type.rawValue)")
            return .skipped(.duplicate)
        }

        // 2. Focus mode check (mirrors OpenClaw's send policy resolution)
        if focusModeActive {
            guard suggestion.urgency.tier == .critical else {
                logger.debug("Dispatch skipped (focus mode): \(suggestion.type.rawValue)")
                return .skipped(.focusSuppressed)
            }
        }

        // 3. Preference adjustment (mirrors session store entry resolution)
        let multiplier = await preferenceLearner.urgencyMultiplier(for: suggestion.type)
        let adjustedUrgency = suggestion.urgency.adjusted(by: multiplier)
        guard adjustedUrgency.score >= minimumThreshold else {
            logger.debug("Dispatch skipped (below threshold \(adjustedUrgency.score) < \(self.minimumThreshold)): \(suggestion.type.rawValue)")
            return .skipped(.belowThreshold)
        }

        // 4. Route to channels (mirrors routeReply with channel selection)
        let channels = await channelRegistry.resolveChannels(for: adjustedUrgency, appInForeground: appInForeground)
        guard !channels.isEmpty else {
            logger.warning("No channels available for suggestion: \(suggestion.type.rawValue)")
            return .skipped(.disabled)
        }

        let adjusted = suggestion.withUrgency(adjustedUrgency)
        var results: [DeliveryResult] = []
        for channel in channels {
            let result = await channel.deliver(adjusted)
            results.append(result)
            logger.debug("Delivered to \(channel.id): \(String(describing: result))")
        }

        // 5. Record dedup timestamp
        recentDispatches[dedupKey] = Date()
        cleanupOldDedup()

        // 6. Fire hooks (mirrors dispatchFromConfig's hook triggering)
        await hookRegistry.triggerHook(event: ProactiveEvent(
            type: .agent,
            action: .completed,
            payload: [
                "suggestionId": suggestion.id,
                "suggestionType": suggestion.type.rawValue,
                "channels": channels.map(\.id).joined(separator: ",")
            ]
        ))

        // 7. Log diagnostics (mirrors logMessageProcessed)
        logger.info("Dispatched \(suggestion.type.rawValue) (urgency: \(adjustedUrgency.score)) to \(channels.count) channels")

        return .delivered(results)
    }

    // MARK: - Dedup Cleanup

    private func cleanupOldDedup() {
        let cutoff = Date().addingTimeInterval(-dedupWindowSeconds * 2)
        recentDispatches = recentDispatches.filter { $0.value > cutoff }
    }
}
