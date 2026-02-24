import Foundation
#if canImport(CoreML)
import CoreML
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - Core ML On-Device Inference Service
//
// Runs language models entirely on-device using Apple's Core ML framework.
// Zero network. Zero telemetry. Pure Apple Silicon inference.
//
// Supports:
// - Pre-converted .mlmodelc bundles (drag into project or ~/Library/Application Support/GRump/Models/)
// - Automatic Neural Engine / GPU / CPU scheduling via MLComputeUnits
// - Token-by-token streaming via AsyncStream
// - Model hot-swapping without recompilation

// MARK: - Errors

enum CoreMLError: Error, LocalizedError {
    case coreMLUnavailable
    case noModelLoaded
    case modelLoadFailed(String)
    case inferenceError(String)
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .coreMLUnavailable:
            return "Core ML is not available on this platform."
        case .noModelLoaded:
            return "No on-device model is loaded. Add a .mlmodelc bundle to the Models directory."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .inferenceError(let reason):
            return "Inference error: \(reason)"
        case .serviceUnavailable:
            return "Core ML service is no longer available."
        }
    }
}

// MARK: - Model Metadata (parsed from manifest.json alongside .mlmodelc)

struct CoreMLModelMetadata {
    let displayName: String?
    let quantization: String?
    let parameterCount: String?
    let contextLength: Int?
}

// MARK: - Constants

/// End-of-sequence markers used by common chat model formats
private let eosMarkers: [String] = {
    let pipe = "|"
    return [
        "<\(pipe)end\(pipe)>",
        "<\(pipe)endoftext\(pipe)>",
        "<\(pipe)eot_id\(pipe)>",
        "</s>",
        "[END]"
    ]
}()

// MARK: - Service

@MainActor
final class CoreMLInferenceService: ObservableObject {

    // MARK: - Published State

    @Published private(set) var availableModels: [CoreMLModelInfo] = []
    @Published private(set) var loadedModelID: String?
    @Published private(set) var isModelLoaded: Bool = false
    @Published private(set) var loadingProgress: Double = 0.0
    @Published private(set) var inferenceStatus: InferenceStatus = .idle

    enum InferenceStatus: Sendable {
        case idle
        case loading
        case generating(tokensPerSecond: Double)
        case error(String)
    }

    // MARK: - Model Info

    struct CoreMLModelInfo: Identifiable, Sendable {
        let id: String
        let name: String
        let path: URL
        let sizeBytes: Int64
        let quantization: String
        let parameterCount: String
        let contextLength: Int
        let supportsStreaming: Bool

        var sizeFormatted: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }
    }

    // MARK: - Private State

    #if canImport(CoreML)
    private var loadedModel: MLModel?
    #endif

    private var modelDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("GRump/Models", isDirectory: true)
    }

    // Removed eosMarkers here

    // MARK: - Initialization

    init() {
        ensureModelDirectoryExists()
        refreshAvailableModels()
    }

    // MARK: - Model Discovery

    func refreshAvailableModels() {
        var discovered: [CoreMLModelInfo] = []
        let fm = FileManager.default
        ensureModelDirectoryExists()

        guard let contents = try? fm.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            availableModels = []
            return
        }

        for url in contents {
            let ext = url.pathExtension.lowercased()
            guard ext == "mlmodelc" || ext == "mlpackage" else { continue }

            let name = url.deletingPathExtension().lastPathComponent
            let size = directorySize(url)
            let metadata = loadModelMetadata(from: url)

            discovered.append(CoreMLModelInfo(
                id: "coreml-\(name.lowercased())",
                name: metadata?.displayName ?? name,
                path: url,
                sizeBytes: size,
                quantization: metadata?.quantization ?? "Unknown",
                parameterCount: metadata?.parameterCount ?? "Unknown",
                contextLength: metadata?.contextLength ?? 2048,
                supportsStreaming: true
            ))
        }

        availableModels = discovered.sorted { $0.name < $1.name }
    }

    // MARK: - Model Loading

    /// Load a Core ML model for inference. Uses Neural Engine when available.
    func loadModel(_ modelInfo: CoreMLModelInfo) async throws {
        inferenceStatus = .loading
        loadingProgress = 0.0

        #if canImport(CoreML)
        let config = MLModelConfiguration()
        // Prefer Neural Engine -> GPU -> CPU fallback chain (Apple Silicon optimized)
        config.computeUnits = .all

        do {
            loadingProgress = 0.3
            let model = try await MLModel.load(
                contentsOf: modelInfo.path,
                configuration: config
            )
            loadingProgress = 1.0
            self.loadedModel = model
            self.loadedModelID = modelInfo.id
            self.isModelLoaded = true
            self.inferenceStatus = .idle
        } catch {
            self.inferenceStatus = .error("Failed to load model: \(error.localizedDescription)")
            throw CoreMLError.modelLoadFailed(error.localizedDescription)
        }
        #else
        throw CoreMLError.coreMLUnavailable
        #endif
    }

    /// Unload the current model to free memory.
    func unloadModel() {
        #if canImport(CoreML)
        loadedModel = nil
        #endif
        loadedModelID = nil
        isModelLoaded = false
        inferenceStatus = .idle
    }

    // MARK: - Streaming Inference

    /// Run inference on the loaded model, streaming tokens as they are generated.
    func streamInference(
        prompt: String,
        maxTokens: Int = 2048,
        temperature: Double = 0.7
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CoreMLError.serviceUnavailable)
                    return
                }

                #if canImport(CoreML)
                guard let model = self.loadedModel else {
                    continuation.finish(throwing: CoreMLError.noModelLoaded)
                    return
                }

                let startTime = Date()
                var tokenCount = 0
                var currentInput = prompt
                var generatedText = ""

                for _ in 0..<maxTokens {
                    if Task.isCancelled { break }

                    guard let prediction = try? self.predictNextToken(
                        model: model,
                        input: currentInput,
                        temperature: temperature
                    ) else {
                        break
                    }

                    if prediction.isEndOfSequence { break }

                    tokenCount += 1
                    generatedText += prediction.token
                    currentInput = prompt + generatedText

                    // Update tokens/sec metric on main actor
                    let elapsed = Date().timeIntervalSince(startTime)
                    let tps = elapsed > 0 ? Double(tokenCount) / elapsed : 0
                    await MainActor.run {
                        self.inferenceStatus = .generating(tokensPerSecond: tps)
                    }

                    continuation.yield(prediction.token)
                }

                await MainActor.run {
                    self.inferenceStatus = .idle
                }
                continuation.finish()
                #else
                continuation.finish(throwing: CoreMLError.coreMLUnavailable)
                #endif
            }
        }
    }

    /// Convert Core ML inference into the standard StreamEvent format used by MultiProviderAIService.
    func streamMessage(
        messages: [Message],
        maxTokens: Int = 2048
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let prompt = buildChatPrompt(from: messages)

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CoreMLError.serviceUnavailable)
                    return
                }

                let tokenStream = self.streamInference(prompt: prompt, maxTokens: maxTokens)

                do {
                    for try await token in tokenStream {
                        continuation.yield(.text(token))
                    }
                    continuation.yield(.done("stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Returns an EnhancedAIModel representation for each discovered on-device model,
    /// so they can appear in the unified model picker alongside cloud providers.
    func enhancedModels() -> [EnhancedAIModel] {
        return availableModels.map { info in
            EnhancedAIModel(
                id: info.id,
                provider: .onDevice,
                modelID: info.id,
                displayName: "\(info.name) (On-Device)",
                description: "\(info.parameterCount) \(info.quantization) — runs locally on Apple Silicon",
                contextWindow: info.contextLength,
                maxOutput: 2048,
                requiresPaidTier: false,
                capabilities: ModelCapabilities(
                    supportsTools: false,
                    supportsVision: false,
                    supportsStreaming: true,
                    supportsFunctionCalling: false,
                    supportsJSONMode: false,
                    maxTokens: info.contextLength,
                    supportsSystemMessages: true,
                    supportsParallelToolUse: false
                ),
                pricing: nil
            )
        }
    }

    // MARK: - Prompt Building

    private func buildChatPrompt(from messages: [Message]) -> String {
        let pipe = "|"
        let formatted = messages.map { msg -> String in
            let tag: String
            switch msg.role {
            case .system:    tag = "system"
            case .user:      tag = "user"
            case .assistant: tag = "assistant"
            case .tool:      tag = "tool"
            }
            return "<\(pipe)\(tag)\(pipe)>\n\(msg.content)<\(pipe)end\(pipe)>"
        }
        return formatted.joined(separator: "\n") + "\n<\(pipe)assistant\(pipe)>\n"
    }

    // MARK: - Token Prediction

    private struct TokenPrediction {
        let token: String
        let isEndOfSequence: Bool
    }

    #if canImport(CoreML)
    private nonisolated func predictNextToken(
        model: MLModel,
        input: String,
        temperature: Double
    ) throws -> TokenPrediction? {
        // Core ML model input/output varies by model architecture.
        // This provides a generic interface that works with models exported
        // via coremltools with standard "text" input and "output" features.
        let provider = try MLDictionaryFeatureProvider(
            dictionary: ["text": input as NSString]
        )
        let result = try model.prediction(from: provider)

        guard let outputValue = result.featureValue(for: "output") else {
            return nil
        }
        let outputString = outputValue.stringValue

        let isEOS = outputString.isEmpty ||
                    eosMarkers.contains(where: { outputString.contains($0) })

        let cleanToken = isEOS ? "" : outputString
        return TokenPrediction(token: cleanToken, isEndOfSequence: isEOS)
    }
    #endif

    // MARK: - File System Helpers

    private func ensureModelDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: modelDirectory.path) {
            try? fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        }
    }

    private nonisolated func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Load optional manifest.json from the same directory as the model bundle.
    /// Expected format: { "displayName": "...", "quantization": "Q4_K_M", "parameterCount": "3B", "contextLength": 4096 }
    private nonisolated func loadModelMetadata(from modelURL: URL) -> CoreMLModelMetadata? {
        let manifestURL = modelURL.deletingLastPathComponent()
            .appendingPathComponent(
                modelURL.deletingPathExtension().lastPathComponent + ".manifest.json"
            )
        guard let data = try? Data(contentsOf: manifestURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return CoreMLModelMetadata(
            displayName: dict["displayName"] as? String,
            quantization: dict["quantization"] as? String,
            parameterCount: dict["parameterCount"] as? String,
            contextLength: dict["contextLength"] as? Int
        )
    }
}
