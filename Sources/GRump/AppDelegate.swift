#if os(macOS)
import AppKit

/// Handles single-instance enforcement and other macOS-specific app lifecycle.
/// When a second G-Rump instance is launched (e.g. dist .app + old .build binary),
/// SwiftData/SQLite file locking can cause both to freeze on the splash screen.
/// This delegate activates the existing instance and quits the duplicate.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Run before GRumpApp init/ModelContainer — prevents DB lock freeze when two instances launch
        enforceSingleInstance()
    }

    /// If another G-Rump instance is running, activate it and quit this one.
    /// Works both for .app bundles (bundle ID match) and bare SPM debug builds
    /// (executable name match) to prevent SwiftData/SQLite lock freezes.
    private func enforceSingleInstance() {
        let current = NSRunningApplication.current
        let others: [NSRunningApplication]

        if let ourID = Bundle.main.bundleIdentifier, !ourID.isEmpty {
            others = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == ourID && $0.processIdentifier != current.processIdentifier
            }
        } else {
            // SPM debug build — no bundle ID. Match by executable name instead.
            let ourName = ProcessInfo.processInfo.processName
            others = NSWorkspace.shared.runningApplications.filter {
                $0.localizedName == ourName && $0.processIdentifier != current.processIdentifier
            }
        }

        if let existing = others.first {
            existing.activate(options: .activateAllWindows)
            NSApplication.shared.terminate(nil)
        }
    }
}
#endif
