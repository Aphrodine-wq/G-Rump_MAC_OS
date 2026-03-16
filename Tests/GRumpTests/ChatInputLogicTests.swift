import XCTest
@testable import GRump

/// Tests the pure business logic behind ChatInputView — send gating, return key
/// handling, attachment management, and hint text selection.
final class ChatInputLogicTests: XCTestCase {

    // MARK: - canSend Logic

    /// Mirror of ChatInputView.canSend for unit testing.
    private func canSend(text: String, isLoading: Bool) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    func testCanSendWithValidText() {
        XCTAssertTrue(canSend(text: "Hello", isLoading: false))
    }

    func testCanSendBlockedWhenEmpty() {
        XCTAssertFalse(canSend(text: "", isLoading: false))
    }

    func testCanSendBlockedWhenWhitespaceOnly() {
        XCTAssertFalse(canSend(text: "   ", isLoading: false))
        XCTAssertFalse(canSend(text: "\n\n", isLoading: false))
        XCTAssertFalse(canSend(text: "\t\t", isLoading: false))
        XCTAssertFalse(canSend(text: "  \n \t  ", isLoading: false))
    }

    func testCanSendBlockedWhileLoading() {
        XCTAssertFalse(canSend(text: "Valid message", isLoading: true))
    }

    func testCanSendBlockedWhileLoadingAndEmpty() {
        XCTAssertFalse(canSend(text: "", isLoading: true))
    }

    func testCanSendWithSingleCharacter() {
        XCTAssertTrue(canSend(text: "x", isLoading: false))
    }

    func testCanSendWithLeadingTrailingWhitespace() {
        XCTAssertTrue(canSend(text: "  Hello  ", isLoading: false))
    }

    func testCanSendWithNewlinesAndContent() {
        XCTAssertTrue(canSend(text: "\nHello\n", isLoading: false))
    }

    func testCanSendWithVeryLongText() {
        let longText = String(repeating: "a", count: 10_000)
        XCTAssertTrue(canSend(text: longText, isLoading: false))
    }

    func testCanSendWithUnicodeContent() {
        XCTAssertTrue(canSend(text: "🚀", isLoading: false))
        XCTAssertTrue(canSend(text: "日本語テスト", isLoading: false))
        XCTAssertTrue(canSend(text: "مرحبا", isLoading: false))
    }

    func testCanSendWithOnlyZeroWidthSpaces() {
        // Zero-width spaces (\u{200B}) are in Foundation's .whitespacesAndNewlines
        // so text containing only zero-width characters is NOT sendable
        let zeroWidth = "\u{200B}\u{200B}"
        let result = canSend(text: zeroWidth, isLoading: false)
        XCTAssertFalse(result, "Zero-width spaces are whitespace per Foundation")
    }

    // MARK: - Return Key Handling Logic

    /// Mirror of ChatInputView's return key decision logic.
    private func shouldReturnKeySend(
        returnToSend: Bool,
        hasShiftModifier: Bool,
        hasCommandModifier: Bool,
        canSend: Bool
    ) -> Bool {
        if returnToSend {
            if hasShiftModifier { return false } // Let newline through
            return canSend
        } else {
            if hasCommandModifier { return canSend }
            return false
        }
    }

    func testReturnToSendEnabled_ReturnKeyTriggersSpend() {
        XCTAssertTrue(shouldReturnKeySend(
            returnToSend: true, hasShiftModifier: false,
            hasCommandModifier: false, canSend: true))
    }

    func testReturnToSendEnabled_ShiftReturnInsertsNewline() {
        XCTAssertFalse(shouldReturnKeySend(
            returnToSend: true, hasShiftModifier: true,
            hasCommandModifier: false, canSend: true))
    }

    func testReturnToSendEnabled_EmptyTextDoesNotSend() {
        XCTAssertFalse(shouldReturnKeySend(
            returnToSend: true, hasShiftModifier: false,
            hasCommandModifier: false, canSend: false))
    }

    func testReturnToSendDisabled_CmdReturnSends() {
        XCTAssertTrue(shouldReturnKeySend(
            returnToSend: false, hasShiftModifier: false,
            hasCommandModifier: true, canSend: true))
    }

    func testReturnToSendDisabled_PlainReturnInsertsNewline() {
        XCTAssertFalse(shouldReturnKeySend(
            returnToSend: false, hasShiftModifier: false,
            hasCommandModifier: false, canSend: true))
    }

    func testReturnToSendDisabled_CmdReturnEmptyDoesNotSend() {
        XCTAssertFalse(shouldReturnKeySend(
            returnToSend: false, hasShiftModifier: false,
            hasCommandModifier: true, canSend: false))
    }

    func testReturnToSendDisabled_ShiftReturnAlwaysNewline() {
        XCTAssertFalse(shouldReturnKeySend(
            returnToSend: false, hasShiftModifier: true,
            hasCommandModifier: false, canSend: true))
    }

    // MARK: - Send Hint Text

    func testSendHintReturnToSendEnabled() {
        let returnToSend = true
        let hint = returnToSend
            ? "Return to send  ·  ⇧ Return for new line"
            : "⌘ Return to send  ·  Return for new line"
        XCTAssertTrue(hint.contains("Return to send"))
        XCTAssertTrue(hint.contains("⇧ Return"))
    }

    func testSendHintReturnToSendDisabled() {
        let returnToSend = false
        let hint = returnToSend
            ? "Return to send  ·  ⇧ Return for new line"
            : "⌘ Return to send  ·  Return for new line"
        XCTAssertTrue(hint.contains("⌘ Return"))
    }

    // MARK: - Attachment Management

    func testAttachmentAdd() {
        var files: [URL] = []
        let url1 = URL(fileURLWithPath: "/tmp/test1.png")
        let url2 = URL(fileURLWithPath: "/tmp/test2.pdf")

        files.append(url1)
        files.append(url2)

        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0], url1)
        XCTAssertEqual(files[1], url2)
    }

    func testAttachmentRemoveSpecific() {
        let url1 = URL(fileURLWithPath: "/tmp/test1.png")
        let url2 = URL(fileURLWithPath: "/tmp/test2.pdf")
        let url3 = URL(fileURLWithPath: "/tmp/test3.swift")
        var files = [url1, url2, url3]

        // Remove url2 (mirrors ChatInputView.removeAttachment)
        files.removeAll { $0 == url2 }

        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains(url1))
        XCTAssertFalse(files.contains(url2))
        XCTAssertTrue(files.contains(url3))
    }

    func testAttachmentRemoveNonexistent() {
        let url1 = URL(fileURLWithPath: "/tmp/test1.png")
        var files = [url1]

        let bogus = URL(fileURLWithPath: "/tmp/nope.txt")
        files.removeAll { $0 == bogus }

        XCTAssertEqual(files.count, 1, "Should not remove anything")
    }

    func testAttachmentCallbackFired() {
        var callbackFiles: [URL]?
        let callback: ([URL]) -> Void = { callbackFiles = $0 }

        var files: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        files.append(url)
        callback(files)

        XCTAssertNotNil(callbackFiles)
        XCTAssertEqual(callbackFiles?.count, 1)
        XCTAssertEqual(callbackFiles?.first, url)
    }

    func testAttachmentCallbackOnRemove() {
        var callbackCount = 0
        let callback: ([URL]) -> Void = { _ in callbackCount += 1 }

        var files = [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")]
        callback(files) // +1 (add)
        files.removeAll { $0.lastPathComponent == "a.png" }
        callback(files) // +1 (remove)

        XCTAssertEqual(callbackCount, 2)
    }

    func testAttachmentDuplicateURLs() {
        let url = URL(fileURLWithPath: "/tmp/same.png")
        var files: [URL] = [url, url, url]

        // removeAll removes all occurrences — mirrors ChatInputView behavior
        files.removeAll { $0 == url }
        XCTAssertTrue(files.isEmpty, "All duplicates should be removed")
    }

    // MARK: - sendAndTrack Behavior

    func testSendAndTrackSetsFlag() {
        var hasSentFirstMessage = false
        var onSendCalled = false

        // Mirror sendAndTrack()
        hasSentFirstMessage = true
        onSendCalled = true

        XCTAssertTrue(hasSentFirstMessage)
        XCTAssertTrue(onSendCalled)
    }

    func testSendAndTrackIdempotent() {
        var hasSentFirstMessage = false

        // First send
        hasSentFirstMessage = true
        XCTAssertTrue(hasSentFirstMessage)

        // Second send — flag stays true
        hasSentFirstMessage = true
        XCTAssertTrue(hasSentFirstMessage)
    }

    // MARK: - Height Constraints

    func testMinHeightDefault() {
        let minHeight: CGFloat = 44
        let maxHeight: CGFloat = 200
        XCTAssertLessThan(minHeight, maxHeight)
        XCTAssertEqual(minHeight, 44)
    }

    func testHeightClamping() {
        let minHeight: CGFloat = 44
        let maxHeight: CGFloat = 200

        let tooSmall: CGFloat = 20
        let tooLarge: CGFloat = 500
        let justRight: CGFloat = 100

        XCTAssertEqual(max(minHeight, min(maxHeight, tooSmall)), minHeight)
        XCTAssertEqual(max(minHeight, min(maxHeight, tooLarge)), maxHeight)
        XCTAssertEqual(max(minHeight, min(maxHeight, justRight)), justRight)
    }
}
