import Foundation
import XcodeKit

// MARK: - Base Command

/// Shared logic for all G-Rump Xcode commands.
/// Extracts the selected text (or full buffer), communicates with the main app
/// via App Group UserDefaults, and replaces or annotates the selection.
class GRumpBaseCommand: NSObject, XCSourceEditorCommand {

    /// Override in subclasses to provide the AI instruction.
    var systemInstruction: String { "" }

    /// Override to control whether the result replaces the selection or is appended.
    var replacesSelection: Bool { false }

    func perform(
        with invocation: XCSourceEditorCommandInvocation,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let buffer = invocation.buffer
        let selections = buffer.selections as! [XCSourceTextRange]

        guard let selection = selections.first else {
            completionHandler(nil)
            return
        }

        // Extract selected text
        let lines = buffer.lines as! [String]
        let selectedText = extractText(from: lines, selection: selection)

        guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completionHandler(nil)
            return
        }

        // Build the request payload and hand off to the main G-Rump app
        // via shared App Group container (com.grump.shared)
        let payload: [String: Any] = [
            "command": type(of: self).commandIdentifier,
            "selectedText": selectedText,
            "instruction": systemInstruction,
            "language": buffer.contentUTI,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Write to shared UserDefaults for the main app to pick up
        if let shared = UserDefaults(suiteName: "group.com.grump.shared") {
            shared.set(payload, forKey: "PendingXcodeRequest")
            shared.synchronize()
        }

        // Open the main app to process the request
        // The main app watches for PendingXcodeRequest and handles it
        if let url = URL(string: "grump://xcode-command") {
            NSWorkspace.shared.open(url)
        }

        completionHandler(nil)
    }

    /// Subclasses should return their command identifier string.
    class var commandIdentifier: String { "" }

    // MARK: - Text Extraction

    private func extractText(from lines: [String], selection: XCSourceTextRange) -> String {
        if selection.start.line == selection.end.line {
            let line = lines[selection.start.line]
            let startIdx = line.index(line.startIndex, offsetBy: min(selection.start.column, line.count))
            let endIdx = line.index(line.startIndex, offsetBy: min(selection.end.column, line.count))
            return String(line[startIdx..<endIdx])
        }

        var result = ""
        for lineIdx in selection.start.line...min(selection.end.line, lines.count - 1) {
            let line = lines[lineIdx]
            if lineIdx == selection.start.line {
                let startIdx = line.index(line.startIndex, offsetBy: min(selection.start.column, line.count))
                result += String(line[startIdx...])
            } else if lineIdx == selection.end.line {
                let endIdx = line.index(line.startIndex, offsetBy: min(selection.end.column, line.count))
                result += String(line[..<endIdx])
            } else {
                result += line
            }
        }
        return result
    }
}

// MARK: - Concrete Commands

class ExplainSelectionCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Explain this code clearly and concisely. Cover what it does, why, and any notable patterns or potential issues."
    }
    override class var commandIdentifier: String { "explain" }
}

class RefactorSelectionCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Refactor this code to be cleaner, more idiomatic, and more maintainable. Preserve the existing behavior. Use modern Swift patterns where applicable."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "refactor" }
}

class AddDocumentationCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Add clear, concise documentation comments to this code following Apple's documentation style (/// for single-line, /** */ for multi-line). Include parameter descriptions, return values, and throws clauses where applicable."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "document" }
}

class FixErrorCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Analyze this code for bugs, compiler errors, or logic issues. Fix them and return the corrected code with a brief comment explaining what was wrong."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "fix" }
}

class GenerateTestsCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Generate comprehensive unit tests for this code using XCTest. Cover happy paths, edge cases, and error conditions. Use descriptive test method names following the pattern test_methodName_condition_expectedResult."
    }
    override var replacesSelection: Bool { false }
    override class var commandIdentifier: String { "generate-tests" }
}

class OptimizeCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Optimize this code for performance. Identify bottlenecks, reduce allocations, and apply Swift-specific optimizations. Preserve correctness and readability."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "optimize" }
}

class SendToGRumpCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "The user selected this code in Xcode and sent it to you for assistance. Ask what they would like to do with it."
    }
    override class var commandIdentifier: String { "send" }
}

// MARK: - Deep Integration Commands

class ConvertToAsyncCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Convert this code from completion handler / delegate pattern to modern Swift async/await. Use structured concurrency (async let, TaskGroup) where appropriate. Maintain error handling with throws instead of Result or optional Error parameters. Preserve the public API contract where possible."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "convert-async" }
}

class AddAccessibilityCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Add comprehensive accessibility support to this SwiftUI view code. Include .accessibilityLabel(), .accessibilityHint(), .accessibilityValue(), .accessibilityAddTraits(), and .accessibilityIdentifier() modifiers. Ensure Dynamic Type support, sufficient contrast, and proper grouping with .accessibilityElement(children:). Follow Apple's Human Interface Guidelines for accessibility."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "add-accessibility" }
}

class GeneratePreviewCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Generate a comprehensive SwiftUI #Preview block for this view. Include multiple preview variants: default state, dark mode, different Dynamic Type sizes, and edge cases (empty data, long text, error states). Use PreviewProvider with named previews if targeting < iOS 17, or #Preview macros for iOS 17+."
    }
    override var replacesSelection: Bool { false }
    override class var commandIdentifier: String { "generate-preview" }
}

class ExplainBuildErrorCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "This code has a build error or compiler diagnostic. Analyze the code, identify what's causing the error, explain the root cause in plain language, and provide the corrected code. Common Swift compiler issues include type mismatches, missing conformances, concurrency isolation violations, and ambiguous expressions."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "explain-build-error" }
}

class GenerateDocCCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Generate Apple DocC-style documentation for this code. Use /// documentation comments with proper markup: ``Symbol`` for code references, - Parameters: / - Returns: / - Throws: sections, > Note: / > Warning: / > Important: callouts, and code examples in ```swift blocks. Follow Apple's documentation style from their own frameworks."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "generate-docc" }
}

class ExtractProtocolCommand: GRumpBaseCommand {
    override var systemInstruction: String {
        "Extract a protocol from this class or struct. Identify the public interface, create a protocol with the same methods and properties, and make the original type conform to it. Use associatedtype where generic parameters are involved. This enables dependency injection and testability."
    }
    override var replacesSelection: Bool { true }
    override class var commandIdentifier: String { "extract-protocol" }
}
