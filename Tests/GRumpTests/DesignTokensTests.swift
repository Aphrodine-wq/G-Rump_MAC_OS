import XCTest
import SwiftUI
@testable import GRump

// NOTE: Primary DesignToken tests are in DesignTokenTests.swift.
// This file adds supplementary coverage for Typography and exact values.
final class DesignTokensTests: XCTestCase {

    // MARK: - Spacing

    func testSpacingValuesArePositive() {
        let values: [CGFloat] = [
            Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
            Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl,
            Spacing.huge, Spacing.massive, Spacing.giant, Spacing.colossal,
        ]
        for value in values {
            XCTAssertGreaterThan(value, 0)
        }
    }

    func testSpacingValuesAscending() {
        let ordered: [CGFloat] = [
            Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
            Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl,
            Spacing.huge, Spacing.massive, Spacing.giant, Spacing.colossal,
        ]
        for i in 1..<ordered.count {
            XCTAssertGreaterThanOrEqual(ordered[i], ordered[i-1],
                "Spacing values should be non-decreasing")
        }
    }

    func testSpecificSpacingValues() {
        XCTAssertEqual(Spacing.xxs, 1)
        XCTAssertEqual(Spacing.sm, 4)
        XCTAssertEqual(Spacing.lg, 8)
        XCTAssertEqual(Spacing.huge, 16)
        XCTAssertEqual(Spacing.colossal, 32)
    }

    // MARK: - Radius

    func testRadiusValuesArePositive() {
        let values: [CGFloat] = [
            Radius.xs, Radius.sm, Radius.md, Radius.standard,
            Radius.lg, Radius.xl, Radius.xxl, Radius.bubble, Radius.pill,
        ]
        for value in values {
            XCTAssertGreaterThan(value, 0)
        }
    }

    func testRadiusStandardValues() {
        XCTAssertEqual(Radius.xs, 2)
        XCTAssertEqual(Radius.sm, 4)
        XCTAssertEqual(Radius.standard, 8)
        XCTAssertEqual(Radius.pill, 20)
    }

    func testRadiusBubbleValue() {
        XCTAssertEqual(Radius.bubble, 14)
    }

    // MARK: - Border

    func testBorderValuesArePositive() {
        XCTAssertGreaterThan(Border.hairline, 0)
        XCTAssertGreaterThan(Border.thin, 0)
        XCTAssertGreaterThan(Border.medium, 0)
    }

    func testBorderValuesAscending() {
        XCTAssertLessThan(Border.hairline, Border.thin)
        XCTAssertLessThan(Border.thin, Border.medium)
    }

    func testSpecificBorderValues() {
        XCTAssertEqual(Border.hairline, 0.5)
        XCTAssertEqual(Border.thin, 1)
        XCTAssertEqual(Border.medium, 1.5)
    }

    // MARK: - Anim

    func testAnimValuesArePositive() {
        let values: [Double] = [
            Anim.instant, Anim.quick, Anim.standard, Anim.smooth,
            Anim.gentle, Anim.slow, Anim.splash, Anim.stagger, Anim.bounce,
        ]
        for value in values {
            XCTAssertGreaterThan(value, 0)
        }
    }

    func testAnimDurationsAscending() {
        let ordered: [Double] = [
            Anim.instant, Anim.quick, Anim.standard, Anim.smooth,
            Anim.gentle, Anim.slow, Anim.splash,
        ]
        for i in 1..<ordered.count {
            XCTAssertGreaterThanOrEqual(ordered[i], ordered[i-1],
                "Anim durations should be non-decreasing")
        }
    }

    func testAnimInstantIsFast() {
        XCTAssertLessThanOrEqual(Anim.instant, 0.15, "Instant should feel immediate")
    }

    func testAnimStaggerIsSmall() {
        XCTAssertLessThanOrEqual(Anim.stagger, 0.1, "Stagger should be a small delay")
    }

    func testSpecificAnimValues() {
        XCTAssertEqual(Anim.instant, 0.12)
        XCTAssertEqual(Anim.quick, 0.15)
        XCTAssertEqual(Anim.standard, 0.18)
        XCTAssertEqual(Anim.splash, 0.5)
    }

    // MARK: - Typography

    func testTypographyFontsExist() {
        // Just verify these don't crash
        _ = Typography.displayLarge
        _ = Typography.displayMedium
        _ = Typography.heading1
        _ = Typography.heading2
        _ = Typography.heading3
        _ = Typography.bodyLarge
        _ = Typography.body
        _ = Typography.bodyMedium
        _ = Typography.bodySemibold
        _ = Typography.bodySmall
        _ = Typography.bodySmallMedium
        _ = Typography.bodySmallSemibold
        _ = Typography.caption
        _ = Typography.captionSemibold
        _ = Typography.captionSmall
        _ = Typography.captionSmallMedium
        _ = Typography.captionSmallSemibold
        _ = Typography.micro
        _ = Typography.microSemibold
        _ = Typography.sidebarTitle
        _ = Typography.codeLarge
        _ = Typography.code
        _ = Typography.codeSmall
        _ = Typography.codeMicro
        _ = Typography.splashTitle
        _ = Typography.splashSubtitle
        _ = Typography.sparkleIcon
        _ = Typography.sparkleSubtitle
        _ = Typography.emptyStateIcon
        _ = Typography.onboardingIcon
    }

    func testTypographyScaledFonts() {
        _ = Typography.bodyScaled(scale: 1.0)
        _ = Typography.bodySmallScaled(scale: 1.5)
        _ = Typography.codeScaled(scale: 0.8)
        _ = Typography.codeLargeScaled(scale: 1.2)
        _ = Typography.codeSmallScaled(scale: 1.0)
        _ = Typography.captionSmallScaled(scale: 1.0)
    }

    func testTypographyScaledFontsWithEdgeScales() {
        _ = Typography.bodyScaled(scale: 0.5)
        _ = Typography.bodyScaled(scale: 2.0)
        _ = Typography.codeScaled(scale: 0.1)
    }
}
