import XCTest
import SwiftUI
@testable import GRump

final class BrandColorsTests: XCTestCase {

    // MARK: - Primary Purple Palette

    func testBrandPurpleExists() {
        let color = Color.brandPurple
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    func testBrandPurpleDarkExists() {
        let color = Color.brandPurpleDark
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    func testBrandPurpleLightExists() {
        let color = Color.brandPurpleLight
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    func testBrandPurpleSubtleExists() {
        let color = Color.brandPurpleSubtle
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    // MARK: - Background Palette

    func testBackgroundColorsExist() {
        let colors: [Color] = [
            .bgDark, .bgCard, .bgSidebar,
            .bgInput, .bgElevated, .bgCrisp
        ]
        for color in colors {
            XCTAssertNotEqual(color.description, Color.clear.description,
                "Background color should not be clear")
        }
    }

    func testBgHighlightExists() {
        let color = Color.bgHighlight
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    // MARK: - Text Colors

    func testTextColorsExist() {
        _ = Color.textPrimary
        _ = Color.textSecondary
        _ = Color.textMuted
    }

    // MARK: - Accent Colors

    func testAccentGlowExists() {
        let color = Color.accentGlow
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    func testAccentGreenExists() {
        let color = Color.accentGreen
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    func testAccentOrangeExists() {
        let color = Color.accentOrange
        XCTAssertNotEqual(color.description, Color.clear.description)
    }

    // MARK: - User Bubble Colors

    func testUserBubbleColors() {
        let bubble = Color.userBubble
        let text = Color.userBubbleText
        XCTAssertNotEqual(bubble.description, Color.clear.description)
        XCTAssertNotEqual(text.description, Color.clear.description)
    }

    // MARK: - Border Colors

    func testBorderColors() {
        _ = Color.borderSubtle
        _ = Color.borderCrisp
    }

    func testBorderFocus() {
        let focused = Color.borderFocus(.blue)
        XCTAssertNotEqual(focused.description, Color.clear.description)
    }

    func testBorderFocusWithBrandPurple() {
        let focused = Color.borderFocus(.brandPurple)
        XCTAssertNotEqual(focused.description, Color.clear.description)
    }
}
