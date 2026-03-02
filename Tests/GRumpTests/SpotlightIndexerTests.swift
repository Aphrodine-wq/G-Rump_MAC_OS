import XCTest
@testable import GRump

final class SpotlightIndexerTests: XCTestCase {

    // MARK: - GRumpActivityType Constants

    func testConversationActivityType() {
        XCTAssertEqual(GRumpActivityType.conversation, "com.grump.conversation")
    }

    func testAgentTaskActivityType() {
        XCTAssertEqual(GRumpActivityType.agentTask, "com.grump.agentTask")
    }

    func testSpotlightDomain() {
        XCTAssertEqual(GRumpActivityType.spotlightDomain, "com.grump.conversations")
    }

    func testActivityTypesAreUnique() {
        let types = [
            GRumpActivityType.conversation,
            GRumpActivityType.agentTask,
            GRumpActivityType.spotlightDomain,
        ]
        XCTAssertEqual(types.count, Set(types).count)
    }

    func testActivityTypesHaveGrumpPrefix() {
        let types = [
            GRumpActivityType.conversation,
            GRumpActivityType.agentTask,
            GRumpActivityType.spotlightDomain,
        ]
        for t in types {
            XCTAssertTrue(t.hasPrefix("com.grump."), "\(t) should start with com.grump.")
        }
    }

    // MARK: - SpotlightIndexer Singleton

    @MainActor
    func testSharedInstanceExists() {
        let indexer = SpotlightIndexer.shared
        XCTAssertNotNil(indexer)
    }

    @MainActor
    func testSharedInstanceIsSingleton() {
        let a = SpotlightIndexer.shared
        let b = SpotlightIndexer.shared
        XCTAssertTrue(a === b)
    }
}
