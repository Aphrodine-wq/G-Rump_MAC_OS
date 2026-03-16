import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Centralized haptic feedback for micro-interactions.
enum HapticHelper {
    #if os(iOS)
    private static var lightGenerator: UIImpactFeedbackGenerator?
    private static var mediumGenerator: UIImpactFeedbackGenerator?
    private static var notificationGenerator: UINotificationFeedbackGenerator?

    private static func ensureGenerators() {
        if lightGenerator == nil { lightGenerator = UIImpactFeedbackGenerator(style: .light) }
        if mediumGenerator == nil { mediumGenerator = UIImpactFeedbackGenerator(style: .medium) }
        if notificationGenerator == nil { notificationGenerator = UINotificationFeedbackGenerator() }
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        ensureGenerators()
        if style == .light {
            lightGenerator?.impactOccurred()
        } else {
            mediumGenerator?.impactOccurred()
        }
    }

    static func success() {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        ensureGenerators()
        notificationGenerator?.notificationOccurred(.success)
    }

    static func error() {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        ensureGenerators()
        notificationGenerator?.notificationOccurred(.error)
    }
    #elseif os(macOS)
    static func impact() {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    static func success() {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    static func error() {
        guard UserDefaults.standard.object(forKey: "HapticFeedbackEnabled") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    #endif
}
