import XCTest
@testable import GRump

final class LiveActivityModelsTests: XCTestCase {

    // MARK: - AgentTaskAttributes

    func testAgentTaskAttributesCreation() {
        let attrs = AgentTaskAttributes(
            conversationId: "conv-123",
            conversationTitle: "Build Feature",
            modelName: "claude-sonnet-4",
            startedAt: Date()
        )
        XCTAssertEqual(attrs.conversationId, "conv-123")
        XCTAssertEqual(attrs.conversationTitle, "Build Feature")
        XCTAssertEqual(attrs.modelName, "claude-sonnet-4")
    }

    // MARK: - ContentState

    func testContentStateProgressFraction() {
        let state = AgentTaskAttributes.ContentState(
            currentStep: "Reading file",
            stepNumber: 3,
            totalSteps: 10,
            status: .running,
            elapsedSeconds: 15
        )
        XCTAssertEqual(state.progressFraction, 0.3, accuracy: 0.001)
    }

    func testContentStateProgressFractionZeroTotal() {
        let state = AgentTaskAttributes.ContentState(
            currentStep: "Starting",
            stepNumber: 0,
            totalSteps: 0,
            status: .running,
            elapsedSeconds: 0
        )
        XCTAssertEqual(state.progressFraction, 0.0)
    }

    func testContentStateProgressFractionComplete() {
        let state = AgentTaskAttributes.ContentState(
            currentStep: "Done",
            stepNumber: 5,
            totalSteps: 5,
            status: .completed,
            elapsedSeconds: 30
        )
        XCTAssertEqual(state.progressFraction, 1.0, accuracy: 0.001)
    }

    // MARK: - AgentStatus

    func testAgentStatusRawValues() {
        XCTAssertEqual(AgentTaskAttributes.ContentState.AgentStatus.running.rawValue, "running")
        XCTAssertEqual(AgentTaskAttributes.ContentState.AgentStatus.paused.rawValue, "paused")
        XCTAssertEqual(AgentTaskAttributes.ContentState.AgentStatus.completed.rawValue, "completed")
        XCTAssertEqual(AgentTaskAttributes.ContentState.AgentStatus.failed.rawValue, "failed")
    }

    // MARK: - LiveActivityManager

    @MainActor func testLiveActivityManagerSharedInstance() {
        let manager = LiveActivityManager.shared
        XCTAssertNotNil(manager)
    }

    @MainActor func testLiveActivityManagerInitialState() {
        let manager = LiveActivityManager.shared
        XCTAssertFalse(manager.isActivityActive)
    }

    @MainActor func testLiveActivityManagerStartAndEnd() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test Chat",
            modelName: "test-model",
            initialStep: "Initializing"
        )
        XCTAssertTrue(manager.isActivityActive)

        manager.endActivity(
            finalStep: "Complete",
            stepNumber: 5,
            totalSteps: 5,
            success: true,
            elapsedSeconds: 10
        )
        XCTAssertFalse(manager.isActivityActive)
    }

    @MainActor func testLiveActivityManagerUpdateProgress() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test",
            modelName: "model",
            initialStep: "Start"
        )
        manager.updateProgress(
            currentStep: "Step 2",
            stepNumber: 2,
            totalSteps: 10,
            elapsedSeconds: 5
        )
        XCTAssertTrue(manager.isActivityActive)

        // Clean up
        manager.cancelActivity()
    }

    @MainActor func testLiveActivityManagerPause() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test",
            modelName: "model",
            initialStep: "Start"
        )
        manager.pauseActivity(
            currentStep: "Paused",
            stepNumber: 3,
            totalSteps: 10,
            elapsedSeconds: 8
        )
        XCTAssertTrue(manager.isActivityActive)

        // Clean up
        manager.cancelActivity()
    }

    @MainActor func testLiveActivityManagerCancel() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test",
            modelName: "model",
            initialStep: "Start"
        )
        XCTAssertTrue(manager.isActivityActive)
        manager.cancelActivity()
        XCTAssertFalse(manager.isActivityActive)
    }

    @MainActor func testLiveActivityManagerProgressFraction() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test",
            modelName: "model",
            initialStep: "Start"
        )
        manager.updateProgress(
            currentStep: "Step 4",
            stepNumber: 4,
            totalSteps: 8,
            elapsedSeconds: 12
        )
        XCTAssertEqual(manager.progressFraction, 0.5, accuracy: 0.001)

        // Clean up
        manager.cancelActivity()
    }

    @MainActor func testLiveActivityManagerEndWithFailure() {
        let manager = LiveActivityManager.shared
        manager.startAgentActivity(
            conversationId: UUID(),
            conversationTitle: "Test",
            modelName: "model",
            initialStep: "Start"
        )
        manager.endActivity(
            finalStep: "Error occurred",
            stepNumber: 2,
            totalSteps: 10,
            success: false,
            elapsedSeconds: 5
        )
        XCTAssertFalse(manager.isActivityActive)
    }
}
