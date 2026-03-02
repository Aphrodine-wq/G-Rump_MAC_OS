import XCTest
@testable import GRump

@MainActor
final class FrameLoopServiceTests: XCTestCase {

    // MARK: - Constants

    func testActiveFPS() {
        XCTAssertEqual(FrameLoopService.activeFPS, 60)
    }

    func testStreamingFPS() {
        XCTAssertEqual(FrameLoopService.streamingFPS, 120)
    }

    func testActiveInterval() {
        let expected = 1.0 / 60.0
        XCTAssertEqual(FrameLoopService.activeInterval, expected, accuracy: 0.0001)
    }

    func testStreamingInterval() {
        let expected = 1.0 / 120.0
        XCTAssertEqual(FrameLoopService.streamingInterval, expected, accuracy: 0.0001)
    }

    // MARK: - Lifecycle

    func testSharedInstance() {
        let instance = FrameLoopService.shared
        XCTAssertNotNil(instance)
    }

    func testInitialState() {
        let service = FrameLoopService()
        XCTAssertFalse(service.isRunning)
        XCTAssertFalse(service.isStreaming)
        XCTAssertEqual(service.tick, 0)
    }

    func testStartSetsRunning() {
        let service = FrameLoopService()
        service.start()
        XCTAssertTrue(service.isRunning)
        service.stop()
    }

    func testStopClearsRunning() {
        let service = FrameLoopService()
        service.start()
        XCTAssertTrue(service.isRunning)
        service.stop()
        XCTAssertFalse(service.isRunning)
    }

    func testDoubleStartDoesNotCrash() {
        let service = FrameLoopService()
        service.start()
        service.start() // Should be a no-op
        XCTAssertTrue(service.isRunning)
        service.stop()
    }

    func testDoubleStopDoesNotCrash() {
        let service = FrameLoopService()
        service.stop() // Stopping when not running
        service.stop()
        XCTAssertFalse(service.isRunning)
    }

    // MARK: - Mark Active / Streaming

    func testMarkActiveStartsLoop() {
        let service = FrameLoopService()
        XCTAssertFalse(service.isRunning)
        service.markActive(for: 0.5)
        XCTAssertTrue(service.isRunning)
        service.stop()
    }

    func testMarkStreamingStartsLoop() {
        let service = FrameLoopService()
        XCTAssertFalse(service.isRunning)
        service.markStreaming(for: 0.5)
        XCTAssertTrue(service.isRunning)
        XCTAssertTrue(service.isStreaming)
        service.stop()
    }

    func testStopClearsStreaming() {
        let service = FrameLoopService()
        service.markStreaming(for: 1.0)
        XCTAssertTrue(service.isStreaming)
        service.stop()
        XCTAssertFalse(service.isStreaming)
    }
}
