import Foundation
import Combine

// MARK: - Multi-Provider AI Service

@MainActor
class MultiProviderAIService: ObservableObject {
    static let shared = MultiProviderAIService()
    @Published var currentProvider: AIProvider = .anthropic
    @Published var currentModel: EnhancedAIModel?
    @Published var availableModels: [EnhancedAIModel] = []
    @Published var isConfigured: Bool = false
    
    let modelRegistry = AIModelRegistry.shared
    private var coreMLService: CoreMLInferenceService?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.coreMLService = CoreMLInferenceService()
        loadConfiguration()
        refreshModels()
        
        // Auto-refresh local models when provider changes
        $currentProvider
            .sink { [weak self] provider in
                switch provider {
                case .ollama:
                    Task {
                        await self?.modelRegistry.refreshOllamaModels()
                        await MainActor.run {
                            self?.refreshModels()
                        }
                    }
                case .onDevice:
                    Task { @MainActor in
                        self?.coreMLService?.refreshAvailableModels()
                        self?.refreshModels()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Configuration
    
    private func loadConfiguration() {
        if let providerString = UserDefaults.standard.string(forKey: "CurrentAIProvider"),
           let provider = AIProvider(rawValue: providerString) {
            currentProvider = provider
        }
        
        if let modelID = UserDefaults.standard.string(forKey: "CurrentAIModel") {
            currentModel = modelRegistry.getModel(by: modelID)
        }
        
        updateConfigurationStatus()
    }
    
    private func saveConfiguration() {
        UserDefaults.standard.set(currentProvider.rawValue, forKey: "CurrentAIProvider")
        UserDefaults.standard.set(currentModel?.id, forKey: "CurrentAIModel")
    }
    
    private func updateConfigurationStatus() {
        isConfigured = modelRegistry.isProviderConfigured(currentProvider)
    }
    
    // MARK: - Model Management
    
    func refreshModels() {
        if currentProvider == .onDevice {
            // On-device models come from CoreMLInferenceService, not the registry
            availableModels = coreMLService?.enhancedModels() ?? []
        } else {
            availableModels = modelRegistry.getModels(for: currentProvider)
        }
        
        // If current model is not in the available models, select the first one
        if let currentModel = currentModel,
           !availableModels.contains(where: { $0.id == currentModel.id }) {
            self.currentModel = availableModels.first
        } else if currentModel == nil {
            currentModel = availableModels.first
        }
        
        updateConfigurationStatus()
    }
    
    func selectProvider(_ provider: AIProvider) {
        currentProvider = provider
        refreshModels()
        saveConfiguration()
    }
    
    func selectModel(_ model: EnhancedAIModel) {
        currentModel = model
        saveConfiguration()
    }
    
    func configureProvider(_ provider: AIProvider, apiKey: String?, baseURL: String?) {
        let config = ProviderConfiguration(
            provider: provider,
            apiKey: apiKey,
            baseURL: baseURL
        )
        modelRegistry.setProviderConfig(config)
        
        if provider == currentProvider {
            updateConfigurationStatus()
        }
    }
    
    // MARK: - Chat Completions
    
    func streamMessage(
        messages: [Message],
        tools: [[String: Any]]? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let model = currentModel else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.noModelSelected) }
        }
        
        // On-device inference does not need a provider config
        if model.provider == .onDevice {
            return streamOnDevice(messages: messages, model: model)
        }
        
        guard let config = modelRegistry.getProviderConfig(for: model.provider) else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.providerNotConfigured) }
        }
        
        switch model.provider {
        case .openRouter:
            return streamOpenRouter(messages: messages, model: model, config: config, tools: tools)
        case .openAI:
            return streamOpenAI(messages: messages, model: model, config: config, tools: tools)
        case .anthropic:
            return streamAnthropic(messages: messages, model: model, config: config, tools: tools)
        case .google:
            return streamGoogle(messages: messages, model: model, config: config, tools: tools)
        case .ollama:
            return streamOllama(messages: messages, model: model, config: config, tools: tools)
        case .onDevice:
            return streamOnDevice(messages: messages, model: model) // Already handled above
        }
    }
    
    // MARK: - Provider-Specific Streaming
    
    private func streamOpenRouter(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let openRouterService = OpenRouterService()
        return openRouterService.streamMessage(
            messages: messages,
            apiKey: config.apiKey ?? "",
            model: model.modelID,
            tools: tools
        )
    }
    
    nonisolated private func streamOpenAI(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
            Task {
                do {
                    let request = try buildOpenAIRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )
                    
                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }
                    
                    try await SSELineParser.parseOpenAICompatible(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    nonisolated private func streamAnthropic(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildAnthropicRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )
                    
                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }
                    
                    try await SSELineParser.parseAnthropic(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    nonisolated private func streamOllama(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildOllamaRequest(
                        messages: messages,
                        model: model.modelID,
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        stream: true
                    )
                    
                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }
                    
                    try await SSELineParser.parseOllamaNDJSON(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Google Gemini Streaming

    nonisolated private func streamGoogle(
        messages: [Message],
        model: EnhancedAIModel,
        config: ProviderConfiguration,
        tools: [[String: Any]]?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        return AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    let request = try buildGoogleRequest(
                        messages: messages,
                        model: model.modelID,
                        apiKey: config.apiKey ?? "",
                        baseURL: config.baseURL ?? model.provider.defaultBaseURL,
                        tools: tools,
                        maxOutputTokens: model.maxOutput
                    )

                    let (bytes, response) = try await StreamingNetwork.session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AIServiceError.networkError
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw AIServiceError.apiError(httpResponse.statusCode)
                    }

                    try await SSELineParser.parseGoogleSSE(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - On-Device (Core ML) Streaming

    private func streamOnDevice(
        messages: [Message],
        model: EnhancedAIModel
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        guard let service = coreMLService else {
            return AsyncThrowingStream { $0.finish(throwing: AIServiceError.providerNotConfigured) }
        }
        return service.streamMessage(messages: messages, maxTokens: model.maxOutput)
    }
    
    // MARK: - Request Builders
    
    nonisolated private func buildOpenAIRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = OpenAIRequest(
            model: model,
            messages: messages.map { openAIMessage(from: $0) },
            tools: tools,
            stream: stream,
            temperature: 0.7,
            maxTokens: nil
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
    
    nonisolated private func buildAnthropicRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("anthropic-dangerous-direct-browser-access", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = AnthropicRequest(
            model: model,
            messages: messages.map { anthropicMessage(from: $0) },
            tools: tools?.map { anthropicTool(from: $0) },
            maxTokens: 4096,
            stream: stream
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
    
    nonisolated private func buildOllamaRequest(
        messages: [Message],
        model: String,
        baseURL: String,
        tools: [[String: Any]]?,
        stream: Bool
    ) throws -> URLRequest {
        // Native Ollama API uses /api/chat, not /v1/chat
        // Strip /v1 suffix if present since we're using native API
        let cleanBaseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/v1", with: "")
        guard let url = URL(string: "\(cleanBaseURL)/api/chat") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = OllamaRequest(
            model: model,
            messages: messages.map { ollamaMessage(from: $0) },
            stream: stream,
            options: OllamaOptions(temperature: 0.7, numPredict: 2048)
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
    
    nonisolated private func buildGoogleRequest(
        messages: [Message],
        model: String,
        apiKey: String,
        baseURL: String,
        tools: [[String: Any]]?,
        maxOutputTokens: Int
    ) throws -> URLRequest {
        let cleanBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(cleanBase)/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert messages to Gemini contents format
        var contents: [[String: Any]] = []
        var systemInstruction: [String: Any]?

        for message in messages {
            if message.role == .system {
                systemInstruction = ["parts": [["text": message.content]]]
                continue
            }
            let role = message.role == .assistant ? "model" : "user"
            contents.append([
                "role": role,
                "parts": [["text": message.content]]
            ])
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxOutputTokens,
            ]
        ]
        if let sys = systemInstruction {
            body["systemInstruction"] = sys
        }

        // Convert tools to Gemini function declarations
        if let tools = tools, !tools.isEmpty {
            var functionDeclarations: [[String: Any]] = []
            for tool in tools {
                if let function = tool["function"] as? [String: Any] {
                    functionDeclarations.append(function)
                }
            }
            if !functionDeclarations.isEmpty {
                body["tools"] = [["functionDeclarations": functionDeclarations]]
            }
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Message Converters
    
    nonisolated private func openAIMessage(from message: Message) -> OpenAIMessage {
        return OpenAIMessage(
            role: message.role.rawValue,
            content: message.content,
            toolCalls: message.toolCalls?.map { toolCall in
                OpenAIMessage.ToolCall(
                    id: toolCall.id,
                    type: "function",
                    function: OpenAIMessage.ToolCall.FunctionCall(
                        name: toolCall.name,
                        arguments: toolCall.arguments
                    )
                )
            }
        )
    }
    
    nonisolated private func anthropicMessage(from message: Message) -> AnthropicMessage {
        if message.role == .tool {
            return AnthropicMessage(
                role: "user",
                content: [
                    AnthropicMessage.Content(
                        type: "tool_result",
                        text: nil,
                        toolUseId: message.toolCallId ?? "",
                        toolResult: message.content
                    )
                ]
            )
        } else {
            return AnthropicMessage(
                role: message.role.rawValue,
                content: [AnthropicMessage.Content(type: "text", text: message.content, toolUseId: nil, toolResult: nil)]
            )
        }
    }
    
    nonisolated private func ollamaMessage(from message: Message) -> OllamaMessage {
        return OllamaMessage(
            role: message.role == .tool ? "user" : message.role.rawValue,
            content: message.content
        )
    }
    
    nonisolated private func anthropicTool(from tool: [String: Any]) -> AnthropicTool {
        let fn = tool["function"] as? [String: Any] ?? [:]
        return AnthropicTool(
            name: fn["name"] as? String ?? "",
            description: fn["description"] as? String ?? "",
            inputSchema: fn["parameters"] as? [String: Any] ?? [:]
        )
    }
}

// MARK: - Error Types

enum AIServiceError: LocalizedError {
    case noModelSelected
    case providerNotConfigured
    case networkError
    case apiError(Int)
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .noModelSelected:
            return "No AI model selected"
        case .providerNotConfigured:
            return "AI provider not configured"
        case .networkError:
            return "Network error occurred"
        case .apiError(let code):
            return "API error: \(code)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}

// MARK: - Stream Event
// Uses the canonical StreamEvent enum defined in OpenRouterService.swift

// MARK: - Request/Response Models (simplified)

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [[String: Any]]?
    let stream: Bool
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream, temperature
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        if let tools = tools, let data = try? JSONSerialization.data(withJSONObject: tools),
           let jsonArray = try? JSONDecoder().decode([JSONValue].self, from: data) {
            try container.encode(jsonArray, forKey: .tools)
        }
    }
}

/// A generic JSON value for encoding arbitrary JSON structures.
private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if container.decodeNil() { self = .null }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
    let toolCalls: [ToolCall]?
    
    struct ToolCall: Codable {
        let id: String
        let type: String
        let function: FunctionCall
        
        struct FunctionCall: Codable {
            let name: String
            let arguments: String
        }
    }
}

private struct OpenAIStreamResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let delta: Delta
        let finishReason: String?

        struct Delta: Codable {
            let content: String?
            let toolCalls: [StreamToolCall]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
    }

    struct StreamToolCall: Codable {
        let id: String?
        let type: String?
        let function: StreamFunction?

        struct StreamFunction: Codable {
            let name: String?
            let arguments: String?
        }
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, stream
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Codable {
    let role: String
    let content: [Content]
    
    struct Content: Codable {
        let type: String
        let text: String?
        let toolUseId: String?
        let toolResult: String?
        
        enum CodingKeys: String, CodingKey {
            case type, text
            case toolUseId = "tool_use_id"
            case toolResult = "content"
        }
    }
}

private struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        if let data = try? JSONSerialization.data(withJSONObject: inputSchema),
           let jsonObj = try? JSONDecoder().decode([String: JSONValue].self, from: data) {
            try container.encode(jsonObj, forKey: .inputSchema)
        }
    }

    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema = "input_schema"
    }
}

private struct AnthropicStreamResponse: Codable {
    let type: String
    let delta: Delta?
    
    struct Delta: Codable {
        let text: String?
        let toolUse: [ToolUse]?
    }
    
    struct ToolUse: Codable {
        let id: String?
        let name: String?
        let input: ToolInput?
    }
    
    struct ToolInput: Codable {
        func jsonString() -> String {
            if let data = try? JSONEncoder().encode(self),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "{}"
        }
    }
}

private struct OllamaRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaMessage: Codable {
    let role: String
    let content: String
}

private struct OllamaOptions: Codable {
    let temperature: Double
    let numPredict: Int
    
    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct OllamaStreamResponse: Codable {
    let response: String
    let done: Bool
}

// MARK: - Extensions

extension Dictionary {
    func jsonString() -> String {
        if let data = try? JSONSerialization.data(withJSONObject: self),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}
