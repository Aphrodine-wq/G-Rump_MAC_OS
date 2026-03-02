import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for applying code blocks to files, tracking apply/reject state,
/// and supporting undo for applied changes.
@MainActor
final class CodeApplyService: ObservableObject {
    static let shared = CodeApplyService()

    /// State of a code block's apply/reject status.
    enum ApplyState: Equatable, Codable {
        case pending
        case applied
        case rejected
    }

    /// Tracks per-code-block state keyed by a stable ID (conversation + block index).
    @Published private(set) var blockStates: [String: ApplyState] = [:]

    /// Stores original file content before apply for undo support.
    private var undoStack: [String: String] = [:]  // blockId -> original content

    // MARK: - Apply

    /// Apply code to a file path. Stores original for undo.
    /// Returns nil on success, or an error message.
    func apply(blockId: String, code: String, toFile filePath: String) -> String? {
        let url = URL(fileURLWithPath: filePath)
        let fm = FileManager.default

        // Store original for undo
        if fm.fileExists(atPath: filePath) {
            if let original = try? String(contentsOf: url, encoding: .utf8) {
                undoStack[blockId] = original
            }
        }

        // Ensure parent directory exists
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            do {
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
            } catch {
                return "Failed to create directory: \(error.localizedDescription)"
            }
        }

        do {
            try code.write(to: url, atomically: true, encoding: .utf8)
            blockStates[blockId] = .applied
            return nil
        } catch {
            return "Failed to write file: \(error.localizedDescription)"
        }
    }

    // MARK: - Reject

    func reject(blockId: String) {
        blockStates[blockId] = .rejected
    }

    // MARK: - Undo

    /// Undo a previously applied code block. Restores original file content.
    func undo(blockId: String, filePath: String) -> String? {
        guard let original = undoStack[blockId] else {
            return "No undo data available for this block."
        }

        let url = URL(fileURLWithPath: filePath)
        do {
            try original.write(to: url, atomically: true, encoding: .utf8)
            blockStates[blockId] = .pending
            undoStack.removeValue(forKey: blockId)
            return nil
        } catch {
            return "Failed to undo: \(error.localizedDescription)"
        }
    }

    // MARK: - State Queries

    func state(for blockId: String) -> ApplyState {
        blockStates[blockId] ?? .pending
    }

    func resetStates(for conversationId: UUID) {
        let prefix = conversationId.uuidString
        for key in blockStates.keys where key.hasPrefix(prefix) {
            blockStates.removeValue(forKey: key)
            undoStack.removeValue(forKey: key)
        }
    }

    // MARK: - File Path Detection

    /// Try to extract a file path from the code block's context (preceding text).
    /// Looks for patterns like: `path/to/file.swift`, `// file: path`, etc.
    static func detectFilePath(from context: String, language: String) -> String? {
        let lines = context.split(separator: "\n").map(String.init)

        // Check last few lines before the code block for file path hints
        let searchLines = lines.suffix(5)
        for line in searchLines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Pattern: `file: path/to/file.ext` or `File: path/to/file.ext`
            if let match = trimmed.range(of: #"(?:file|path|in)\s*:\s*[`"]?([^\s`"]+\.\w+)"#, options: .regularExpression) {
                let pathMatch = trimmed[match]
                // Extract the path part after the colon
                if let colonRange = pathMatch.range(of: ":") {
                    let path = String(pathMatch[colonRange.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
                    if !path.isEmpty { return path }
                }
            }

            // Pattern: backticked path `path/to/file.ext`
            if let match = trimmed.range(of: #"`([^`]+\.\w+)`"#, options: .regularExpression) {
                let captured = trimmed[match].dropFirst().dropLast()
                let path = String(captured)
                if path.contains("/") || path.contains(".") {
                    return path
                }
            }
        }

        return nil
    }

    /// Generate a stable block ID from conversation ID and block index.
    static func blockId(conversationId: UUID, blockIndex: Int) -> String {
        "\(conversationId.uuidString)-block-\(blockIndex)"
    }
}
