import XCTest
import SwiftUI
@testable import GRump

final class ThemeManagerTests: XCTestCase {

    // MARK: - Theme Palette Completeness

    func testAllThemesHaveNonClearBackgrounds() {
        for theme in AppTheme.allCases {
            for accent in AccentColorOption.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                // Verify key colors are not .clear (would be invisible)
                XCTAssertNotEqual(palette.bgDark.description, Color.clear.description,
                    "\(theme.displayName) bgDark should not be clear")
                XCTAssertNotEqual(palette.bgCard.description, Color.clear.description,
                    "\(theme.displayName) bgCard should not be clear")
                XCTAssertNotEqual(palette.bgSidebar.description, Color.clear.description,
                    "\(theme.displayName) bgSidebar should not be clear")
            }
        }
    }

    func testAllThemesHaveAccentColors() {
        for theme in AppTheme.allCases {
            for accent in AccentColorOption.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                // effectiveAccent should never be .clear
                XCTAssertNotEqual(palette.effectiveAccent.description, Color.clear.description,
                    "\(theme.displayName) with \(accent.displayName) accent should have a visible effectiveAccent")
            }
        }
    }

    func testAllThemesHaveTextColors() {
        for theme in AppTheme.allCases {
            let palette = ThemePalette(theme: theme, accent: .blue)
            XCTAssertNotEqual(palette.textPrimary.description, Color.clear.description,
                "\(theme.displayName) textPrimary should not be clear")
            XCTAssertNotEqual(palette.textSecondary.description, Color.clear.description,
                "\(theme.displayName) textSecondary should not be clear")
            XCTAssertNotEqual(palette.textMuted.description, Color.clear.description,
                "\(theme.displayName) textMuted should not be clear")
        }
    }

    func testAllThemesHaveBorderColors() {
        for theme in AppTheme.allCases {
            let palette = ThemePalette(theme: theme, accent: .blue)
            // Border colors exist (not nil crash)
            _ = palette.borderCrisp
            _ = palette.borderSubtle
        }
    }

    // MARK: - Theme Properties

    func testAllThemesHaveDisplayName() {
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.displayName.isEmpty,
                "\(theme.rawValue) should have a display name")
        }
    }

    func testAllThemesHaveIcon() {
        for theme in AppTheme.allCases {
            XCTAssertFalse(theme.icon.isEmpty,
                "\(theme.rawValue) should have an icon")
        }
    }

    func testSystemThemeHasNilColorScheme() {
        XCTAssertNil(AppTheme.system.colorScheme, "system theme should have nil colorScheme")
    }

    func testNonSystemThemesHaveColorScheme() {
        for theme in AppTheme.allCases where theme != .system {
            XCTAssertNotNil(theme.colorScheme, "\(theme.rawValue) should have a colorScheme")
        }
    }

    func testThemeCategoriesAreComplete() {
        let allThemes = Set(AppTheme.allCases)
        let categorized = Set(AppTheme.lightThemes + AppTheme.darkThemes + AppTheme.funThemes + [.system])
        let uncategorized = allThemes.subtracting(categorized)
        XCTAssertTrue(uncategorized.isEmpty,
            "Themes not in any category: \(uncategorized.map(\.rawValue))")
    }

    func testLightThemesHaveLightColorScheme() {
        for theme in AppTheme.lightThemes {
            XCTAssertEqual(theme.colorScheme, .light,
                "\(theme.rawValue) is in lightThemes but doesn't have .light colorScheme")
        }
    }

    func testDarkThemesHaveDarkColorScheme() {
        for theme in AppTheme.darkThemes {
            XCTAssertEqual(theme.colorScheme, .dark,
                "\(theme.rawValue) is in darkThemes but doesn't have .dark colorScheme")
        }
    }

    // MARK: - Accent Colors

    func testAllAccentColorsHaveDisplayName() {
        for accent in AccentColorOption.allCases {
            XCTAssertFalse(accent.displayName.isEmpty,
                "\(accent.rawValue) should have a display name")
        }
    }

    func testAccentColorVariantsExist() {
        for accent in AccentColorOption.allCases {
            // Should not crash
            _ = accent.color
            _ = accent.darkVariant
            _ = accent.lightVariant
        }
    }

    // MARK: - Accent Variant Hierarchy

    func testEffectiveAccentVariantsAccessible() {
        // Verify effectiveAccent variants don't crash for any theme/accent combo
        for theme in AppTheme.allCases {
            for accent in AccentColorOption.allCases {
                let palette = ThemePalette(theme: theme, accent: accent)
                _ = palette.effectiveAccent
                _ = palette.effectiveAccentDarkVariant
                _ = palette.effectiveAccentLightVariant
            }
        }
    }

    // MARK: - AppDensity & AppContentSize

    func testAppDensityAllCases() {
        for density in AppDensity.allCases {
            XCTAssertFalse(density.displayName.isEmpty)
            XCTAssertGreaterThan(density.scaleFactor, 0)
        }
    }

    func testAppContentSizeAllCases() {
        for size in AppContentSize.allCases {
            XCTAssertFalse(size.displayName.isEmpty)
            XCTAssertGreaterThan(size.scaleFactor, 0)
        }
    }

    // MARK: - ThemeManager Singleton

    func testThemeManagerSharedExists() {
        let manager = ThemeManager.shared
        XCTAssertNotNil(manager.palette)
        // Verify palette is constructed without crash
        _ = manager.palette.bgDark
        _ = manager.palette.effectiveAccent
    }
}
