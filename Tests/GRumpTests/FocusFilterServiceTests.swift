import XCTest
@testable import GRump

final class FocusFilterServiceTests: XCTestCase {

    // MARK: - FocusMode

    func testFocusModeAllCases() {
        let cases = FocusMode.allCases
        XCTAssertEqual(cases.count, 9)
        XCTAssertTrue(cases.contains(.none))
        XCTAssertTrue(cases.contains(.work))
        XCTAssertTrue(cases.contains(.personal))
        XCTAssertTrue(cases.contains(.sleep))
        XCTAssertTrue(cases.contains(.driving))
        XCTAssertTrue(cases.contains(.exercise))
        XCTAssertTrue(cases.contains(.mindfulness))
        XCTAssertTrue(cases.contains(.reading))
        XCTAssertTrue(cases.contains(.gaming))
    }

    func testFocusModeRawValues() {
        XCTAssertEqual(FocusMode.none.rawValue, "none")
        XCTAssertEqual(FocusMode.work.rawValue, "work")
        XCTAssertEqual(FocusMode.personal.rawValue, "personal")
        XCTAssertEqual(FocusMode.sleep.rawValue, "sleep")
        XCTAssertEqual(FocusMode.driving.rawValue, "driving")
        XCTAssertEqual(FocusMode.exercise.rawValue, "exercise")
        XCTAssertEqual(FocusMode.mindfulness.rawValue, "mindfulness")
        XCTAssertEqual(FocusMode.reading.rawValue, "reading")
        XCTAssertEqual(FocusMode.gaming.rawValue, "gaming")
    }

    func testFocusModeDisplayNames() {
        for mode in FocusMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode.rawValue) missing displayName")
            XCTAssertEqual(mode.displayName, mode.rawValue.capitalized)
        }
    }

    func testFocusModeIcons() {
        for mode in FocusMode.allCases {
            XCTAssertFalse(mode.icon.isEmpty, "\(mode.rawValue) missing icon")
        }
    }

    func testFocusModeIconsUnique() {
        let icons = FocusMode.allCases.map(\.icon)
        let unique = Set(icons)
        XCTAssertEqual(icons.count, unique.count, "FocusMode icons should be unique")
    }

    func testFocusModeIdentifiable() {
        for mode in FocusMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testFocusModeCodable() throws {
        for mode in FocusMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(FocusMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    // MARK: - FocusNotificationCategory

    func testNotificationCategoryAllCases() {
        let cases = FocusNotificationCategory.allCases
        XCTAssertEqual(cases.count, 4)
        XCTAssertTrue(cases.contains(.taskComplete))
        XCTAssertTrue(cases.contains(.taskFailed))
        XCTAssertTrue(cases.contains(.approvalNeeded))
        XCTAssertTrue(cases.contains(.buildResult))
    }

    func testNotificationCategoryRawValues() {
        XCTAssertEqual(FocusNotificationCategory.taskComplete.rawValue, "GRUMP_TASK_COMPLETE")
        XCTAssertEqual(FocusNotificationCategory.taskFailed.rawValue, "GRUMP_TASK_FAILED")
        XCTAssertEqual(FocusNotificationCategory.approvalNeeded.rawValue, "GRUMP_APPROVAL_NEEDED")
        XCTAssertEqual(FocusNotificationCategory.buildResult.rawValue, "GRUMP_BUILD_RESULT")
    }

    func testNotificationCategoryDisplayNames() {
        for category in FocusNotificationCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category.rawValue) missing displayName")
        }
    }

    func testNotificationCategoryCodable() throws {
        for category in FocusNotificationCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(FocusNotificationCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - FocusConfiguration

    func testFocusConfigurationDefault() {
        let config = FocusConfiguration.default
        XCTAssertEqual(config.allowedNotifications.count, FocusNotificationCategory.allCases.count)
        XCTAssertEqual(config.agentModeId, "chat")
        XCTAssertFalse(config.autoStartAgent)
        XCTAssertTrue(config.showDistractions)
        XCTAssertTrue(config.enableSounds)
        XCTAssertTrue(config.suggestedSkills.isEmpty)
    }

    func testFocusConfigurationCodable() throws {
        let config = FocusConfiguration(
            allowedNotifications: [.taskComplete, .buildResult],
            agentModeId: "build",
            autoStartAgent: true,
            showDistractions: false,
            enableSounds: false,
            suggestedSkills: ["swift", "testing"]
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(FocusConfiguration.self, from: data)
        XCTAssertEqual(decoded.allowedNotifications, [.taskComplete, .buildResult])
        XCTAssertEqual(decoded.agentModeId, "build")
        XCTAssertTrue(decoded.autoStartAgent)
        XCTAssertFalse(decoded.showDistractions)
        XCTAssertFalse(decoded.enableSounds)
        XCTAssertEqual(decoded.suggestedSkills, ["swift", "testing"])
    }

    // MARK: - FocusFilterService Configuration

    @MainActor func testWorkFocusConfiguration() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .work)
        XCTAssertTrue(config.autoStartAgent)
        XCTAssertFalse(config.showDistractions)
        XCTAssertFalse(config.enableSounds)
        XCTAssertEqual(config.agentModeId, "build")
        XCTAssertTrue(config.allowedNotifications.contains(.taskComplete))
        XCTAssertTrue(config.allowedNotifications.contains(.buildResult))
    }

    @MainActor func testPersonalFocusConfiguration() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .personal)
        XCTAssertFalse(config.autoStartAgent)
        XCTAssertTrue(config.showDistractions)
        XCTAssertTrue(config.enableSounds)
        XCTAssertEqual(config.agentModeId, "chat")
    }

    @MainActor func testReadingFocusConfiguration() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .reading)
        XCTAssertFalse(config.autoStartAgent)
        XCTAssertFalse(config.showDistractions)
        XCTAssertFalse(config.enableSounds)
        XCTAssertEqual(config.agentModeId, "spec")
    }

    @MainActor func testGamingFocusConfiguration() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .gaming)
        XCTAssertFalse(config.autoStartAgent)
        XCTAssertTrue(config.showDistractions)
        XCTAssertTrue(config.enableSounds)
        XCTAssertTrue(config.allowedNotifications.isEmpty)
    }

    @MainActor func testNoneFocusReturnsDefault() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .none)
        let defaultConfig = FocusConfiguration.default
        XCTAssertEqual(config.agentModeId, defaultConfig.agentModeId)
        XCTAssertEqual(config.autoStartAgent, defaultConfig.autoStartAgent)
        XCTAssertEqual(config.showDistractions, defaultConfig.showDistractions)
        XCTAssertEqual(config.enableSounds, defaultConfig.enableSounds)
    }

    @MainActor func testSleepFocusReturnsDefault() {
        let service = FocusFilterService.shared
        let config = service.getConfiguration(for: .sleep)
        XCTAssertEqual(config.agentModeId, "chat")
        XCTAssertFalse(config.autoStartAgent)
    }
}
