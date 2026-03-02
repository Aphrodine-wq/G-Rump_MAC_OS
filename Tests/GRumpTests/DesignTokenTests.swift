import XCTest
@testable import GRump

final class DesignTokenTests: XCTestCase {

    // MARK: - Spacing

    func testSpacingValuesArePositive() {
        XCTAssertGreaterThan(Spacing.xxs, 0)
        XCTAssertGreaterThan(Spacing.xs, 0)
        XCTAssertGreaterThan(Spacing.sm, 0)
        XCTAssertGreaterThan(Spacing.md, 0)
        XCTAssertGreaterThan(Spacing.lg, 0)
        XCTAssertGreaterThan(Spacing.xl, 0)
        XCTAssertGreaterThan(Spacing.xxl, 0)
        XCTAssertGreaterThan(Spacing.xxxl, 0)
        XCTAssertGreaterThan(Spacing.huge, 0)
        XCTAssertGreaterThan(Spacing.massive, 0)
        XCTAssertGreaterThan(Spacing.giant, 0)
        XCTAssertGreaterThan(Spacing.colossal, 0)
    }

    func testSpacingValuesIncreaseMonotonically() {
        let values: [CGFloat] = [
            Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
            Spacing.lg, Spacing.xl, Spacing.xxl, Spacing.xxxl,
            Spacing.huge, Spacing.massive, Spacing.giant, Spacing.colossal,
        ]
        for i in 1..<values.count {
            XCTAssertGreaterThanOrEqual(values[i], values[i - 1],
                "Spacing values should increase monotonically")
        }
    }

    // MARK: - Radius

    func testRadiusValuesAreNonNegative() {
        XCTAssertGreaterThanOrEqual(Radius.xs, 0)
        XCTAssertGreaterThanOrEqual(Radius.sm, 0)
        XCTAssertGreaterThanOrEqual(Radius.md, 0)
        XCTAssertGreaterThanOrEqual(Radius.standard, 0)
        XCTAssertGreaterThanOrEqual(Radius.lg, 0)
        XCTAssertGreaterThanOrEqual(Radius.xl, 0)
        XCTAssertGreaterThanOrEqual(Radius.xxl, 0)
        XCTAssertGreaterThanOrEqual(Radius.bubble, 0)
        XCTAssertGreaterThanOrEqual(Radius.pill, 0)
    }

    func testRadiusIncreases() {
        XCTAssertLessThan(Radius.xs, Radius.sm)
        XCTAssertLessThan(Radius.sm, Radius.md)
        XCTAssertLessThan(Radius.md, Radius.standard)
        XCTAssertLessThan(Radius.standard, Radius.lg)
        XCTAssertLessThan(Radius.lg, Radius.xl)
    }

    // MARK: - Border

    func testBorderValues() {
        XCTAssertGreaterThan(Border.hairline, 0)
        XCTAssertGreaterThan(Border.thin, 0)
        XCTAssertGreaterThan(Border.medium, 0)
        XCTAssertLessThan(Border.hairline, Border.thin)
        XCTAssertLessThan(Border.thin, Border.medium)
    }

    // MARK: - Animation Durations

    func testAnimDurationsArePositive() {
        XCTAssertGreaterThan(Anim.instant, 0)
        XCTAssertGreaterThan(Anim.quick, 0)
        XCTAssertGreaterThan(Anim.standard, 0)
        XCTAssertGreaterThan(Anim.smooth, 0)
        XCTAssertGreaterThan(Anim.gentle, 0)
        XCTAssertGreaterThan(Anim.slow, 0)
        XCTAssertGreaterThan(Anim.splash, 0)
        XCTAssertGreaterThan(Anim.stagger, 0)
        XCTAssertGreaterThan(Anim.bounce, 0)
    }

    func testAnimDurationsIncrease() {
        XCTAssertLessThanOrEqual(Anim.instant, Anim.quick)
        XCTAssertLessThanOrEqual(Anim.quick, Anim.standard)
        XCTAssertLessThanOrEqual(Anim.standard, Anim.smooth)
        XCTAssertLessThanOrEqual(Anim.smooth, Anim.gentle)
        XCTAssertLessThanOrEqual(Anim.gentle, Anim.slow)
        XCTAssertLessThanOrEqual(Anim.slow, Anim.splash)
    }

    func testAnimDurationsReasonableRange() {
        // Animations should be < 1 second for good UX
        for duration in [Anim.instant, Anim.quick, Anim.standard, Anim.smooth, Anim.gentle, Anim.slow, Anim.splash] {
            XCTAssertLessThanOrEqual(duration, 1.0, "Animation duration should be under 1 second")
        }
    }

    // MARK: - Typography Scaled

    func testTypographyScaledFunctions() {
        // These should not crash with various scale values
        _ = Typography.bodyScaled(scale: 0.5)
        _ = Typography.bodyScaled(scale: 1.0)
        _ = Typography.bodyScaled(scale: 1.5)
        _ = Typography.bodySmallScaled(scale: 1.0)
        _ = Typography.codeScaled(scale: 1.0)
        _ = Typography.codeLargeScaled(scale: 1.0)
        _ = Typography.codeSmallScaled(scale: 1.0)
        _ = Typography.captionSmallScaled(scale: 1.0)
    }
}
