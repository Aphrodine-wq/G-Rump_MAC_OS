import Foundation

// MARK: - Proactive Suggestion Types

/// All proactive suggestion types, categorized by trigger source.
enum ProactiveSuggestionType: String, CaseIterable, Sendable, Equatable, Hashable {

    // Activity-triggered (via hook registry)
    case uncommittedChanges
    case testFailure
    case dependencyAlert
    case contextSwitch
    case codeReview
    case branchStale

    // Cron-triggered (via cron scheduler)
    case endOfDayReview
    case morningBrief
    case focusReminder

    // Memory-triggered (via memory relevance scan)
    case relatedMemory

    // Calendar-triggered (via EventKit cron)
    case meetingPrep

    // Chain-triggered (via lifecycle chaining)
    case commitAfterTests
    case pushAfterCommit
    case reviewAfterManyEdits

    // Legacy (migrated from SuggestionEngine)
    case runTests
    case runBuild
    case commitChanges
    case fixErrors
    case fixLint
    case reviewCode

    // MARK: - Metadata

    var displayName: String {
        switch self {
        case .uncommittedChanges: return "Uncommitted Changes"
        case .testFailure: return "Test Failure"
        case .dependencyAlert: return "Dependency Alert"
        case .contextSwitch: return "Context Switch"
        case .codeReview: return "Code Review"
        case .branchStale: return "Branch Stale"
        case .endOfDayReview: return "End of Day Review"
        case .morningBrief: return "Morning Brief"
        case .focusReminder: return "Focus Reminder"
        case .relatedMemory: return "Related Memory"
        case .meetingPrep: return "Meeting Prep"
        case .commitAfterTests: return "Commit After Tests"
        case .pushAfterCommit: return "Push After Commit"
        case .reviewAfterManyEdits: return "Review Changes"
        case .runTests: return "Run Tests"
        case .runBuild: return "Build Project"
        case .commitChanges: return "Commit Changes"
        case .fixErrors: return "Fix Errors"
        case .fixLint: return "Fix Lint Issues"
        case .reviewCode: return "Review Code"
        }
    }

    var icon: String {
        switch self {
        case .uncommittedChanges: return "arrow.triangle.branch"
        case .testFailure: return "xmark.circle"
        case .dependencyAlert: return "exclamationmark.shield"
        case .contextSwitch: return "arrow.left.arrow.right"
        case .codeReview: return "doc.text.magnifyingglass"
        case .branchStale: return "clock.arrow.circlepath"
        case .endOfDayReview: return "sun.horizon"
        case .morningBrief: return "sunrise"
        case .focusReminder: return "timer"
        case .relatedMemory: return "brain.head.profile"
        case .meetingPrep: return "calendar"
        case .commitAfterTests: return "checkmark.circle"
        case .pushAfterCommit: return "arrow.up.circle"
        case .reviewAfterManyEdits: return "eye"
        case .runTests: return "checkmark.diamond"
        case .runBuild: return "hammer"
        case .commitChanges: return "vault"
        case .fixErrors: return "exclamationmark.triangle"
        case .fixLint: return "paintbrush"
        case .reviewCode: return "eye"
        }
    }

    var defaultUrgency: Int {
        switch self {
        case .testFailure: return 75
        case .dependencyAlert: return 70
        case .uncommittedChanges: return 55
        case .branchStale: return 50
        case .meetingPrep: return 65
        case .contextSwitch: return 45
        case .codeReview: return 50
        case .endOfDayReview: return 40
        case .morningBrief: return 35
        case .focusReminder: return 30
        case .relatedMemory: return 25
        case .commitAfterTests: return 50
        case .pushAfterCommit: return 45
        case .reviewAfterManyEdits: return 40
        case .runTests: return 55
        case .runBuild: return 50
        case .commitChanges: return 45
        case .fixErrors: return 70
        case .fixLint: return 35
        case .reviewCode: return 30
        }
    }

    /// Default staleness window after which the suggestion expires.
    var expiryInterval: TimeInterval {
        switch self {
        case .meetingPrep: return 1800         // 30 min
        case .testFailure, .fixErrors: return 3600  // 1 hour
        case .uncommittedChanges: return 14400 // 4 hours
        case .endOfDayReview: return 7200      // 2 hours
        case .morningBrief: return 10800       // 3 hours
        case .focusReminder: return 3600       // 1 hour
        default: return 28800                  // 8 hours
        }
    }

    /// Trigger source classification.
    var triggerSource: TriggerSource {
        switch self {
        case .uncommittedChanges, .branchStale, .codeReview:
            return .git
        case .testFailure, .runTests, .runBuild, .fixErrors, .fixLint, .commitChanges, .reviewCode:
            return .activity
        case .dependencyAlert:
            return .cron
        case .contextSwitch:
            return .ambient
        case .endOfDayReview, .morningBrief, .focusReminder:
            return .cron
        case .relatedMemory:
            return .memory
        case .meetingPrep:
            return .calendar
        case .commitAfterTests, .pushAfterCommit, .reviewAfterManyEdits:
            return .chain
        }
    }

    enum TriggerSource: String {
        case activity, git, cron, ambient, memory, calendar, chain
    }
}

// MARK: - Suggestion Factory

/// Factory methods for creating pre-configured suggestions.
enum SuggestionFactory {

    static func uncommittedChanges(fileCount: Int, hours: Int) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .uncommittedChanges,
            title: "Uncommitted Changes",
            detail: "\(fileCount) files changed over \(hours) hours without a commit.",
            prompt: "Review and commit the uncommitted changes with a descriptive message.",
            icon: ProactiveSuggestionType.uncommittedChanges.icon,
            urgency: UrgencyLevel(score: min(90, 40 + hours * 5)),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.uncommittedChanges.expiryInterval),
            chainOnSuccess: .pushAfterCommit
        )
    }

    static func testFailure(testName: String, error: String) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .testFailure,
            title: "Test Failure",
            detail: "Test '\(testName)' failed: \(String(error.prefix(100)))",
            prompt: "Diagnose and fix the failing test: \(testName). Error: \(error)",
            icon: ProactiveSuggestionType.testFailure.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.testFailure.defaultUrgency),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.testFailure.expiryInterval),
            chainOnSuccess: .commitAfterTests
        )
    }

    static func contextSwitch(fromProject: String, toProject: String) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .contextSwitch,
            title: "Context Switch",
            detail: "Switched from \(fromProject) to \(toProject). Here's where you left off.",
            prompt: "Recall my previous context in project \(toProject). What was I working on?",
            icon: ProactiveSuggestionType.contextSwitch.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.contextSwitch.defaultUrgency),
            expiresAt: Date().addingTimeInterval(1800)
        )
    }

    static func endOfDayReview() -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .endOfDayReview,
            title: "End of Day Review",
            detail: "Summarize today's work: files changed, tests run, commits made.",
            prompt: "Generate an end-of-day summary of all work done today in this project.",
            icon: ProactiveSuggestionType.endOfDayReview.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.endOfDayReview.defaultUrgency),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.endOfDayReview.expiryInterval)
        )
    }

    static func morningBrief() -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .morningBrief,
            title: "Morning Brief",
            detail: "Good morning! Here's what happened since you last left.",
            prompt: "Give me a morning briefing: what changed in the project overnight, any pending PRs, CI status.",
            icon: ProactiveSuggestionType.morningBrief.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.morningBrief.defaultUrgency),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.morningBrief.expiryInterval)
        )
    }

    static func focusReminder(fileName: String, minutes: Int) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .focusReminder,
            title: "Focus Check",
            detail: "You've been working on \(fileName) for \(minutes) minutes. Consider a commit checkpoint.",
            prompt: "I've been focused on \(fileName) for a while. Create a commit checkpoint and suggest next steps.",
            icon: ProactiveSuggestionType.focusReminder.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.focusReminder.defaultUrgency),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.focusReminder.expiryInterval)
        )
    }

    static func branchStale(behindBy: Int) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .branchStale,
            title: "Branch Behind",
            detail: "Your branch is \(behindBy) commits behind main. Consider rebasing.",
            prompt: "My branch is \(behindBy) commits behind main. Help me rebase safely.",
            icon: ProactiveSuggestionType.branchStale.icon,
            urgency: UrgencyLevel(score: min(80, 40 + behindBy * 3)),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.branchStale.expiryInterval)
        )
    }

    static func meetingPrep(eventTitle: String, minutesUntil: Int) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .meetingPrep,
            title: "Meeting in \(minutesUntil)min",
            detail: "'\(eventTitle)' starts soon. Prepare notes from recent context.",
            prompt: "Meeting '\(eventTitle)' starts in \(minutesUntil) minutes. Generate prep notes based on my recent work.",
            icon: ProactiveSuggestionType.meetingPrep.icon,
            urgency: UrgencyLevel(score: min(85, 50 + (30 - minutesUntil) * 2)),
            expiresAt: Date().addingTimeInterval(Double(minutesUntil * 60 + 300))
        )
    }

    static func relatedMemory(memoryContent: String) -> ProactiveSuggestion {
        ProactiveSuggestion(
            type: .relatedMemory,
            title: "Related Memory",
            detail: String(memoryContent.prefix(150)),
            prompt: "I found a relevant memory from a past conversation: \(memoryContent). How does this apply to what I'm currently doing?",
            icon: ProactiveSuggestionType.relatedMemory.icon,
            urgency: UrgencyLevel(score: ProactiveSuggestionType.relatedMemory.defaultUrgency),
            expiresAt: Date().addingTimeInterval(ProactiveSuggestionType.relatedMemory.expiryInterval)
        )
    }
}
