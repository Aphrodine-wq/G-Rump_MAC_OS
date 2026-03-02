import XCTest
@testable import GRump

@MainActor
final class ConnectionMonitorTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let monitor = ConnectionMonitor()
        XCTAssertTrue(monitor.isConnected)
        XCTAssertEqual(monitor.status, .connected)
        XCTAssertNil(monitor.lastLatency)
        XCTAssertTrue(monitor.canStream)
    }

    // MARK: - Formatted Latency

    func testFormattedLatencyNilWhenNoData() {
        let monitor = ConnectionMonitor()
        XCTAssertNil(monitor.formattedLatency)
    }

    // MARK: - Can Stream

    func testCanStreamTrueWhenConnected() {
        let monitor = ConnectionMonitor()
        XCTAssertTrue(monitor.canStream)
    }

    // MARK: - Status Equatable

    func testStatusEquatable() {
        XCTAssertEqual(ConnectionMonitor.Status.connected, ConnectionMonitor.Status.connected)
        XCTAssertEqual(ConnectionMonitor.Status.disconnected, ConnectionMonitor.Status.disconnected)
        XCTAssertEqual(ConnectionMonitor.Status.degraded("slow"), ConnectionMonitor.Status.degraded("slow"))
        XCTAssertNotEqual(ConnectionMonitor.Status.connected, ConnectionMonitor.Status.disconnected)
        XCTAssertNotEqual(ConnectionMonitor.Status.degraded("a"), ConnectionMonitor.Status.degraded("b"))
    }

    // MARK: - Start / Stop

    func testStartAndStopDoNotCrash() {
        let monitor = ConnectionMonitor()
        monitor.start()
        monitor.stop()
        // Should not crash or leave dangling state
        XCTAssertTrue(true)
    }

    func testDoubleStartDoesNotCrash() {
        let monitor = ConnectionMonitor()
        monitor.start()
        monitor.start() // Should be a no-op
        monitor.stop()
        XCTAssertTrue(true)
    }
}
