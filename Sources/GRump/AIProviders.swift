import Foundation

// MARK: - AI Provider System

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openRouter = "openrouter"
    case openAI = "openai"
    case anthropic = "anthropic"
    case google = "google"
    case ollama = "ollama"
    case onDevice = "ondevice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google AI"
        case .ollama: return "Ollama (Local)"
        case .onDevice: return "On-Device (Core ML)"
        }
    }

    var description: String {
        switch self {
        case .openRouter: return "Access multiple models through OpenRouter"
        case .openAI: return "Direct access to OpenAI models"
        case .anthropic: return "Direct access to Anthropic Claude models"
        case .google: return "Direct access to Google Gemini models"
        case .ollama: return "Run models locally on your machine"
        case .onDevice: return "Apple Silicon inference via Core ML \u{2014} zero network, zero telemetry"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openRouter, .openAI, .anthropic, .google: return true
        case .ollama, .onDevice: return false
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .ollama: return "http://localhost:11434/v1"
        case .onDevice: return "" // No network needed
        }
    }
}

// MARK: - Model Mode

struct ModelMode: Codable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let apiModelID: String?
    let overrideContextWindow: Int?
    let overrideMaxOutput: Int?

    init(id: String, displayName: String, apiModelID: String? = nil, overrideContextWindow: Int? = nil, overrideMaxOutput: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.apiModelID = apiModelID
        self.overrideContextWindow = overrideContextWindow
        self.overrideMaxOutput = overrideMaxOutput
    }
}

// MARK: - Enhanced AI Model

struct EnhancedAIModel: Identifiable, Codable, Equatable {
    let id: String
    let provider: AIProvider
    let modelID: String
    let displayName: String
    let description: String
    let contextWindow: Int
    let maxOutput: Int
    let requiresPaidTier: Bool
    let capabilities: ModelCapabilities
    let pricing: ModelPricing?
    let modes: [ModelMode]

    var rawValue: String { modelID }

    var hasModes: Bool { !modes.isEmpty }

    func effectiveModelID(mode: ModelMode?) -> String {
        guard let mode = mode, let override = mode.apiModelID else { return modelID }
        return override
    }

    func effectiveContextWindow(mode: ModelMode?) -> Int {
        mode?.overrideContextWindow ?? contextWindow
    }

    func effectiveMaxOutput(mode: ModelMode?) -> Int {
        mode?.overrideMaxOutput ?? maxOutput
    }

    init(id: String, provider: AIProvider, modelID: String, displayName: String, description: String,
         contextWindow: Int, maxOutput: Int, requiresPaidTier: Bool, capabilities: ModelCapabilities,
         pricing: ModelPricing?, modes: [ModelMode] = []) {
        self.id = id
        self.provider = provider
        self.modelID = modelID
        self.displayName = displayName
        self.description = description
        self.contextWindow = contextWindow
        self.maxOutput = maxOutput
        self.requiresPaidTier = requiresPaidTier
        self.capabilities = capabilities
        self.pricing = pricing
        self.modes = modes
    }

    static func == (lhs: EnhancedAIModel, rhs: EnhancedAIModel) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Model Capabilities

struct ModelCapabilities: Codable, Equatable {
    let supportsTools: Bool
    let supportsVision: Bool
    let supportsStreaming: Bool
    let supportsFunctionCalling: Bool
    let supportsJSONMode: Bool
    let maxTokens: Int?
    let supportsSystemMessages: Bool
    let supportsParallelToolUse: Bool
    
    static let `default` = ModelCapabilities(
        supportsTools: true,
        supportsVision: false,
        supportsStreaming: true,
        supportsFunctionCalling: true,
        supportsJSONMode: false,
        maxTokens: nil,
        supportsSystemMessages: true,
        supportsParallelToolUse: false
    )
}

// MARK: - Model Pricing

struct ModelPricing: Codable, Equatable {
    let inputPricePer1K: Double  // Price per 1K input tokens
    let outputPricePer1K: Double // Price per 1K output tokens
    let currency: String
    
    var formattedInputPrice: String {
        return String(format: "%.4f %@", inputPricePer1K, currency)
    }
    
    var formattedOutputPrice: String {
        return String(format: "%.4f %@", outputPricePer1K, currency)
    }
}

// MARK: - Provider Configuration

struct ProviderConfiguration: Codable {
    let provider: AIProvider
    var apiKey: String?
    var baseURL: String?
    var isEnabled: Bool = true
    var customHeaders: [String: String] = [:]
    
    init(provider: AIProvider, apiKey: String? = nil, baseURL: String? = nil) {
        self.provider = provider
        self.apiKey = apiKey
        self.baseURL = baseURL ?? provider.defaultBaseURL
    }
}

// MARK: - Model Registry

final class AIModelRegistry: @unchecked Sendable {
    static let shared = AIModelRegistry()
    
    private var models: [EnhancedAIModel] = []
    private var providerConfigs: [AIProvider: ProviderConfiguration] = [:]
    
    private init() {
        loadDefaultModels()
        loadProviderConfigurations()
    }
    
    // MARK: - Public Interface
    
    func getAllModels() -> [EnhancedAIModel] {
        return models.sorted { $0.displayName < $1.displayName }
    }
    
    func getModels(for provider: AIProvider) -> [EnhancedAIModel] {
        return models.filter { $0.provider == provider }
            .sorted { $0.displayName < $1.displayName }
    }
    
    func getModel(by id: String) -> EnhancedAIModel? {
        return models.first { $0.id == id }
    }
    
    func getProviderConfig(for provider: AIProvider) -> ProviderConfiguration? {
        return providerConfigs[provider]
    }
    
    func setProviderConfig(_ config: ProviderConfiguration) {
        providerConfigs[config.provider] = config
        saveProviderConfigurations()
    }
    
    func isProviderConfigured(_ provider: AIProvider) -> Bool {
        // On-device needs no config — it's always "configured" if Core ML is available
        if provider == .onDevice { return true }
        
        guard let config = providerConfigs[provider] else { return false }
        
        if !provider.requiresAPIKey { return true }
        return !(config.apiKey?.isEmpty ?? true)
    }
    
    // MARK: - Model Loading
    
    // MARK: - Shared Capabilities

    private static let fullCaps = ModelCapabilities(
        supportsTools: true, supportsVision: true, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    private static let basicCaps = ModelCapabilities(
        supportsTools: true, supportsVision: false, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: false
    )

    private func loadDefaultModels() {
        let full = Self.fullCaps
        let basic = Self.basicCaps

        models = [

            // ──────────────────────────────────────────────
            // MARK: Anthropic (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "anthropic-claude-opus-4.6",
                provider: .anthropic,
                modelID: "claude-opus-4-6-20250827",
                displayName: "Claude Opus 4.6",
                description: "Flagship frontier — complex coding, agents, extended thinking",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.015, outputPricePer1K: 0.075, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "claude-opus-4-6-fast-20250827"),
                    ModelMode(id: "1m", displayName: "1M Context", overrideContextWindow: 1_000_000),
                ]
            ),

            EnhancedAIModel(
                id: "anthropic-claude-sonnet-4.6",
                provider: .anthropic,
                modelID: "claude-sonnet-4-6-20250827",
                displayName: "Claude Sonnet 4.6",
                description: "Frontier Sonnet — coding, agents, professional work",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "claude-sonnet-4-6-fast-20250827"),
                ]
            ),

            EnhancedAIModel(
                id: "anthropic-claude-sonnet-4",
                provider: .anthropic,
                modelID: "claude-sonnet-4-20250514",
                displayName: "Claude Sonnet 4",
                description: "Balanced coding and reasoning, excellent tool use",
                contextWindow: 200_000,
                maxOutput: 16_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
            ),

            EnhancedAIModel(
                id: "anthropic-claude-3-5-haiku",
                provider: .anthropic,
                modelID: "claude-3-5-haiku-20241022",
                displayName: "Claude 3.5 Haiku",
                description: "Fast and compact, great for simple tasks and high throughput",
                contextWindow: 200_000,
                maxOutput: 8_192,
                requiresPaidTier: false,
                capabilities: ModelCapabilities(
                    supportsTools: true, supportsVision: true, supportsStreaming: true,
                    supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
                    supportsSystemMessages: true, supportsParallelToolUse: false
                ),
                pricing: ModelPricing(inputPricePer1K: 0.0008, outputPricePer1K: 0.004, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenAI (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openai-codex-5.3",
                provider: .openAI,
                modelID: "codex-5.3",
                displayName: "Codex 5.3",
                description: "OpenAI's latest coding model — agentic, multi-file, deep reasoning",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.02, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "reasoning", displayName: "Reasoning", apiModelID: "codex-5.3-reasoning"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "codex-5.3-fast"),
                ]
            ),

            EnhancedAIModel(
                id: "openai-gpt-4o",
                provider: .openAI,
                modelID: "gpt-4o",
                displayName: "GPT-4o",
                description: "Multimodal flagship with vision and audio",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.0025, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-gpt-4o-mini",
                provider: .openAI,
                modelID: "gpt-4o-mini",
                displayName: "GPT-4o Mini",
                description: "Fast multimodal model for most tasks",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o3",
                provider: .openAI,
                modelID: "o3",
                displayName: "o3",
                description: "Advanced reasoning model for complex problems",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.01, outputPricePer1K: 0.04, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o3-mini",
                provider: .openAI,
                modelID: "o3-mini",
                displayName: "o3 Mini",
                description: "Fast reasoning model, cost-efficient",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00115, outputPricePer1K: 0.0044, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openai-o4-mini",
                provider: .openAI,
                modelID: "o4-mini",
                displayName: "o4 Mini",
                description: "Latest reasoning model with tool use and vision",
                contextWindow: 200_000,
                maxOutput: 100_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00115, outputPricePer1K: 0.0044, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: Google Gemini (Direct API)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "google-gemini-3.1-pro",
                provider: .google,
                modelID: "gemini-3.1-pro",
                displayName: "Gemini 3.1 Pro",
                description: "Flagship reasoning, complex coding, 1M context window",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00125, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "google-gemini-3.1-flash",
                provider: .google,
                modelID: "gemini-3.1-flash",
                displayName: "Gemini 3.1 Flash",
                description: "Speed king — fast iteration, great for drafting and exploration",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenRouter (Multi-Provider)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openrouter-claude-opus-4.6",
                provider: .openRouter,
                modelID: "anthropic/claude-opus-4.6",
                displayName: "Claude Opus 4.6",
                description: "Flagship frontier model via OpenRouter — complex coding, agents, long context",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.015, outputPricePer1K: 0.075, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "anthropic/claude-opus-4.6:fast"),
                    ModelMode(id: "1m", displayName: "1M Context", overrideContextWindow: 1_000_000),
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-claude-sonnet-4.6",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-4.6",
                displayName: "Claude Sonnet 4.6",
                description: "Frontier Sonnet via OpenRouter — coding, agents, professional work",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "thinking", displayName: "Thinking"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "anthropic/claude-sonnet-4.6:fast"),
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-claude-sonnet-4",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-4",
                displayName: "Claude Sonnet 4",
                description: "Balanced coding and reasoning via OpenRouter",
                contextWindow: 200_000,
                maxOutput: 16_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-gemini-3.1-pro",
                provider: .openRouter,
                modelID: "google/gemini-3.1-pro",
                displayName: "Gemini 3.1 Pro",
                description: "Flagship reasoning via OpenRouter, 1M context",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00125, outputPricePer1K: 0.01, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-gemini-3.1-flash",
                provider: .openRouter,
                modelID: "google/gemini-3.1-flash",
                displayName: "Gemini 3.1 Flash",
                description: "Speed king via OpenRouter — fast iteration",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.00015, outputPricePer1K: 0.0006, currency: "USD")
            ),

            EnhancedAIModel(
                id: "openrouter-codex-5.3",
                provider: .openRouter,
                modelID: "openai/codex-5.3",
                displayName: "Codex 5.3",
                description: "OpenAI's latest coding model via OpenRouter",
                contextWindow: 200_000,
                maxOutput: 65_536,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.02, currency: "USD"),
                modes: [
                    ModelMode(id: "standard", displayName: "Standard"),
                    ModelMode(id: "reasoning", displayName: "Reasoning", apiModelID: "openai/codex-5.3-reasoning"),
                    ModelMode(id: "fast", displayName: "Fast", apiModelID: "openai/codex-5.3-fast"),
                ]
            ),

            EnhancedAIModel(
                id: "openrouter-kimi-k2.5",
                provider: .openRouter,
                modelID: "moonshotai/kimi-k2.5",
                displayName: "Kimi K2.5",
                description: "Strong reasoning and visual coding, top tool use",
                contextWindow: 200_000,
                maxOutput: 16_384,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.002, outputPricePer1K: 0.008, currency: "USD")
            ),

            // ──────────────────────────────────────────────
            // MARK: OpenRouter — Free Models
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "openrouter-deepseek-chat",
                provider: .openRouter,
                modelID: "deepseek/deepseek-chat-v3-0324:free",
                displayName: "DeepSeek V3",
                description: "Strong coder, free DeepSeek V3",
                contextWindow: 164_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-qwen3-coder",
                provider: .openRouter,
                modelID: "qwen/qwen3-coder:free",
                displayName: "Qwen3 Coder 480B",
                description: "Best free coding model, 480B MoE, agentic tool use",
                contextWindow: 262_144,
                maxOutput: 32_768,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-deepseek-r1",
                provider: .openRouter,
                modelID: "deepseek/deepseek-r1-0528:free",
                displayName: "DeepSeek R1",
                description: "Open-source reasoning on par with o1, 164K context",
                contextWindow: 164_000,
                maxOutput: 32_768,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-gpt-oss-120b",
                provider: .openRouter,
                modelID: "openai/gpt-oss-120b:free",
                displayName: "GPT-OSS 120B",
                description: "OpenAI open-weight MoE, native tool use & reasoning",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-trinity-large",
                provider: .openRouter,
                modelID: "arcee-ai/trinity-large-preview:free",
                displayName: "Trinity Large 400B",
                description: "400B MoE, trained for agentic coding (Cline/OpenCode)",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-step-3.5-flash",
                provider: .openRouter,
                modelID: "stepfun/step-3.5-flash:free",
                displayName: "Step 3.5 Flash",
                description: "196B MoE, blazing fast at 256K context",
                contextWindow: 256_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-llama-3.3-70b",
                provider: .openRouter,
                modelID: "meta-llama/llama-3.3-70b-instruct:free",
                displayName: "Llama 3.3 70B",
                description: "Meta's best open-weight 70B, multilingual coding",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            EnhancedAIModel(
                id: "openrouter-glm-4.5-air",
                provider: .openRouter,
                modelID: "z-ai/glm-4.5-air:free",
                displayName: "GLM 4.5 Air",
                description: "Agent-first model with thinking mode, tool use",
                contextWindow: 128_000,
                maxOutput: 16_384,
                requiresPaidTier: false,
                capabilities: basic,
                pricing: nil
            ),

            // ──────────────────────────────────────────────
            // MARK: On-Device (Apple Silicon)
            // ──────────────────────────────────────────────

            EnhancedAIModel(
                id: "ondevice-apple-foundation",
                provider: .onDevice,
                modelID: "apple-foundation-model",
                displayName: "Apple Foundation Model",
                description: "On-device Apple Intelligence — zero cost, zero latency, full privacy",
                contextWindow: 32_000,
                maxOutput: 4_096,
                requiresPaidTier: false,
                capabilities: ModelCapabilities(
                    supportsTools: true, supportsVision: false, supportsStreaming: true,
                    supportsFunctionCalling: true, supportsJSONMode: false, maxTokens: nil,
                    supportsSystemMessages: true, supportsParallelToolUse: false
                ),
                pricing: nil
            ),

            EnhancedAIModel(
                id: "ondevice-coreml",
                provider: .onDevice,
                modelID: "coreml-local",
                displayName: "Core ML Local",
                description: "Custom Core ML model — bring your own GGUF or MLX model",
                contextWindow: 8_192,
                maxOutput: 2_048,
                requiresPaidTier: false,
                capabilities: ModelCapabilities.default,
                pricing: nil
            ),
        ]
    }
    
    // MARK: - Configuration Management
    
    private func loadProviderConfigurations() {
        if let data = UserDefaults.standard.data(forKey: "AIProviderConfigurations"),
           let configs = try? JSONDecoder().decode([ProviderConfiguration].self, from: data) {
            for config in configs {
                providerConfigs[config.provider] = config
            }
        }
        
        // Set up default configurations for unconfigured providers
        for provider in AIProvider.allCases {
            if providerConfigs[provider] == nil {
                providerConfigs[provider] = ProviderConfiguration(provider: provider)
            }
        }
    }
    
    private func saveProviderConfigurations() {
        let configs = Array(providerConfigs.values)
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: "AIProviderConfigurations")
        }
    }
    
    // MARK: - Dynamic Model Loading
    
    @discardableResult
    func refreshOllamaModels() async -> Bool {
        guard let config = providerConfigs[.ollama],
              config.isEnabled else { return false }
        
        do {
            let fetchedModels = try await fetchOllamaModels(baseURL: config.baseURL ?? AIProvider.ollama.defaultBaseURL)
            await MainActor.run {
                // Remove existing Ollama models
                self.models.removeAll(where: { $0.provider == .ollama })

                // Add fetched models
                for model in fetchedModels {
                    let enhancedModel = EnhancedAIModel(
                        id: "ollama-\(model.name)",
                        provider: .ollama,
                        modelID: model.name,
                        displayName: model.name.capitalized,
                        description: "Local Ollama model: \(model.name)",
                        contextWindow: 4096,
                        maxOutput: 2048,
                        requiresPaidTier: false,
                        capabilities: ModelCapabilities.default,
                        pricing: nil
                    )
                    self.models.append(enhancedModel)
                }
            }
            return true
        } catch {
            GRumpLogger.ai.error("Failed to fetch Ollama models: \(error.localizedDescription)")
            return false
        }
    }

    func isOllamaRunning() async -> Bool {
        guard let config = providerConfigs[.ollama], config.isEnabled else { return false }
        do {
            _ = try await fetchOllamaModels(baseURL: config.baseURL ?? AIProvider.ollama.defaultBaseURL)
            return true
        } catch {
            return false
        }
    }

    func pullOllamaModel(_ modelName: String) async throws {
        guard let config = providerConfigs[.ollama], config.isEnabled else {
            throw URLError(.userAuthenticationRequired)
        }

        let baseURL = config.baseURL ?? AIProvider.ollama.defaultBaseURL
        let urls = ollamaPullEndpoints(baseURL: baseURL)
        guard !urls.isEmpty else { throw URLError(.badURL) }

        let payload: [String: Any] = [
            "name": modelName,
            "stream": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        var lastError: Error = URLError(.cannotConnectToHost)
        for endpoint in urls {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    lastError = URLError(.badServerResponse)
                    continue
                }
                _ = await refreshOllamaModels()
                return
            } catch {
                lastError = error
            }
        }

        throw lastError
    }
    
    private func fetchOllamaModels(baseURL: String) async throws -> [OllamaModel] {
        let endpoints = ollamaTagEndpoints(baseURL: baseURL)
        guard !endpoints.isEmpty else { throw URLError(.badURL) }

        var lastError: Error = URLError(.cannotConnectToHost)
        for endpoint in endpoints {
            do {
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = 3
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    lastError = URLError(.badServerResponse)
                    continue
                }

                let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
                return decoded.models
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func ollamaTagEndpoints(baseURL: String) -> [URL] {
        var urls: [URL] = []

        if let v1 = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/tags") {
            urls.append(v1)
        }
        if let root = ollamaRootURL(from: baseURL) {
            urls.append(root.appendingPathComponent("api/tags"))
        }

        return deduplicatedURLs(urls)
    }

    private func ollamaPullEndpoints(baseURL: String) -> [URL] {
        var urls: [URL] = []

        if let v1 = URL(string: "\(baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/pull") {
            urls.append(v1)
        }
        if let root = ollamaRootURL(from: baseURL) {
            urls.append(root.appendingPathComponent("api/pull"))
        }

        return deduplicatedURLs(urls)
    }

    private func ollamaRootURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        if components.path.hasSuffix("/v1") {
            components.path = String(components.path.dropLast(3))
        }
        if components.path == "/" { components.path = "" }
        if components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    private func deduplicatedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var deduped: [URL] = []
        for url in urls {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                deduped.append(url)
            }
        }
        return deduped
    }
}

// MARK: - Ollama Models

struct OllamaModel: Codable {
    let name: String
    let model: String
    let modified_at: String
    let size: Int64?
    let digest: String
    let details: OllamaModelDetails?
}

struct OllamaModelDetails: Codable {
    let format: String
    let family: String
    let families: [String]?
    let parameter_size: String?
    let quantization_level: String?
}

struct OllamaResponse: Codable {
    let models: [OllamaModel]
}
