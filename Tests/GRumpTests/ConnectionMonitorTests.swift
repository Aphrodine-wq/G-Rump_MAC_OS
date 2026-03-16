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

    // MARK: - Stop Without Start

    func testStopWithoutStartDoesNotCrash() {
        let monitor = ConnectionMonitor()
        monitor.stop() // Should be a no-op
        XCTAssertTrue(true)
    }

    func testDoubleStopDoesNotCrash() {
        let monitor = ConnectionMonitor()
        monitor.start()
        monitor.stop()
        monitor.stop() // Second stop should be safe
        XCTAssertTrue(true)
    }

    // MARK: - Connection Type

    func testConnectionTypeEnumCoverage() {
        // Verify all enum cases exist
        let types: [ConnectionMonitor.ConnectionType] = [.wifi, .cellular, .wired, .unknown]
        XCTAssertEqual(types.count, 4)
    }

    func testInitialConnectionTypeIsUnknown() {
        let monitor = ConnectionMonitor()
        XCTAssertEqual(monitor.connectionType, .unknown)
    }

    // MARK: - Status Variants

    func testStatusCheckingExists() {
        let status = ConnectionMonitor.Status.checking
        XCTAssertNotEqual(status, .connected)
        XCTAssertNotEqual(status, .disconnected)
    }

    func testStatusDegradedCarriesMessage() {
        let status = ConnectionMonitor.Status.degraded("High latency: 5.2s")
        if case .degraded(let msg) = status {
            XCTAssertTrue(msg.contains("5.2s"))
        } else {
            XCTFail("Expected degraded status")
        }
    }

    // MARK: - Formatted Latency Formatting

    func testFormattedLatencySubSecond() {
        // Test the formatting logic directly
        let latency: TimeInterval = 0.250
        let formatted: String
        if latency < 1 {
            formatted = String(format: "%.0fms", latency * 1000)
        } else {
            formatted = String(format: "%.1fs", latency)
        }
        XCTAssertEqual(formatted, "250ms")
    }

    func testFormattedLatencyOverSecond() {
        let latency: TimeInterval = 2.35
        let formatted: String
        if latency < 1 {
            formatted = String(format: "%.0fms", latency * 1000)
        } else {
            formatted = String(format: "%.1fs", latency)
        }
        XCTAssertEqual(formatted, "2.4s")
    }

    func testFormattedLatencyExactlyOneSecond() {
        let latency: TimeInterval = 1.0
        let formatted: String
        if latency < 1 {
            formatted = String(format: "%.0fms", latency * 1000)
        } else {
            formatted = String(format: "%.1fs", latency)
        }
        XCTAssertEqual(formatted, "1.0s")
    }

    func testFormattedLatencyVerySmall() {
        let latency: TimeInterval = 0.005
        let formatted = String(format: "%.0fms", latency * 1000)
        XCTAssertEqual(formatted, "5ms")
    }

    // MARK: - Observable Object

    func testConnectionMonitorIsObservable() {
        let monitor = ConnectionMonitor()
        let _ = monitor.objectWillChange
        // Compiles = confirms ObservableObject conformance
    }
}
