import XCTest
@testable import GRump

/// Tests for message-level operations in `ChatViewModel+Messages`.
/// Covers undo send, edit user message, threading, and branching operations.
@MainActor
final class MessageOperationsTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> ChatViewModel {
        let vm = ChatViewModel()
        vm.createNewConversation()
        return vm
    }

    private func makeViewModelWithMessages() -> ChatViewModel {
        let vm = makeViewModel()
        vm.currentConversation?.messages.append(Message(role: .user, content: "Hello"))
        vm.currentConversation?.messages.append(Message(role: .assistant, content: "Hi there!"))
        vm.currentConversation?.messages.append(Message(role: .user, content: "Build a feature"))
        vm.syncConversation()
        return vm
    }

    // MARK: - Edit User Message

    func testEditUserMessageUpdatesContent() {
        let vm = makeViewModelWithMessages()
        let userMsg = vm.currentConversation!.messages.first(where: { $0.role == .user })!

        vm.editUserMessage(userMsg.id, newContent: "Updated content")

        let updated = vm.currentConversation?.messages.first(where: { $0.id == userMsg.id })
        XCTAssertEqual(updated?.content, "Updated content")
    }

    func testEditUserMessageDoesNotEditAssistantMessage() {
        let vm = makeViewModelWithMessages()
        let assistantMsg = vm.currentConversation!.messages.first(where: { $0.role == .assistant })!
        let originalContent = assistantMsg.content

        vm.editUserMessage(assistantMsg.id, newContent: "Hacked")

        let unchanged = vm.currentConversation?.messages.first(where: { $0.id == assistantMsg.id })
        XCTAssertEqual(unchanged?.content, originalContent,
                       "Should not edit assistant messages")
    }

    func testEditUserMessageWithInvalidIdDoesNothing() {
        let vm = makeViewModelWithMessages()
        let messageCountBefore = vm.currentConversation?.messages.count ?? 0

        vm.editUserMessage(UUID(), newContent: "Ghost edit")

        XCTAssertEqual(vm.currentConversation?.messages.count, messageCountBefore,
                       "Editing with invalid ID should not modify messages")
    }

    func testEditUserMessageNoConversation() {
        let vm = makeViewModel()
        vm.currentConversation = nil

        // Should not crash
        vm.editUserMessage(UUID(), newContent: "No crash")
    }

    func testEditUserMessageToEmptyString() {
        let vm = makeViewModelWithMessages()
        let userMsg = vm.currentConversation!.messages.first(where: { $0.role == .user })!

        vm.editUserMessage(userMsg.id, newContent: "")

        let updated = vm.currentConversation?.messages.first(where: { $0.id == userMsg.id })
        XCTAssertEqual(updated?.content, "", "Should allow editing to empty string")
    }

    func testEditUserMessageToUnicode() {
        let vm = makeViewModelWithMessages()
        let userMsg = vm.currentConversation!.messages.first(where: { $0.role == .user })!

        vm.editUserMessage(userMsg.id, newContent: "Hello 🌍🎉 こんにちは")

        let updated = vm.currentConversation?.messages.first(where: { $0.id == userMsg.id })
        XCTAssertEqual(updated?.content, "Hello 🌍🎉 こんにちは")
    }

    // MARK: - Threading

    func testCreateThreadFromMessage() {
        let vm = makeViewModelWithMessages()
        let msg = vm.currentConversation!.messages[0]
        let threadCountBefore = vm.currentConversation?.threads.count ?? 0

        vm.createThread(from: msg.id, name: "Discussion Thread")

        XCTAssertEqual(vm.currentConversation?.threads.count, (threadCountBefore + 1))
        XCTAssertEqual(vm.currentConversation?.threads.last?.name, "Discussion Thread")
    }

    func testCreateThreadFromInvalidId() {
        let vm = makeViewModelWithMessages()
        let threadCountBefore = vm.currentConversation?.threads.count ?? 0

        vm.createThread(from: UUID(), name: "Ghost Thread")

        XCTAssertEqual(vm.currentConversation?.threads.count, threadCountBefore,
                       "Should not create thread from non-existent message")
    }

    func testCreateThreadWithoutConversation() {
        let vm = makeViewModel()
        vm.currentConversation = nil

        // Should not crash
        vm.createThread(from: UUID(), name: "No crash")
    }

    // MARK: - Branching

    func testCreateBranchFromMessage() {
        let vm = makeViewModelWithMessages()
        let msg = vm.currentConversation!.messages[0]
        let branchCountBefore = vm.currentConversation?.branches.count ?? 0

        vm.createBranch(from: msg.id, name: "Alt Branch")

        XCTAssertEqual(vm.currentConversation?.branches.count, (branchCountBefore + 1))
    }

    func testCreateBranchFromInvalidId() {
        let vm = makeViewModelWithMessages()
        let branchCountBefore = vm.currentConversation?.branches.count ?? 0

        vm.createBranch(from: UUID(), name: "Ghost Branch")

        XCTAssertEqual(vm.currentConversation?.branches.count, branchCountBefore)
    }

    // MARK: - View Mode

    func testSetConversationViewMode() {
        let vm = makeViewModelWithMessages()

        vm.setConversationViewMode(.threaded)
        XCTAssertEqual(vm.currentConversation?.viewMode, .threaded)

        vm.setConversationViewMode(.branched)
        XCTAssertEqual(vm.currentConversation?.viewMode, .branched)

        vm.setConversationViewMode(.linear)
        XCTAssertEqual(vm.currentConversation?.viewMode, .linear)
    }

    func testSetViewModeWithNoConversation() {
        let vm = makeViewModel()
        vm.currentConversation = nil

        // Should not crash
        vm.setConversationViewMode(.threaded)
    }
}
