import Foundation
import CryptoKit
import OSLog

// MARK: - Cognitive Loop Detector
//
// Detects when the agent is stuck in a repeating failure pattern —
// e.g., making the same edit, hitting the same error, oscillating
// between two approaches. Automatically triggers a strategy pivot
// by injecting a system message that forces a new approach.
//
// No AI coding tool does semantic loop detection. They all loop until
// max iterations. This makes the agent self-aware of its own failure modes.

// MARK: - Action Fingerprint

struct ActionFingerprint: Equatable {
    let toolName: String
    let argsHash: String
    let resultHash: String
    let wasError: Bool
    let timestamp: Date

    /// Similarity to another fingerprint (0.0 = unrelated, 1.0 = identical).
    func similarity(to other: ActionFingerprint) -> Double {
        var score = 0.0
        if toolName == other.toolName { score += 0.4 }
        if argsHash == other.argsHash { score += 0.35 }
        if resultHash == other.resultHash { score += 0.15 }
        if wasError == other.wasError { score += 0.1 }
        return score
    }
}

// MARK: - Loop Pattern

struct LoopPattern: Identifiable {
    let id = UUID()
    let fingerprints: [ActionFingerprint]
    let cycleLength: Int
    let confidence: Double
    let detectedAt: Date
}

// MARK: - Pivot Strategy

enum PivotStrategy: String, CaseIterable {
    case alternativeApproach
    case simplify
    case decompose
    case askUser
    case useAlternativeTool
    case readContext

    var systemMessage: String {
        switch self {
        case .alternativeApproach:
            return """
            LOOP DETECTED: You have been repeating a similar action pattern that is not making progress. \
            STOP your current approach entirely. Think step-by-step about WHY your previous attempts failed, \
            then try a fundamentally different approach. Do not retry the same strategy with minor variations.
            """
        case .simplify:
            return """
            LOOP DETECTED: Your repeated attempts suggest the problem may be more complex than expected. \
            SIMPLIFY: Break the problem into the smallest possible piece that you can solve with certainty. \
            Solve that piece first, verify it works, then build on it incrementally.
            """
        case .decompose:
            return """
            LOOP DETECTED: You appear to be stuck. DECOMPOSE the task: \
            1) List what you know for certain about the current state. \
            2) List what you are unsure about. \
            3) Read any files or run any diagnostic commands needed to resolve uncertainties. \
            4) Only then attempt a fix based on verified information.
            """
        case .askUser:
            return """
            LOOP DETECTED: Multiple attempts have not resolved this issue. \
            Ask the user a specific, targeted question about what they expect. \
            Do NOT attempt another fix until you hear back from the user.
            """
        case .useAlternativeTool:
            return """
            LOOP DETECTED: The tool you've been using repeatedly may not be the right one. \
            Consider using a different tool or approach entirely. For example: \
            - If editing a file keeps failing, try reading it first to verify its current state. \
            - If a build keeps failing, check dependencies or read the error more carefully. \
            - If a command keeps failing, check if prerequisites are met.
            """
        case .readContext:
            return """
            LOOP DETECTED: You may be missing context. Before attempting any more fixes: \
            1) Read the relevant file(s) in full to understand current state. \
            2) Check git status and recent changes. \
            3) Look at any related test files or documentation. \
            Then proceed with a fresh approach based on what you actually see.
            """
        }
    }
}

// MARK: - Cognitive Loop Detector

actor CognitiveLoopDetector {

    // Configuration
    private let windowSize: Int
    private let similarityThreshold: Double
    private let minCycleDetections: Int
    private let maxHistorySize: Int

    // State
    private var history: [ActionFingerprint] = []
    private var detectedLoops: [LoopPattern] = []
    private var pivotCount: Int = 0
    private var lastPivotStrategy: PivotStrategy?
    private var pivotSuccessRate: [PivotStrategy: (successes: Int, total: Int)] = [:]

    private let logger = GRumpLogger.general

    init(
        windowSize: Int = 12,
        similarityThreshold: Double = 0.75,
        minCycleDetections: Int = 3,
        maxHistorySize: Int = 50
    ) {
        self.windowSize = windowSize
        self.similarityThreshold = similarityThreshold
        self.minCycleDetections = minCycleDetections
        self.maxHistorySize = maxHistorySize
    }

    // MARK: - Recording

    /// Record an action (tool call + result) and check for loops.
    /// Returns a pivot strategy if a loop is detected, nil otherwise.
    func recordAction(
        toolName: String,
        arguments: String,
        result: String,
        wasError: Bool
    ) -> PivotStrategy? {
        let fingerprint = ActionFingerprint(
            toolName: toolName,
            argsHash: stableHash(truncate(arguments, max: 500)),
            resultHash: stableHash(truncate(result, max: 500)),
            wasError: wasError,
            timestamp: Date()
        )

        history.append(fingerprint)

        // Trim history to prevent unbounded growth
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }

        // Check for loops
        if let pattern = detectLoop() {
            detectedLoops.append(pattern)
            let strategy = selectPivotStrategy(pattern: pattern)
            pivotCount += 1
            lastPivotStrategy = strategy
            logger.info("CognitiveLoopDetector: Loop detected (cycle=\(pattern.cycleLength), confidence=\(String(format: "%.2f", pattern.confidence))). Pivoting with strategy: \(strategy.rawValue)")
            return strategy
        }

        return nil
    }

    /// Call when the agent successfully completes after a pivot.
    /// Improves future pivot strategy selection.
    func recordPivotOutcome(success: Bool) {
        guard let strategy = lastPivotStrategy else { return }
        var stats = pivotSuccessRate[strategy] ?? (successes: 0, total: 0)
        stats.total += 1
        if success { stats.successes += 1 }
        pivotSuccessRate[strategy] = stats
    }

    /// Reset state for a new conversation turn.
    func reset() {
        history.removeAll()
        detectedLoops.removeAll()
        pivotCount = 0
        lastPivotStrategy = nil
    }

    /// Number of loops detected in this session.
    var loopCount: Int { detectedLoops.count }

    /// Number of pivots triggered.
    var totalPivots: Int { pivotCount }

    // MARK: - Detection

    /// Detect repeating patterns in recent action history.
    private func detectLoop() -> LoopPattern? {
        let recent = Array(history.suffix(windowSize))
        guard recent.count >= minCycleDetections * 2 else { return nil }

        // Check for cycles of length 1..windowSize/2
        for cycleLen in 1...(recent.count / minCycleDetections) {
            let matches = countCycleMatches(in: recent, cycleLength: cycleLen)
            if matches >= minCycleDetections {
                let confidence = Double(matches) / Double(recent.count / cycleLen)
                if confidence >= 0.6 {
                    return LoopPattern(
                        fingerprints: Array(recent.suffix(cycleLen * matches)),
                        cycleLength: cycleLen,
                        confidence: min(1.0, confidence),
                        detectedAt: Date()
                    )
                }
            }
        }

        // Check for error-only loops (repeated failures regardless of tool)
        let recentErrors = recent.filter(\.wasError)
        if recentErrors.count >= minCycleDetections && Double(recentErrors.count) / Double(recent.count) > 0.7 {
            return LoopPattern(
                fingerprints: recentErrors,
                cycleLength: 1,
                confidence: Double(recentErrors.count) / Double(recent.count),
                detectedAt: Date()
            )
        }

        return nil
    }

    /// Count how many times a cycle of `cycleLength` repeats in the sequence.
    private func countCycleMatches(in fingerprints: [ActionFingerprint], cycleLength: Int) -> Int {
        guard fingerprints.count >= cycleLength * 2 else { return 0 }

        // Use the last `cycleLength` fingerprints as the reference cycle
        let reference = Array(fingerprints.suffix(cycleLength))
        var matches = 1 // The reference itself counts as 1

        // Walk backward through the history checking for similar cycles
        var offset = fingerprints.count - cycleLength * 2
        while offset >= 0 {
            let candidate = Array(fingerprints[offset..<(offset + cycleLength)])
            let avgSimilarity = zip(reference, candidate).map { $0.similarity(to: $1) }.reduce(0, +) / Double(cycleLength)
            if avgSimilarity >= similarityThreshold {
                matches += 1
            } else {
                break // Stop at the first non-matching cycle
            }
            offset -= cycleLength
        }

        return matches
    }

    // MARK: - Strategy Selection

    /// Select the best pivot strategy based on the detected pattern and historical success rates.
    private func selectPivotStrategy(pattern: LoopPattern) -> PivotStrategy {
        // Escalation: if we've already pivoted, try increasingly aggressive strategies
        let strategies: [PivotStrategy]

        let allErrors = pattern.fingerprints.allSatisfy(\.wasError)
        let sameToolRepeated = Set(pattern.fingerprints.map(\.toolName)).count == 1

        if pivotCount == 0 {
            // First pivot — try gentle strategies
            if sameToolRepeated {
                strategies = [.useAlternativeTool, .readContext, .alternativeApproach]
            } else if allErrors {
                strategies = [.readContext, .decompose, .simplify]
            } else {
                strategies = [.alternativeApproach, .readContext, .decompose]
            }
        } else if pivotCount == 1 {
            // Second pivot — escalate
            strategies = [.decompose, .simplify, .alternativeApproach]
        } else {
            // Third+ pivot — ask the user
            strategies = [.askUser, .simplify, .decompose]
        }

        // Pick the strategy with the best historical success rate, or the first one
        return strategies.max(by: { strategyScore($0) < strategyScore($1) }) ?? strategies[0]
    }

    /// Score a strategy based on historical success rate (higher = better).
    private func strategyScore(_ strategy: PivotStrategy) -> Double {
        guard let stats = pivotSuccessRate[strategy], stats.total > 0 else {
            return 0.5 // Unknown strategy gets neutral score
        }
        return Double(stats.successes) / Double(stats.total)
    }

    // MARK: - Utilities

    private func stableHash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private func truncate(_ string: String, max: Int) -> String {
        if string.count <= max { return string }
        return String(string.prefix(max))
    }
}
