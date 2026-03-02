import XCTest
@testable import GRump

final class MessageModelTests: XCTestCase {

    // MARK: - Message Creation

    func testMessageDefaultValues() {
        let msg = Message(role: .user, content: "Hello")
        XCTAssertFalse(msg.id.uuidString.isEmpty)
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertNil(msg.toolCallId)
        XCTAssertNil(msg.toolCalls)
        XCTAssertNil(msg.parentMessageId)
        XCTAssertNil(msg.branchId)
        XCTAssertNil(msg.threadId)
        XCTAssertFalse(msg.isBranch)
        XCTAssertNil(msg.branchName)
        XCTAssertTrue(msg.children.isEmpty)
    }

    func testMessageAllRoles() {
        let roles: [Message.Role] = [.user, .assistant, .system, .tool]
        for role in roles {
            let msg = Message(role: role, content: "test")
            XCTAssertEqual(msg.role, role)
        }
    }

    func testMessageRoleRawValues() {
        XCTAssertEqual(Message.Role.user.rawValue, "user")
        XCTAssertEqual(Message.Role.assistant.rawValue, "assistant")
        XCTAssertEqual(Message.Role.system.rawValue, "system")
        XCTAssertEqual(Message.Role.tool.rawValue, "tool")
    }

    func testMessageWithToolCallId() {
        let msg = Message(role: .tool, content: "result", toolCallId: "call_123")
        XCTAssertEqual(msg.toolCallId, "call_123")
        XCTAssertEqual(msg.role, .tool)
    }

    func testMessageWithToolCalls() {
        let tc = ToolCall(id: "tc1", name: "read_file", arguments: "{\"path\":\"/tmp/test\"}")
        let msg = Message(role: .assistant, content: "", toolCalls: [tc])
        XCTAssertEqual(msg.toolCalls?.count, 1)
        XCTAssertEqual(msg.toolCalls?[0].name, "read_file")
    }

    func testMessageWithMultipleToolCalls() {
        let calls = [
            ToolCall(id: "tc1", name: "read_file", arguments: "{}"),
            ToolCall(id: "tc2", name: "write_file", arguments: "{}"),
            ToolCall(id: "tc3", name: "run_command", arguments: "{}"),
        ]
        let msg = Message(role: .assistant, content: "Let me do several things", toolCalls: calls)
        XCTAssertEqual(msg.toolCalls?.count, 3)
    }

    // MARK: - Message Codable

    func testMessageCodableAllRoles() throws {
        for role in [Message.Role.user, .assistant, .system, .tool] {
            let msg = Message(role: role, content: "Content for \(role.rawValue)")
            let data = try JSONEncoder().encode(msg)
            let decoded = try JSONDecoder().decode(Message.self, from: data)
            XCTAssertEqual(decoded.role, role)
            XCTAssertEqual(decoded.content, msg.content)
            XCTAssertEqual(decoded.id, msg.id)
        }
    }

    func testMessageCodableWithToolCalls() throws {
        let tc = ToolCall(id: "tc1", name: "grep_search", arguments: "{\"query\":\"hello\"}")
        let msg = Message(role: .assistant, content: "Searching...", toolCalls: [tc])
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.toolCalls?.count, 1)
        XCTAssertEqual(decoded.toolCalls?[0].id, "tc1")
        XCTAssertEqual(decoded.toolCalls?[0].name, "grep_search")
        XCTAssertEqual(decoded.toolCalls?[0].arguments, "{\"query\":\"hello\"}")
    }

    func testMessageCodableWithThreadingFields() throws {
        var msg = Message(role: .user, content: "Threaded")
        msg.parentMessageId = UUID()
        msg.branchId = UUID()
        msg.threadId = UUID()
        msg.isBranch = true
        msg.branchName = "feature"
        msg.children = [UUID(), UUID()]

        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.parentMessageId, msg.parentMessageId)
        XCTAssertEqual(decoded.branchId, msg.branchId)
        XCTAssertEqual(decoded.threadId, msg.threadId)
        XCTAssertTrue(decoded.isBranch)
        XCTAssertEqual(decoded.branchName, "feature")
        XCTAssertEqual(decoded.children.count, 2)
    }

    func testMessageEmptyContent() throws {
        let msg = Message(role: .assistant, content: "")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.content, "")
    }

    func testMessageUnicodeContent() throws {
        let content = "Hello 🌍🎉 こんにちは мир العالم"
        let msg = Message(role: .user, content: content)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.content, content)
    }

    func testMessageVeryLongContent() throws {
        let content = String(repeating: "A", count: 100_000)
        let msg = Message(role: .user, content: content)
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(decoded.content.count, 100_000)
    }

    // MARK: - Message Equatable

    func testMessageEquatable() {
        let id = UUID()
        let date = Date()
        let msg1 = Message(id: id, role: .user, content: "Hello", timestamp: date)
        let msg2 = Message(id: id, role: .user, content: "Hello", timestamp: date)
        XCTAssertEqual(msg1, msg2)
    }

    func testMessageNotEqualDifferentContent() {
        let id = UUID()
        let date = Date()
        let msg1 = Message(id: id, role: .user, content: "Hello", timestamp: date)
        let msg2 = Message(id: id, role: .user, content: "World", timestamp: date)
        XCTAssertNotEqual(msg1, msg2)
    }

    func testMessageNotEqualDifferentRole() {
        let id = UUID()
        let msg1 = Message(id: id, role: .user, content: "Hello")
        let msg2 = Message(id: id, role: .assistant, content: "Hello")
        XCTAssertNotEqual(msg1, msg2)
    }

    // MARK: - ToolCall

    func testToolCallCreation() {
        let tc = ToolCall(id: "call_abc", name: "read_file", arguments: "{\"path\":\"/tmp\"}")
        XCTAssertEqual(tc.id, "call_abc")
        XCTAssertEqual(tc.name, "read_file")
        XCTAssertEqual(tc.arguments, "{\"path\":\"/tmp\"}")
    }

    func testToolCallCodable() throws {
        let tc = ToolCall(id: "tc_999", name: "web_search", arguments: "{\"query\":\"swift concurrency\"}")
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, tc.id)
        XCTAssertEqual(decoded.name, tc.name)
        XCTAssertEqual(decoded.arguments, tc.arguments)
    }

    func testToolCallEquatable() {
        let tc1 = ToolCall(id: "a", name: "read_file", arguments: "{}")
        let tc2 = ToolCall(id: "a", name: "read_file", arguments: "{}")
        XCTAssertEqual(tc1, tc2)

        let tc3 = ToolCall(id: "b", name: "read_file", arguments: "{}")
        XCTAssertNotEqual(tc1, tc3)
    }

    func testToolCallEmptyArguments() throws {
        let tc = ToolCall(id: "tc1", name: "get_cwd", arguments: "")
        let data = try JSONEncoder().encode(tc)
        let decoded = try JSONDecoder().decode(ToolCall.self, from: data)
        XCTAssertEqual(decoded.arguments, "")
    }

    // MARK: - ToolCallStatus

    func testToolCallStatusCreation() {
        let status = ToolCallStatus(
            id: "tc1", name: "run_command", arguments: "{}", status: .pending
        )
        XCTAssertEqual(status.id, "tc1")
        XCTAssertEqual(status.name, "run_command")
        XCTAssertEqual(status.status, .pending)
        XCTAssertNil(status.result)
        XCTAssertEqual(status.progress, 0.0)
        XCTAssertNil(status.startTime)
        XCTAssertNil(status.endTime)
        XCTAssertNil(status.currentStep)
        XCTAssertEqual(status.totalSteps, 1)
        XCTAssertEqual(status.currentStepNumber, 0)
    }

    func testToolCallStatusAllStates() {
        let states: [ToolCallStatus.ToolRunStatus] = [.pending, .running, .completed, .failed, .cancelled]
        for state in states {
            let status = ToolCallStatus(id: "t", name: "n", arguments: "", status: state)
            XCTAssertEqual(status.status, state)
        }
    }

    func testToolCallStatusMutation() {
        var status = ToolCallStatus(id: "tc1", name: "read_file", arguments: "{}", status: .pending)
        status.status = .running
        status.startTime = Date()
        status.currentStep = "Reading file"
        status.progress = 0.5
        XCTAssertEqual(status.status, .running)
        XCTAssertNotNil(status.startTime)
        XCTAssertEqual(status.currentStep, "Reading file")

        status.status = .completed
        status.endTime = Date()
        status.result = "File contents here"
        status.progress = 1.0
        XCTAssertEqual(status.status, .completed)
        XCTAssertNotNil(status.endTime)
        XCTAssertEqual(status.result, "File contents here")
    }

    // MARK: - SystemRunHistoryEntry

    func testSystemRunHistoryEntry() {
        let entry = SystemRunHistoryEntry(
            command: "swift build",
            resolvedPath: "/usr/bin/swift",
            allowed: true
        )
        XCTAssertEqual(entry.command, "swift build")
        XCTAssertEqual(entry.resolvedPath, "/usr/bin/swift")
        XCTAssertTrue(entry.allowed)
        XCTAssertFalse(entry.id.uuidString.isEmpty)
    }

    func testSystemRunHistoryEntryDenied() {
        let entry = SystemRunHistoryEntry(
            command: "rm -rf /",
            resolvedPath: "/bin/rm",
            allowed: false
        )
        XCTAssertFalse(entry.allowed)
    }
}
