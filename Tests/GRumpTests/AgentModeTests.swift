import XCTest
@testable import GRump

@MainActor
final class AgentModeTests: XCTestCase {

    func testAllModesHaveDisplayNames() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode.rawValue) missing displayName")
        }
    }

    func testAllModesHaveIcons() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.icon.isEmpty, "\(mode.rawValue) missing icon")
        }
    }

    func testAllModesHaveDescriptions() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.description.isEmpty, "\(mode.rawValue) missing description")
        }
    }

    func testAllModesHaveToastMessages() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.toastMessage.isEmpty, "\(mode.rawValue) missing toastMessage")
        }
    }

    func testModeCodableRoundTrip() throws {
        for mode in AgentMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AgentMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testModeCount() {
        // Ensure we don't accidentally drop a mode
        XCTAssertEqual(AgentMode.allCases.count, 6, "Expected 6 modes: Chat, Plan, Build, Debate, Spec, Parallel")
    }

    func testModeRawValues() {
        XCTAssertEqual(AgentMode.standard.rawValue, "standard")
        XCTAssertEqual(AgentMode.plan.rawValue, "plan")
        XCTAssertEqual(AgentMode.fullStack.rawValue, "fullStack")
        XCTAssertEqual(AgentMode.argue.rawValue, "argue")
        XCTAssertEqual(AgentMode.spec.rawValue, "spec")
        XCTAssertEqual(AgentMode.parallel.rawValue, "parallel")
    }
}
