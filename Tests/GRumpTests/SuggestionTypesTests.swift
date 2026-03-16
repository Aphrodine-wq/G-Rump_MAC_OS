import XCTest
@testable import GRump

/// Tests for ProactiveSuggestionType and SuggestionFactory.
final class SuggestionTypesTests: XCTestCase {

    // MARK: - ProactiveSuggestionType Properties

    func testAllCasesExist() {
        XCTAssertGreaterThanOrEqual(ProactiveSuggestionType.allCases.count, 20)
    }

    func testAllTypesHaveDisplayNames() {
        for type in ProactiveSuggestionType.allCases {
            XCTAssertFalse(type.displayName.isEmpty,
                "\(type.rawValue) has empty displayName")
        }
    }

    func testDisplayNamesStartCapitalized() {
        for type in ProactiveSuggestionType.allCases {
            let first = type.displayName.first!
            XCTAssertTrue(first.isUppercase || first.isNumber,
                "\(type.rawValue) displayName '\(type.displayName)' should start uppercase")
        }
    }

    func testAllTypesHaveIcons() {
        for type in ProactiveSuggestionType.allCases {
            XCTAssertFalse(type.icon.isEmpty,
                "\(type.rawValue) has empty icon")
        }
    }

    func testAllTypesHaveUrgency() {
        for type in ProactiveSuggestionType.allCases {
            XCTAssertGreaterThan(type.defaultUrgency, 0,
                "\(type.rawValue) has 0 urgency")
            XCTAssertLessThanOrEqual(type.defaultUrgency, 100,
                "\(type.rawValue) urgency too high")
        }
    }

    func testAllTypesHaveExpiryInterval() {
        for type in ProactiveSuggestionType.allCases {
            XCTAssertGreaterThan(type.expiryInterval, 0,
                "\(type.rawValue) has 0 expiry")
        }
    }

    func testAllTypesHaveTriggerSource() {
        for type in ProactiveSuggestionType.allCases {
            let source = type.triggerSource
            XCTAssertFalse(source.rawValue.isEmpty,
                "\(type.rawValue) has empty trigger source")
        }
    }

    func testTriggerSourceCoverage() {
        let allSources = Set(ProactiveSuggestionType.allCases.map(\.triggerSource))
        // Should have at least activity, git, cron, and chain sources
        XCTAssertTrue(allSources.contains(.activity))
        XCTAssertTrue(allSources.contains(.git))
        XCTAssertTrue(allSources.contains(.cron))
        XCTAssertTrue(allSources.contains(.chain))
    }

    func testRawValuesAreUnique() {
        let rawValues = ProactiveSuggestionType.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    // MARK: - Specific Types

    func testTestFailureHasHighUrgency() {
        XCTAssertGreaterThanOrEqual(ProactiveSuggestionType.testFailure.defaultUrgency, 70)
    }

    func testEndOfDayReviewIsCronTriggered() {
        XCTAssertEqual(ProactiveSuggestionType.endOfDayReview.triggerSource, .cron)
    }

    func testCommitAfterTestsIsChainTriggered() {
        XCTAssertEqual(ProactiveSuggestionType.commitAfterTests.triggerSource, .chain)
    }

    func testRelatedMemoryIsMemoryTriggered() {
        XCTAssertEqual(ProactiveSuggestionType.relatedMemory.triggerSource, .memory)
    }

    // MARK: - SuggestionFactory

    func testUncommittedChangesFactory() {
        let suggestion = SuggestionFactory.uncommittedChanges(fileCount: 5, hours: 2)
        XCTAssertEqual(suggestion.type, .uncommittedChanges)
        XCTAssertFalse(suggestion.title.isEmpty)
        XCTAssertTrue(suggestion.detail.contains("5"))
        XCTAssertTrue(suggestion.detail.contains("2"))
    }

    func testTestFailureFactory() {
        let suggestion = SuggestionFactory.testFailure(testName: "testLogin", error: "assertion failed")
        XCTAssertEqual(suggestion.type, .testFailure)
        XCTAssertTrue(suggestion.detail.contains("testLogin"))
        // Should chain to commit after tests
        XCTAssertEqual(suggestion.chainOnSuccess, .commitAfterTests)
    }

    func testContextSwitchFactory() {
        let suggestion = SuggestionFactory.contextSwitch(fromProject: "AppA", toProject: "AppB")
        XCTAssertEqual(suggestion.type, .contextSwitch)
        XCTAssertTrue(suggestion.detail.contains("AppA") || suggestion.detail.contains("AppB"))
    }

    func testEndOfDayReviewFactory() {
        let suggestion = SuggestionFactory.endOfDayReview()
        XCTAssertEqual(suggestion.type, .endOfDayReview)
        XCTAssertFalse(suggestion.title.isEmpty)
    }

    func testMorningBriefFactory() {
        let suggestion = SuggestionFactory.morningBrief()
        XCTAssertEqual(suggestion.type, .morningBrief)
        XCTAssertTrue(suggestion.detail.lowercased().contains("morning"))
    }

    func testFocusReminderFactory() {
        let suggestion = SuggestionFactory.focusReminder(fileName: "main.swift", minutes: 45)
        XCTAssertEqual(suggestion.type, ProactiveSuggestionType.focusReminder)
    }

    func testBranchStaleFactory() {
        let suggestion = SuggestionFactory.branchStale(behindBy: 15)
        XCTAssertEqual(suggestion.type, .branchStale)
        XCTAssertTrue(suggestion.detail.contains("15"))
    }

    func testRelatedMemoryFactory() {
        let suggestion = SuggestionFactory.relatedMemory(memoryContent: "Previously fixed similar auth bug")
        XCTAssertEqual(suggestion.type, .relatedMemory)
        XCTAssertTrue(suggestion.detail.contains("auth"))
    }

    func testMeetingPrepFactory() {
        let suggestion = SuggestionFactory.meetingPrep(eventTitle: "Sprint Review", minutesUntil: 15)
        XCTAssertEqual(suggestion.type, ProactiveSuggestionType.meetingPrep)
        XCTAssertTrue(suggestion.detail.contains("Sprint Review"))
    }

    // MARK: - Suggestion Properties

    func testFactorySuggestionsHaveExpiry() {
        let suggestion = SuggestionFactory.endOfDayReview()
        XCTAssertNotNil(suggestion.expiresAt)
        XCTAssertTrue(suggestion.expiresAt! > Date())
    }

    func testFactorySuggestionsHaveIcons() {
        let suggestion = SuggestionFactory.testFailure(testName: "t", error: "e")
        XCTAssertFalse(suggestion.icon.isEmpty)
    }

    // MARK: - TriggerSource

    func testTriggerSourceRawValues() {
        let sources: [ProactiveSuggestionType.TriggerSource] = [
            .activity, .git, .cron, .ambient, .memory, .calendar, .chain
        ]
        XCTAssertEqual(sources.count, 7)
        for source in sources {
            XCTAssertFalse(source.rawValue.isEmpty)
        }
    }
}
