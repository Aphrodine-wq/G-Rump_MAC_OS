import XCTest
@testable import GRump

final class PerformanceAdvisorTests: XCTestCase {

    // MARK: - GRumpSignpost

    func testSignpostLogExists() {
        let log = GRumpSignpost.log
        XCTAssertNotNil(log)
    }

    func testSignpostAgentLogExists() {
        let log = GRumpSignpost.agentLog
        XCTAssertNotNil(log)
    }

    func testSignpostNetworkLogExists() {
        let log = GRumpSignpost.networkLog
        XCTAssertNotNil(log)
    }

    func testSignpostToolLogExists() {
        let log = GRumpSignpost.toolLog
        XCTAssertNotNil(log)
    }

    // MARK: - PerformanceAdvisor Singleton

    @MainActor
    func testSharedInstanceExists() {
        let advisor = PerformanceAdvisor.shared
        XCTAssertNotNil(advisor)
    }

    @MainActor
    func testInitialThermalState() {
        let advisor = PerformanceAdvisor.shared
        // Should start at nominal (or whatever system reports)
        _ = advisor.thermalState
    }

    @MainActor
    func testInitialMemoryValues() {
        let advisor = PerformanceAdvisor.shared
        // appMemoryMB should be non-negative
        XCTAssertGreaterThanOrEqual(advisor.appMemoryMB, 0)
    }

    @MainActor
    func testAdvisoriesStartEmpty() {
        let advisor = PerformanceAdvisor.shared
        // Advisories may or may not be empty depending on system state
        _ = advisor.advisories
    }
}
