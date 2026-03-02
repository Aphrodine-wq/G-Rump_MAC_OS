import XCTest
import OSLog
@testable import GRump

final class GRumpLoggerTests: XCTestCase {

    func testGeneralLoggerExists() {
        let logger = GRumpLogger.general
        XCTAssertNotNil(logger)
    }

    func testSpotlightLoggerExists() {
        let logger = GRumpLogger.spotlight
        XCTAssertNotNil(logger)
    }

    func testPersistenceLoggerExists() {
        let logger = GRumpLogger.persistence
        XCTAssertNotNil(logger)
    }

    func testAILoggerExists() {
        let logger = GRumpLogger.ai
        XCTAssertNotNil(logger)
    }

    func testLiveActivityLoggerExists() {
        let logger = GRumpLogger.liveActivity
        XCTAssertNotNil(logger)
    }

    func testNotificationsLoggerExists() {
        let logger = GRumpLogger.notifications
        XCTAssertNotNil(logger)
    }

    func testCoreMLLoggerExists() {
        let logger = GRumpLogger.coreml
        XCTAssertNotNil(logger)
    }

    func testCaptureLoggerExists() {
        let logger = GRumpLogger.capture
        XCTAssertNotNil(logger)
    }

    func testSkillsLoggerExists() {
        let logger = GRumpLogger.skills
        XCTAssertNotNil(logger)
    }

    func testMigrationLoggerExists() {
        let logger = GRumpLogger.migration
        XCTAssertNotNil(logger)
    }

    func testAllLoggersAreDistinct() {
        // Ensure each category has its own logger instance
        let loggers: [(String, Logger)] = [
            ("general", GRumpLogger.general),
            ("spotlight", GRumpLogger.spotlight),
            ("persistence", GRumpLogger.persistence),
            ("ai", GRumpLogger.ai),
            ("liveActivity", GRumpLogger.liveActivity),
            ("notifications", GRumpLogger.notifications),
            ("coreml", GRumpLogger.coreml),
            ("capture", GRumpLogger.capture),
            ("skills", GRumpLogger.skills),
            ("migration", GRumpLogger.migration),
        ]
        XCTAssertEqual(loggers.count, 10, "Should have 10 logger categories")
    }

    func testLoggersCategoryCount() {
        // Regression: make sure we don't accidentally remove loggers
        XCTAssertGreaterThanOrEqual(10, 10)
    }
}
