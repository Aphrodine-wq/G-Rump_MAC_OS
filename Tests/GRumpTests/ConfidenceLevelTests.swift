import XCTest
@testable import GRump

/// Tests for ConfidenceLevel, ConfidenceSignal, and ConfidenceReport — pure logic.
final class ConfidenceLevelTests: XCTestCase {

    // MARK: - ConfidenceLevel from Score

    func testVeryLowFromScore() {
        XCTAssertEqual(ConfidenceLevel(score: 0.0), .veryLow)
        XCTAssertEqual(ConfidenceLevel(score: 0.1), .veryLow)
        XCTAssertEqual(ConfidenceLevel(score: 0.24), .veryLow)
    }

    func testLowFromScore() {
        XCTAssertEqual(ConfidenceLevel(score: 0.25), .low)
        XCTAssertEqual(ConfidenceLevel(score: 0.49), .low)
    }

    func testModerateFromScore() {
        XCTAssertEqual(ConfidenceLevel(score: 0.5), .moderate)
        XCTAssertEqual(ConfidenceLevel(score: 0.74), .moderate)
    }

    func testHighFromScore() {
        XCTAssertEqual(ConfidenceLevel(score: 0.75), .high)
        XCTAssertEqual(ConfidenceLevel(score: 0.89), .high)
    }

    func testVeryHighFromScore() {
        XCTAssertEqual(ConfidenceLevel(score: 0.9), .veryHigh)
        XCTAssertEqual(ConfidenceLevel(score: 1.0), .veryHigh)
    }

    func testNegativeScoreIsVeryLow() {
        XCTAssertEqual(ConfidenceLevel(score: -0.5), .veryLow)
    }

    func testScoreAbove1IsVeryHigh() {
        XCTAssertEqual(ConfidenceLevel(score: 1.5), .veryHigh)
    }

    // MARK: - Labels

    func testAllLevelsHaveLabels() {
        let levels: [ConfidenceLevel] = [.veryLow, .low, .moderate, .high, .veryHigh]
        for level in levels {
            XCTAssertFalse(level.label.isEmpty, "\(level) has empty label")
        }
    }

    func testLabelsAreUnique() {
        let levels: [ConfidenceLevel] = [.veryLow, .low, .moderate, .high, .veryHigh]
        let labels = levels.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count)
    }

    // MARK: - Colors

    func testAllLevelsHaveColors() {
        let levels: [ConfidenceLevel] = [.veryLow, .low, .moderate, .high, .veryHigh]
        for level in levels {
            XCTAssertFalse(level.colorName.isEmpty, "\(level) has empty colorName")
        }
    }

    // MARK: - shouldConfirmWithUser

    func testVeryLowShouldConfirm() {
        XCTAssertTrue(ConfidenceLevel.veryLow.shouldConfirmWithUser)
    }

    func testLowShouldConfirm() {
        XCTAssertTrue(ConfidenceLevel.low.shouldConfirmWithUser)
    }

    func testModerateDoesNotConfirm() {
        XCTAssertFalse(ConfidenceLevel.moderate.shouldConfirmWithUser)
    }

    func testHighDoesNotConfirm() {
        XCTAssertFalse(ConfidenceLevel.high.shouldConfirmWithUser)
    }

    func testVeryHighDoesNotConfirm() {
        XCTAssertFalse(ConfidenceLevel.veryHigh.shouldConfirmWithUser)
    }

    // MARK: - Comparable

    func testComparableLevels() {
        XCTAssertTrue(ConfidenceLevel.veryLow < .low)
        XCTAssertTrue(ConfidenceLevel.low < .moderate)
        XCTAssertTrue(ConfidenceLevel.moderate < .high)
        XCTAssertTrue(ConfidenceLevel.high < .veryHigh)
    }

    func testComparableTransitive() {
        XCTAssertTrue(ConfidenceLevel.veryLow < .veryHigh)
    }

    // MARK: - ConfidenceSignal

    func testConfidenceSignalCreation() {
        let signal = ConfidenceSignal(source: .toolSuccess, score: 0.8, weight: 0.3, reason: "Good")
        XCTAssertEqual(signal.source, .toolSuccess)
        XCTAssertEqual(signal.score, 0.8)
        XCTAssertEqual(signal.weight, 0.3)
        XCTAssertEqual(signal.reason, "Good")
        XCTAssertNotNil(signal.id)
    }

    func testConfidenceSignalSources() {
        let sources: [ConfidenceSignal.Source] = [
            .toolSuccess, .lspDiagnostics, .memoryMatch,
            .fileStability, .errorRecovery, .taskComplexity
        ]
        XCTAssertEqual(sources.count, 6)
    }

    // MARK: - ConfidenceReport

    func testConfidenceReportSummaryHighConfidence() {
        let report = ConfidenceReport(
            signals: [
                ConfidenceSignal(source: .toolSuccess, score: 0.9, weight: 1.0, reason: "High success")
            ],
            overallScore: 0.9,
            level: .veryHigh,
            timestamp: Date()
        )
        XCTAssertTrue(report.summary.lowercased().contains("confidence"))
    }

    func testConfidenceReportSummaryLowConfidence() {
        let report = ConfidenceReport(
            signals: [
                ConfidenceSignal(source: .lspDiagnostics, score: 0.2, weight: 1.0, reason: "Many errors")
            ],
            overallScore: 0.2,
            level: .veryLow,
            timestamp: Date()
        )
        XCTAssertTrue(report.summary.contains("Concern"))
    }

    func testConfidenceReportProperties() {
        let signals = [
            ConfidenceSignal(source: .toolSuccess, score: 0.5, weight: 1.0, reason: "OK")
        ]
        let report = ConfidenceReport(signals: signals, overallScore: 0.5, level: .moderate, timestamp: Date())
        XCTAssertEqual(report.signals.count, 1)
        XCTAssertEqual(report.overallScore, 0.5)
        XCTAssertEqual(report.level, .moderate)
    }

    // MARK: - ConfidenceCalibration

    @MainActor
    func testCalibrationInitialState() {
        let cal = ConfidenceCalibration()
        XCTAssertNil(cal.currentReport)
        XCTAssertEqual(cal.currentLevel, .moderate)
    }

    @MainActor
    func testCalibrationReset() {
        let cal = ConfidenceCalibration()
        cal.reset()
        XCTAssertNil(cal.currentReport)
        XCTAssertEqual(cal.currentLevel, .moderate)
    }

    @MainActor
    func testCalibrationAssess() {
        let cal = ConfidenceCalibration()
        let report = cal.assess(
            recentToolResults: [("read_file", true), ("edit_file", true)],
            lspDiagnostics: [:],
            targetFiles: ["/src/main.swift"],
            taskDescription: "fix a simple typo",
            memoryHits: 1,
            loopDetectorPivots: 0
        )
        XCTAssertTrue(report.overallScore >= 0.0)
        XCTAssertTrue(report.overallScore <= 1.0)
        XCTAssertNotNil(cal.currentReport)
    }

    @MainActor
    func testCalibrationAssessWithFailures() {
        let cal = ConfidenceCalibration()
        let report = cal.assess(
            recentToolResults: [("edit_file", false), ("run_command", false), ("edit_file", false)],
            lspDiagnostics: [:],
            targetFiles: [],
            taskDescription: "refactor the entire architecture across multiple packages",
            memoryHits: 0,
            loopDetectorPivots: 3
        )
        // With failures +  complex task + pivots, confidence should be lower
        XCTAssertTrue(report.overallScore < 0.8)
    }

    @MainActor
    func testRecordOutcome() {
        let cal = ConfidenceCalibration()
        // Should not crash with any combo
        cal.recordOutcome(predictedLevel: .high, actualSuccess: true)
        cal.recordOutcome(predictedLevel: .high, actualSuccess: false)
        cal.recordOutcome(predictedLevel: .veryLow, actualSuccess: true)
    }
}
