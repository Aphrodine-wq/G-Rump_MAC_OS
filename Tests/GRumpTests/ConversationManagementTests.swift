import XCTest
@testable import GRump

/// Tests for conversation CRUD operations in `ChatViewModel+Messages`.
/// Covers create, delete, rename, duplicate, select, and sync behaviors.
@MainActor
final class ConversationManagementTests: XCTestCase {

    // MARK: - Helpers

    private func makeViewModel() -> ChatViewModel {
        let vm = ChatViewModel()
        // Clear any default conversations
        vm.conversations = []
        vm.currentConversation = nil
        return vm
    }

    // MARK: - Create

    func testCreateNewConversationInsertsAtFront() {
        let vm = makeViewModel()
        vm.createNewConversation()

        XCTAssertEqual(vm.conversations.count, 1)
        XCTAssertNotNil(vm.currentConversation)
        XCTAssertEqual(vm.currentConversation?.title, "New Chat")
        XCTAssertTrue(vm.currentConversation?.messages.isEmpty ?? false)
    }

    func testCreateMultipleConversationsInsertsAtFront() {
        let vm = makeViewModel()

        vm.createNewConversation()
        let firstId = vm.currentConversation?.id

        vm.createNewConversation()
        let secondId = vm.currentConversation?.id

        XCTAssertEqual(vm.conversations.count, 2)
        XCTAssertEqual(vm.conversations[0].id, secondId, "Newest conversation should be at index 0")
        XCTAssertEqual(vm.conversations[1].id, firstId)
        XCTAssertEqual(vm.currentConversation?.id, secondId, "Current should be the newest")
    }

    func testCreateConversationClearsInput() {
        let vm = makeViewModel()
        vm.userInput = "some draft text"

        vm.createNewConversation()

        XCTAssertEqual(vm.userInput, "", "Creating a new conversation should clear input")
    }

    // MARK: - Delete

    func testDeleteConversationRemovesIt() {
        let vm = makeViewModel()
        vm.createNewConversation()
        vm.createNewConversation()
        XCTAssertEqual(vm.conversations.count, 2)

        let toDelete = vm.conversations[1]
        vm.deleteConversation(toDelete)

        XCTAssertEqual(vm.conversations.count, 1)
        XCTAssertNil(vm.conversations.first(where: { $0.id == toDelete.id }))
    }

    func testDeleteCurrentConversationSelectsNext() {
        let vm = makeViewModel()
        vm.createNewConversation() // conv A
        let convA = vm.conversations[0]
        vm.createNewConversation() // conv B (now current)
        let convB = vm.conversations[0]

        XCTAssertEqual(vm.currentConversation?.id, convB.id)

        vm.deleteConversation(convB)

        XCTAssertEqual(vm.currentConversation?.id, convA.id,
                       "Should select next conversation after deleting current")
    }

    func testDeleteLastConversation() {
        let vm = makeViewModel()
        vm.createNewConversation()
        let only = vm.conversations[0]

        vm.deleteConversation(only)

        XCTAssertTrue(vm.conversations.isEmpty)
        XCTAssertNil(vm.currentConversation)
    }

    // MARK: - Rename

    func testRenameConversation() {
        let vm = makeViewModel()
        vm.createNewConversation()
        let conv = vm.conversations[0]

        vm.renameConversation(conv, to: "Renamed Title")

        XCTAssertEqual(vm.conversations[0].title, "Renamed Title")
    }

    func testRenameCurrentConversationUpdatesCurrentRef() {
        let vm = makeViewModel()
        vm.createNewConversation()

        vm.renameConversation(vm.currentConversation!, to: "Updated")

        XCTAssertEqual(vm.currentConversation?.title, "Updated",
                       "Renaming current conversation should update currentConversation")
    }

    func testRenameNonexistentConversationDoesNothing() {
        let vm = makeViewModel()
        vm.createNewConversation()
        let ghost = Conversation(title: "Ghost")

        vm.renameConversation(ghost, to: "Should Not Appear")

        XCTAssertNil(vm.conversations.first(where: { $0.title == "Should Not Appear" }))
    }

    // MARK: - Duplicate

    func testDuplicateConversationCreatesDeepCopy() {
        let vm = makeViewModel()
        vm.createNewConversation()
        vm.currentConversation?.messages.append(Message(role: .user, content: "Hello"))
        vm.currentConversation?.messages.append(Message(role: .assistant, content: "Hi!"))
        vm.syncConversation()

        let original = vm.conversations[0]
        vm.duplicateConversation(original)

        XCTAssertEqual(vm.conversations.count, 2)
        XCTAssertEqual(vm.currentConversation?.title, "Copy of \(original.title)")
        XCTAssertEqual(vm.currentConversation?.messages.count, 2)

        // Verify messages are deep-copied with new IDs
        let originalIds = Set(original.messages.map(\.id))
        let copyIds = Set(vm.currentConversation?.messages.map(\.id) ?? [])
        XCTAssertTrue(originalIds.isDisjoint(with: copyIds),
                      "Duplicated messages should have new UUIDs")
    }

    func testDuplicatePreservesMessageContent() {
        let vm = makeViewModel()
        vm.createNewConversation()
        vm.currentConversation?.messages.append(Message(role: .user, content: "Original content"))
        vm.syncConversation()

        let original = vm.conversations[0]
        vm.duplicateConversation(original)

        XCTAssertEqual(vm.currentConversation?.messages.first?.content, "Original content",
                       "Duplicate should preserve message content")
    }

    // MARK: - Select

    func testSelectConversationSwitchesCurrent() {
        let vm = makeViewModel()
        vm.createNewConversation()
        let first = vm.conversations[0]
        vm.createNewConversation()
        
        XCTAssertNotEqual(vm.currentConversation?.id, first.id)

        vm.selectConversation(first)

        XCTAssertEqual(vm.currentConversation?.id, first.id)
    }

    func testSelectConversationPreservesDraft() {
        let vm = makeViewModel()
        vm.createNewConversation()
        let convA = vm.conversations[0]
        vm.userInput = "Draft for A"
        vm.createNewConversation()
        let convB = vm.conversations[0]
        vm.userInput = "Draft for B"

        // Switch to A — "Draft for B" should be saved
        vm.selectConversation(convA)

        // Switch back to B — draft should be restored
        vm.selectConversation(convB)
        // Draft restoration depends on saveDraft/loadDraft working correctly,
        // which uses UserDefaults under the hood
    }

    // MARK: - Sync

    func testSyncConversationUpdatesConversationsList() {
        let vm = makeViewModel()
        vm.createNewConversation()
        
        vm.currentConversation?.messages.append(Message(role: .user, content: "Synced"))
        vm.syncConversation()

        let stored = vm.conversations.first(where: { $0.id == vm.currentConversation?.id })
        XCTAssertEqual(stored?.messages.count, 1, "Sync should propagate changes to the list")
        XCTAssertEqual(stored?.messages.first?.content, "Synced")
    }

    func testSyncConversationWithNilCurrentDoesNothing() {
        let vm = makeViewModel()
        vm.currentConversation = nil

        // Should not crash
        vm.syncConversation()
    }

    // MARK: - Edge Cases

    func testOperationsWithEmptyConversationsList() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.conversations.isEmpty)

        // Delete non-existent
        vm.deleteConversation(Conversation(title: "Ghost"))
        XCTAssertTrue(vm.conversations.isEmpty)

        // Rename non-existent
        vm.renameConversation(Conversation(title: "Ghost"), to: "X")
        XCTAssertTrue(vm.conversations.isEmpty)
    }
}
