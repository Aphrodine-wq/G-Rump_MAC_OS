import XCTest
@testable import GRump

final class ParallelAgentStateTests: XCTestCase {

    // MARK: - ParallelAgentState

    func testParallelAgentStateCreation() {
        let state = ParallelAgentState(
            id: "agent-1",
            agentIndex: 1,
            taskDescription: "Implement login flow",
            taskType: .codeGen,
            modelName: "claude-sonnet-4"
        )
        XCTAssertEqual(state.id, "agent-1")
        XCTAssertEqual(state.agentIndex, 1)
        XCTAssertEqual(state.taskDescription, "Implement login flow")
        XCTAssertEqual(state.taskType, .codeGen)
        XCTAssertEqual(state.modelName, "claude-sonnet-4")
        XCTAssertEqual(state.status, .pending)
        XCTAssertEqual(state.streamingText, "")
        XCTAssertNil(state.result)
    }

    func testParallelAgentStateMutation() {
        var state = ParallelAgentState(
            id: "agent-2",
            agentIndex: 2,
            taskDescription: "Write tests",
            taskType: .testing,
            modelName: "gemini-2.5-flash"
        )
        state.status = .running
        state.streamingText = "Working on it..."
        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.streamingText, "Working on it...")

        state.status = .completed
        state.result = "Tests written successfully"
        XCTAssertEqual(state.status, .completed)
        XCTAssertEqual(state.result, "Tests written successfully")
    }

    // MARK: - TaskType

    func testTaskTypeAllCases() {
        let cases = TaskType.allCases
        XCTAssertEqual(cases.count, 12)
        XCTAssertTrue(cases.contains(.reasoning))
        XCTAssertTrue(cases.contains(.planning))
        XCTAssertTrue(cases.contains(.fileOps))
        XCTAssertTrue(cases.contains(.search))
        XCTAssertTrue(cases.contains(.codeGen))
        XCTAssertTrue(cases.contains(.synthesis))
        XCTAssertTrue(cases.contains(.writing))
        XCTAssertTrue(cases.contains(.web))
        XCTAssertTrue(cases.contains(.research))
        XCTAssertTrue(cases.contains(.testing))
        XCTAssertTrue(cases.contains(.debugging))
        XCTAssertTrue(cases.contains(.general))
    }

    func testTaskTypeDisplayNames() {
        for taskType in TaskType.allCases {
            XCTAssertFalse(taskType.displayName.isEmpty, "\(taskType.rawValue) missing displayName")
        }
    }

    func testTaskTypeIcons() {
        for taskType in TaskType.allCases {
            XCTAssertFalse(taskType.icon.isEmpty, "\(taskType.rawValue) missing icon")
        }
    }

    func testTaskTypeCodable() throws {
        for taskType in TaskType.allCases {
            let data = try JSONEncoder().encode(taskType)
            let decoded = try JSONDecoder().decode(TaskType.self, from: data)
            XCTAssertEqual(decoded, taskType)
        }
    }
}
