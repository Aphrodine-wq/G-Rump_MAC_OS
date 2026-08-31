import SwiftUI

/// Public launcher kept intentionally tiny so the GUI implementation remains
/// an importable/testable library while the app product owns the entry point.
public enum GRumpApplication {
    @MainActor
    public static func launch() {
        GRumpApp.main()
    }
}
