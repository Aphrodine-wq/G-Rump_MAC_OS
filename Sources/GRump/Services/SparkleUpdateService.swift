#if os(macOS)
import SwiftUI
import Sparkle

/// Wraps Sparkle's SPUUpdater for SwiftUI integration.
/// Configure the appcast URL in Info.plist (SUFeedURL) or via the updater.
final class SparkleUpdateService: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false
    @Published var lastUpdateCheckDate: Date?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Bind canCheckForUpdates from updater
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        updaterController.updater.publisher(for: \.lastUpdateCheckDate)
            .assign(to: &$lastUpdateCheckDate)
    }

    var updater: SPUUpdater {
        updaterController.updater
    }

    /// Check for updates interactively (shows UI if update found)
    func checkForUpdates() {
        updaterController.updater.checkForUpdates()
    }

    /// Whether automatic update checks are enabled
    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Update check interval in seconds (default: 1 day)
    var updateCheckInterval: TimeInterval {
        get { updaterController.updater.updateCheckInterval }
        set { updaterController.updater.updateCheckInterval = newValue }
    }
}

/// SwiftUI view for "Check for Updates" menu item
struct CheckForUpdatesView: View {
    @ObservedObject var sparkle: SparkleUpdateService

    var body: some View {
        Button("Check for Updates…") {
            sparkle.checkForUpdates()
        }
        .disabled(!sparkle.canCheckForUpdates)
    }
}

/// Settings section for update preferences
struct UpdateSettingsSection: View {
    @ObservedObject var sparkle: SparkleUpdateService

    var body: some View {
        Section("Software Updates") {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { sparkle.automaticallyChecksForUpdates },
                set: { sparkle.automaticallyChecksForUpdates = $0 }
            ))

            if let lastCheck = sparkle.lastUpdateCheckDate {
                Text("Last checked: \(lastCheck, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Check for Updates Now") {
                sparkle.checkForUpdates()
            }
            .disabled(!sparkle.canCheckForUpdates)
        }
    }
}
#endif
