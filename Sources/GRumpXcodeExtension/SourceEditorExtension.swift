import Foundation
import XcodeKit

/// Entry point for the G-Rump Xcode Source Editor Extension.
/// Declares the commands available in Xcode's Editor menu.
class SourceEditorExtension: NSObject, XCSourceEditorExtension {

    func extensionDidFinishLaunching() {
        // Called when Xcode loads the extension. Lightweight init only.
    }

    /// Commands appear under Editor > G-Rump in Xcode's menu bar.
    var commandDefinitions: [[XCSourceEditorCommandDefinitionKey: Any]] {
        return [
            [
                .classNameKey: "GRumpXcodeExtension.ExplainSelectionCommand",
                .identifierKey: "com.grump.xcode-extension.explain",
                .nameKey: "Explain Selection"
            ],
            [
                .classNameKey: "GRumpXcodeExtension.RefactorSelectionCommand",
                .identifierKey: "com.grump.xcode-extension.refactor",
                .nameKey: "Refactor Selection"
            ],
            [
                .classNameKey: "GRumpXcodeExtension.AddDocumentationCommand",
                .identifierKey: "com.grump.xcode-extension.document",
                .nameKey: "Add Documentation"
            ],
            [
                .classNameKey: "GRumpXcodeExtension.FixErrorCommand",
                .identifierKey: "com.grump.xcode-extension.fix",
                .nameKey: "Fix This"
            ],
            [
                .classNameKey: "GRumpXcodeExtension.SendToGRumpCommand",
                .identifierKey: "com.grump.xcode-extension.send",
                .nameKey: "Send to G-Rump Chat"
            ],
        ]
    }
}
