import XCTest
@testable import GRump

final class NotificationServiceTests: XCTestCase {

    // MARK: - Notification Categories

    func testTaskCompleteCategoryExists() {
        XCTAssertEqual(GRumpNotificationCategory.taskComplete, "GRUMP_TASK_COMPLETE")
    }

    func testTaskFailedCategoryExists() {
        XCTAssertEqual(GRumpNotificationCategory.taskFailed, "GRUMP_TASK_FAILED")
    }

    func testApprovalNeededCategoryExists() {
        XCTAssertEqual(GRumpNotificationCategory.approvalNeeded, "GRUMP_APPROVAL_NEEDED")
    }

    func testBuildResultCategoryExists() {
        XCTAssertEqual(GRumpNotificationCategory.buildResult, "GRUMP_BUILD_RESULT")
    }

    func testAgentProgressCategoryExists() {
        XCTAssertEqual(GRumpNotificationCategory.agentProgress, "GRUMP_AGENT_PROGRESS")
    }

    func testAllCategoriesAreUnique() {
        let categories = [
            GRumpNotificationCategory.taskComplete,
            GRumpNotificationCategory.taskFailed,
            GRumpNotificationCategory.approvalNeeded,
            GRumpNotificationCategory.buildResult,
            GRumpNotificationCategory.agentProgress,
        ]
        XCTAssertEqual(categories.count, Set(categories).count)
    }

    func testAllCategoriesHaveGRUMPPrefix() {
        let categories = [
            GRumpNotificationCategory.taskComplete,
            GRumpNotificationCategory.taskFailed,
            GRumpNotificationCategory.approvalNeeded,
            GRumpNotificationCategory.buildResult,
            GRumpNotificationCategory.agentProgress,
        ]
        for cat in categories {
            XCTAssertTrue(cat.hasPrefix("GRUMP_"), "\(cat) should have GRUMP_ prefix")
        }
    }

    // MARK: - Notification Actions

    func testViewResultAction() {
        XCTAssertEqual(GRumpNotificationAction.viewResult, "VIEW_RESULT")
    }

    func testRunAgainAction() {
        XCTAssertEqual(GRumpNotificationAction.runAgain, "RUN_AGAIN")
    }

    func testOpenConversationAction() {
        XCTAssertEqual(GRumpNotificationAction.openConversation, "OPEN_CONVERSATION")
    }

    func testApproveAction() {
        XCTAssertEqual(GRumpNotificationAction.approveAction, "APPROVE_ACTION")
    }

    func testDenyAction() {
        XCTAssertEqual(GRumpNotificationAction.denyAction, "DENY_ACTION")
    }

    func testViewBuildLogAction() {
        XCTAssertEqual(GRumpNotificationAction.viewBuildLog, "VIEW_BUILD_LOG")
    }

    func testAllActionsAreUnique() {
        let actions = [
            GRumpNotificationAction.viewResult,
            GRumpNotificationAction.runAgain,
            GRumpNotificationAction.openConversation,
            GRumpNotificationAction.approveAction,
            GRumpNotificationAction.denyAction,
            GRumpNotificationAction.viewBuildLog,
        ]
        XCTAssertEqual(actions.count, Set(actions).count)
    }

    // MARK: - Notification Service Singleton

    @MainActor
    func testSharedInstanceExists() {
        let service = GRumpNotificationService.shared
        XCTAssertNotNil(service)
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let a = GRumpNotificationService.shared
        let b = GRumpNotificationService.shared
        XCTAssertTrue(a === b)
    }
}
