import Foundation
import OSLog

// MARK: - Proactive Event Types
//
// Adapted from OpenClaw's `src/hooks/internal-hooks.ts`.
// Typed event categories and actions for the proactive event bus.

enum ProactiveEventType: String, CaseIterable, Sendable {
    case fileSystem
    case git
    case activity
    case calendar
    case memory
    case ambient
    case schedule
    case agent
}

enum ProactiveEventAction: String, Sendable {
    // fileSystem
    case created, changed, deleted
    // git
    case uncommitted, behind, conflict
    // activity
    case toolCompleted, toolFailed
    // calendar
    case upcoming, started, ended
    // memory
    case relevanceSpike
    // ambient
    case appSwitch, clipboardChange
    // schedule
    case fired
    // agent
    case completed, failed
}

// MARK: - Proactive Event

/// Event payload passed through the hook system.
/// Mirrors OpenClaw's `createInternalHookEvent()`.
struct ProactiveEvent: Sendable {
    let id: UUID
    let type: ProactiveEventType
    let action: ProactiveEventAction
    let timestamp: Date
    let sessionKey: String?
    let payload: [String: String]

    init(
        id: UUID = UUID(),
        type: ProactiveEventType,
        action: ProactiveEventAction,
        timestamp: Date = Date(),
        sessionKey: String? = nil,
        payload: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.action = action
        self.timestamp = timestamp
        self.sessionKey = sessionKey
        self.payload = payload
    }
}

// MARK: - Hook Handler

/// A registered hook handler with metadata.
struct HookRegistration: Sendable {
    let id: UUID
    let action: ProactiveEventAction?
    let handler: @Sendable (ProactiveEvent) async -> Void

    init(
        id: UUID = UUID(),
        action: ProactiveEventAction? = nil,
        handler: @escaping @Sendable (ProactiveEvent) async -> Void
    ) {
        self.id = id
        self.action = action
        self.handler = handler
    }
}

// MARK: - Proactive Hook Registry

/// Actor-based event bus mirroring OpenClaw's internal hook system.
/// Handlers register for event types and optional actions.
/// Triggering runs all matching handlers concurrently, catching individual errors.
actor ProactiveHookRegistry {

    private var handlers: [ProactiveEventType: [HookRegistration]] = [:]
    private let logger = GRumpLogger.proactive

    // MARK: - Registration

    /// Register a handler for a specific event type, optionally filtered by action.
    /// Mirrors OpenClaw's `registerInternalHook(event, handler)`.
    @discardableResult
    func register(
        type: ProactiveEventType,
        action: ProactiveEventAction? = nil,
        handler: @escaping @Sendable (ProactiveEvent) async -> Void
    ) -> UUID {
        let registration = HookRegistration(action: action, handler: handler)
        handlers[type, default: []].append(registration)
        logger.debug("Hook registered: \(type.rawValue).\(action?.rawValue ?? "*")")
        return registration.id
    }

    /// Remove a previously registered handler by ID.
    func unregister(id: UUID) {
        for type in ProactiveEventType.allCases {
            handlers[type]?.removeAll { $0.id == id }
        }
    }

    /// Remove all handlers for a given event type.
    func unregisterAll(type: ProactiveEventType) {
        handlers[type] = nil
    }

    // MARK: - Triggering

    /// Trigger all registered handlers for a given event.
    /// Mirrors OpenClaw's `triggerInternalHook(event)` — runs handlers concurrently,
    /// catches individual errors without stopping other handlers.
    /// Fire-and-forget: returns immediately.
    func triggerHook(event: ProactiveEvent) {
        let registrations = handlers[event.type] ?? []
        let matching = registrations.filter { reg in
            reg.action == nil || reg.action == event.action
        }

        guard !matching.isEmpty else { return }

        logger.debug("Triggering \(matching.count) hooks for \(event.type.rawValue).\(event.action.rawValue)")

        // Fire-and-forget: spawn a detached task group
        Task.detached { [logger] in
            await withTaskGroup(of: Void.self) { group in
                for reg in matching {
                    group.addTask {
                        do {
                            await reg.handler(event)
                        } catch {
                            logger.error("Hook handler error [\(event.type.rawValue).\(event.action.rawValue)]: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Introspection

    /// Number of registered handlers per type.
    func handlerCounts() -> [ProactiveEventType: Int] {
        var counts: [ProactiveEventType: Int] = [:]
        for (type, regs) in handlers {
            counts[type] = regs.count
        }
        return counts
    }

    /// Total number of registered handlers.
    func totalHandlerCount() -> Int {
        handlers.values.reduce(0) { $0 + $1.count }
    }
}
