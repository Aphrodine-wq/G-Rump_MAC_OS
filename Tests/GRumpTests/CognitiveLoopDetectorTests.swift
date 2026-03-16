import XCTest
@testable import GRump

/// Tests for CognitiveLoopDetector — action fingerprinting, loop detection, and pivot strategies.
final class CognitiveLoopDetectorTests: XCTestCase {

    // MARK: - PivotStrategy

    func testPivotStrategyCaseCount() {
        XCTAssertEqual(PivotStrategy.allCases.count, 6)
    }

    func testAllPivotStrategiesHaveSystemMessages() {
        for strategy in PivotStrategy.allCases {
            XCTAssertFalse(strategy.systemMessage.isEmpty,
                "\(strategy.rawValue) has empty systemMessage")
        }
    }

    func testSystemMessagesAreSubstantial() {
        for strategy in PivotStrategy.allCases {
            XCTAssertGreaterThan(strategy.systemMessage.count, 50,
                "\(strategy.rawValue) systemMessage too short")
        }
    }

    func testSystemMessagesContainLoopDetected() {
        for strategy in PivotStrategy.allCases {
            XCTAssertTrue(strategy.systemMessage.uppercased().contains("LOOP"),
                "\(strategy.rawValue) systemMessage should mention LOOP")
        }
    }

    func testPivotStrategyRawValuesAreUnique() {
        let rawValues = PivotStrategy.allCases.map(\.rawValue)
        XCTAssertEqual(rawValues.count, Set(rawValues).count)
    }

    // MARK: - ActionFingerprint

    func testActionFingerprintCreation() {
        let fp = ActionFingerprint(
            toolName: "edit_file",
            argsHash: "abc123",
            resultHash: "def456",
            wasError: false,
            timestamp: Date()
        )
        XCTAssertEqual(fp.toolName, "edit_file")
        XCTAssertFalse(fp.wasError)
    }

    // MARK: - CognitiveLoopDetector Init

    func testDetectorInitialState() async {
        let detector = CognitiveLoopDetector()
        let loopCount = await detector.loopCount
        let pivots = await detector.totalPivots
        XCTAssertEqual(loopCount, 0)
        XCTAssertEqual(pivots, 0)
    }

    // MARK: - Recording Actions

    func testRecordSingleActionNoPivot() async {
        let detector = CognitiveLoopDetector()
        let pivot = await detector.recordAction(
            toolName: "read_file",
            arguments: "{\"path\":\"/a.swift\"}",
            result: "file contents",
            wasError: false
        )
        XCTAssertNil(pivot, "Single action should not trigger a pivot")
    }

    func testRecordDiverseActionsNoPivot() async {
        let detector = CognitiveLoopDetector()
        let tools = ["read_file", "edit_file", "run_command", "grep_search", "write_file"]
        for tool in tools {
            let pivot = await detector.recordAction(
                toolName: tool,
                arguments: "{}",
                result: "ok",
                wasError: false
            )
            XCTAssertNil(pivot)
        }
    }

    func testRepeatingErrorsEventuallyTriggerPivot() async {
        let detector = CognitiveLoopDetector()
        var lastPivot: PivotStrategy?
        // Repeat the exact same failing action many times
        for _ in 0..<20 {
            let pivot = await detector.recordAction(
                toolName: "edit_file",
                arguments: "{\"path\":\"/a.swift\",\"content\":\"let x = 1\"}",
                result: "Error: file not found",
                wasError: true
            )
            if pivot != nil { lastPivot = pivot }
        }
        // After many identical errors, should suggest a pivot
        XCTAssertNotNil(lastPivot, "Repeated identical errors should eventually trigger a loop pivot")
    }

    // MARK: - Reset

    func testDetectorReset() async {
        let detector = CognitiveLoopDetector()
        // Add some actions
        for _ in 0..<5 {
            _ = await detector.recordAction(toolName: "t", arguments: "{}", result: "ok", wasError: false)
        }
        await detector.reset()
        let loopCount = await detector.loopCount
        XCTAssertEqual(loopCount, 0)
    }

    // MARK: - Pivot Outcome Recording

    func testRecordPivotOutcome() async {
        let detector = CognitiveLoopDetector()
        // Force a pivot by repeating errors
        for _ in 0..<20 {
            _ = await detector.recordAction(toolName: "t", arguments: "a", result: "fail", wasError: true)
        }
        // Recording outcome should not crash
        await detector.recordPivotOutcome(success: true)
        await detector.recordPivotOutcome(success: false)
    }

    // MARK: - LoopPattern

    func testLoopPatternCreation() {
        let fp = ActionFingerprint(toolName: "t", argsHash: "a", resultHash: "r", wasError: false, timestamp: Date())
        let pattern = LoopPattern(fingerprints: [fp], cycleLength: 1, confidence: 0.9, detectedAt: Date())
        XCTAssertEqual(pattern.cycleLength, 1)
        XCTAssertEqual(pattern.confidence, 0.9)
        XCTAssertEqual(pattern.fingerprints.count, 1)
        XCTAssertNotNil(pattern.id)
    }
}
