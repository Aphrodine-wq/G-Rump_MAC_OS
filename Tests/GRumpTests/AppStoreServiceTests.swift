import XCTest
@testable import GRump

final class AppStoreServiceTests: XCTestCase {

    // MARK: - AppStoreCheck Model

    func testCheckCategories() {
        let categories = AppStoreCheck.CheckCategory.allCases
        XCTAssertEqual(categories.count, 6)
        XCTAssertTrue(categories.contains(.icons))
        XCTAssertTrue(categories.contains(.privacy))
        XCTAssertTrue(categories.contains(.entitlements))
        XCTAssertTrue(categories.contains(.infoPlist))
        XCTAssertTrue(categories.contains(.deployment))
        XCTAssertTrue(categories.contains(.localization))
    }

    func testCheckCategoryRawValues() {
        XCTAssertEqual(AppStoreCheck.CheckCategory.icons.rawValue, "Icons")
        XCTAssertEqual(AppStoreCheck.CheckCategory.privacy.rawValue, "Privacy")
        XCTAssertEqual(AppStoreCheck.CheckCategory.entitlements.rawValue, "Entitlements")
        XCTAssertEqual(AppStoreCheck.CheckCategory.infoPlist.rawValue, "Info.plist")
        XCTAssertEqual(AppStoreCheck.CheckCategory.deployment.rawValue, "Deployment")
        XCTAssertEqual(AppStoreCheck.CheckCategory.localization.rawValue, "Localization")
    }

    func testCheckCategoryIcons() {
        for category in AppStoreCheck.CheckCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) missing icon")
        }
    }

    func testCheckStatusIcons() {
        let statuses: [AppStoreCheck.CheckStatus] = [.pass, .fail, .warning, .notChecked]
        for status in statuses {
            XCTAssertFalse(status.icon.isEmpty, "Status missing icon")
        }
    }

    func testCheckStatusPassIcon() {
        XCTAssertEqual(AppStoreCheck.CheckStatus.pass.icon, "checkmark.circle.fill")
    }

    func testCheckStatusFailIcon() {
        XCTAssertEqual(AppStoreCheck.CheckStatus.fail.icon, "xmark.circle.fill")
    }

    func testCheckStatusWarningIcon() {
        XCTAssertEqual(AppStoreCheck.CheckStatus.warning.icon, "exclamationmark.triangle.fill")
    }

    func testCheckCreation() {
        let check = AppStoreCheck(
            id: "test-check",
            title: "Test Check",
            category: .icons,
            status: .pass,
            detail: "All icons present"
        )
        XCTAssertEqual(check.id, "test-check")
        XCTAssertEqual(check.title, "Test Check")
        XCTAssertEqual(check.category, .icons)
        XCTAssertEqual(check.status, .pass)
        XCTAssertEqual(check.detail, "All icons present")
    }

    // MARK: - performChecks

    func testPerformChecksOnProjectDirectory() {
        let projectDir = "/Users/jameswalton/Documents/G-Rump"
        let checks = AppStoreService.performChecks(dir: projectDir)
        XCTAssertFalse(checks.isEmpty, "Should return at least one check result")

        // Should find the app icon
        let iconCheck = checks.first(where: { $0.id == "app-icon" })
        XCTAssertNotNil(iconCheck)
        XCTAssertEqual(iconCheck?.status, .pass, "Should find AppIcon.appiconset in project")

        // Should find entitlements
        let entCheck = checks.first(where: { $0.id == "entitlements" })
        XCTAssertNotNil(entCheck)
        XCTAssertEqual(entCheck?.status, .pass, "Should find entitlements file")

        // Should find deployment targets
        let deployCheck = checks.first(where: { $0.id == "deployment" })
        XCTAssertNotNil(deployCheck)
    }

    func testPerformChecksOnEmptyDirectory() {
        let tempDir = NSTemporaryDirectory() + "GRumpTest-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let checks = AppStoreService.performChecks(dir: tempDir)
        // Should still return checks (mostly failing)
        XCTAssertFalse(checks.isEmpty)

        let iconCheck = checks.first(where: { $0.id == "app-icon" })
        XCTAssertNotNil(iconCheck)
        XCTAssertEqual(iconCheck?.status, .fail, "Empty dir should fail app icon check")
    }

    func testPerformChecksOnNonexistentDirectory() {
        let checks = AppStoreService.performChecks(dir: "/nonexistent/path/that/does/not/exist")
        // Should not crash, may return empty or failed checks
        XCTAssertTrue(checks.isEmpty || checks.allSatisfy { $0.status == .fail || $0.status == .warning })
    }

    // MARK: - AppStoreService Lifecycle

    @MainActor
    func testServiceInitialState() {
        let service = AppStoreService()
        XCTAssertTrue(service.checks.isEmpty)
        XCTAssertFalse(service.isRunning)
        XCTAssertEqual(service.archiveLog, "")
        XCTAssertFalse(service.isArchiving)
    }
}
