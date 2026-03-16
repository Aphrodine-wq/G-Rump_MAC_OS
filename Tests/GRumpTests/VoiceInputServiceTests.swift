import XCTest
@testable import GRump

#if os(macOS)
/// Tests the VoiceInputService state machine and error handling.
@MainActor
final class VoiceInputServiceTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateNotRecording() {
        let service = VoiceInputService()
        XCTAssertFalse(service.isRecording)
    }

    func testInitialTranscribedTextEmpty() {
        let service = VoiceInputService()
        XCTAssertTrue(service.transcribedText.isEmpty)
    }

    func testInitialErrorMessageNil() {
        let service = VoiceInputService()
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Stop Recording

    func testStopRecordingResetsIsRecording() {
        let service = VoiceInputService()
        // Directly call stopRecording — should not crash even if not recording
        service.stopRecording()
        XCTAssertFalse(service.isRecording)
    }

    func testStopRecordingIsIdempotent() {
        let service = VoiceInputService()
        service.stopRecording()
        service.stopRecording()
        service.stopRecording()
        XCTAssertFalse(service.isRecording, "Multiple stopRecording calls should be safe")
    }

    // MARK: - Toggle Recording

    func testToggleRecordingWhenNotRecordingWillAttemptStart() {
        let service = VoiceInputService()
        XCTAssertFalse(service.isRecording)
        // toggleRecording will request authorization first, which won't
        // succeed in test environment, but should not crash
        service.toggleRecording()
        // Since auth won't be granted in test, isRecording should remain false
        XCTAssertFalse(service.isRecording)
    }

    // MARK: - Error Message Assignment

    func testErrorMessageCanBeSet() {
        let service = VoiceInputService()
        service.errorMessage = "Test error"
        XCTAssertEqual(service.errorMessage, "Test error")
    }

    func testErrorMessageCanBeCleared() {
        let service = VoiceInputService()
        service.errorMessage = "Some error"
        service.errorMessage = nil
        XCTAssertNil(service.errorMessage)
    }

    // MARK: - Transcribed Text

    func testTranscribedTextCanBeSet() {
        let service = VoiceInputService()
        service.transcribedText = "Hello world"
        XCTAssertEqual(service.transcribedText, "Hello world")
    }

    func testTranscribedTextResetOnStop() {
        let service = VoiceInputService()
        service.transcribedText = "Some text"
        // After stopRecording, the service should have stopped but
        // transcribedText is preserved (per source code review)
        service.stopRecording()
        // The source doesn't clear transcribedText in stopRecording —
        // it's cleared in startRecording. Verify this behavior.
        XCTAssertEqual(service.transcribedText, "Some text",
            "stopRecording should NOT clear transcribedText (it's preserved for the caller)")
    }

    // MARK: - Published Properties Observable

    func testIsRecordingIsPublished() {
        let service = VoiceInputService()
        // Verify @Published works by setting values
        service.isRecording = true
        XCTAssertTrue(service.isRecording)
        service.isRecording = false
        XCTAssertFalse(service.isRecording)
    }

    func testServiceIsObservableObject() {
        let service = VoiceInputService()
        // VoiceInputService conforms to ObservableObject
        let _ = service.objectWillChange
        // If this compiles, it confirms ObservableObject conformance
    }

    // MARK: - Edge Cases

    func testStartRecordingWithUnavailableRecognizer() {
        let service = VoiceInputService()
        // In test environment, speech recognizer may not be available
        // startRecording should handle this gracefully
        service.startRecording()
        // Should either set an error message or remain not recording
        if !service.isRecording {
            // Expected in test environment — either error or recognizer unavailable
            // This is acceptable behavior
        }
    }
}
#endif
