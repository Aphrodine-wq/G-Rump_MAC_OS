import SwiftUI

// MARK: - Typography Scale

enum Typography {
    // Display
    static let displayLarge = Font.system(size: 30, weight: .bold, design: .rounded)
    static let displayMedium = Font.system(size: 24, weight: .bold, design: .rounded)

    // Headings
    static let heading1 = Font.system(size: 22, weight: .bold)
    static let heading2 = Font.system(size: 18, weight: .bold)
    static let heading3 = Font.system(size: 16, weight: .semibold)

    // Body
    static let bodyLarge = Font.system(size: 15)
    static let body = Font.system(size: 14)
    static let bodyMedium = Font.system(size: 14, weight: .medium)
    static let bodySemibold = Font.system(size: 14, weight: .semibold)
    static let bodySmall = Font.system(size: 13)
    static let bodySmallMedium = Font.system(size: 13, weight: .medium)
    static let bodySmallSemibold = Font.system(size: 13, weight: .semibold)

    // Caption / Metadata
    static let caption = Font.system(size: 12)
    static let captionSemibold = Font.system(size: 12, weight: .semibold)
    static let captionSmall = Font.system(size: 11)
    static let captionSmallMedium = Font.system(size: 11, weight: .medium)
    static let captionSmallSemibold = Font.system(size: 11, weight: .semibold)
    static let micro = Font.system(size: 10)
    static let microSemibold = Font.system(size: 10, weight: .semibold)

    // Sidebar title
    static let sidebarTitle = Font.system(size: 15, weight: .bold, design: .rounded)

    // Code
    static let codeLarge = Font.system(size: 13, design: .monospaced)
    static let code = Font.system(size: 12, design: .monospaced)
    static let codeSmall = Font.system(size: 11, design: .monospaced)
    static let codeMicro = Font.system(size: 10, design: .monospaced)

    // Special
    static let splashTitle = Font.system(size: 30, weight: .bold, design: .rounded)
    static let splashSubtitle = Font.system(size: 14, weight: .medium, design: .rounded)
    static let sparkleIcon = Font.system(size: 9, weight: .bold)
    static let sparkleSubtitle = Font.system(size: 13)
    static let emptyStateIcon = Font.system(size: 48, weight: .medium)
    static let onboardingIcon = Font.system(size: 54, weight: .semibold)

    // Content-size scaled (for user preference: Small / Medium / Large)
    static func bodyScaled(scale: CGFloat) -> Font { .system(size: 14 * scale) }
    static func bodySmallScaled(scale: CGFloat) -> Font { .system(size: 13 * scale) }
    static func codeScaled(scale: CGFloat) -> Font { .system(size: 12 * scale, design: .monospaced) }
    static func codeLargeScaled(scale: CGFloat) -> Font { .system(size: 13 * scale, design: .monospaced) }
    static func codeSmallScaled(scale: CGFloat) -> Font { .system(size: 11 * scale, design: .monospaced) }
    static func captionSmallScaled(scale: CGFloat) -> Font { .system(size: 11 * scale, weight: .medium) }
}

// MARK: - Spacing Scale (4pt base)

enum Spacing {
    static let xxs: CGFloat = 1
    static let xs: CGFloat = 3
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let xl: CGFloat = 10
    static let xxl: CGFloat = 12
    static let xxxl: CGFloat = 14
    static let huge: CGFloat = 16
    static let massive: CGFloat = 20
    static let giant: CGFloat = 28
    static let colossal: CGFloat = 32
}

// MARK: - Corner Radii (crisp: slightly tighter for clarity)

enum Radius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let standard: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let bubble: CGFloat = 14
    static let pill: CGFloat = 20
}

// MARK: - Border (crisp 1pt)

enum Border {
    static let hairline: CGFloat = 0.5
    static let thin: CGFloat = 1
    static let medium: CGFloat = 1.5
}

// MARK: - Animation Durations
// Prefer instant/quick for micro-interactions to keep the UI feeling 250fps-ready.

enum Anim {
    static let instant: Double = 0.12
    static let quick: Double = 0.15
    static let standard: Double = 0.18
    static let smooth: Double = 0.25
    static let gentle: Double = 0.28
    static let slow: Double = 0.4
    static let splash: Double = 0.5
    /// Stagger delay for sequential item animations (e.g. message list).
    static let stagger: Double = 0.05
    /// Bounce / spring-like micro-interaction.
    static let bounce: Double = 0.35
}
