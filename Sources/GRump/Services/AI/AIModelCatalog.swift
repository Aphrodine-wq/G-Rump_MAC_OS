import Foundation

// MARK: - Default Model Catalog
//
// Current-generation models for the four first-class providers. Anthropic is
// the flagship provider (Claude Opus 5 is the app default); OpenRouter
// carries passthrough routes, including the legacy Qwen lane. `id` ==
// `modelID` == the exact wire id. This file is deliberately a single data
// table — when a vendor ships new models, edit here only.
//
// Pricing is USD per 1K tokens (Anthropic + OpenAI verified 2026-08 against
// vendor docs; Google/OpenRouter render "—" until verified).

extension AIModelRegistry {

    // MARK: - Shared Capabilities

    static let fullCaps = ModelCapabilities(
        supportsTools: true, supportsVision: true, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    static let textCaps = ModelCapabilities(
        supportsTools: true, supportsVision: false, supportsStreaming: true,
        supportsFunctionCalling: true, supportsJSONMode: true, maxTokens: nil,
        supportsSystemMessages: true, supportsParallelToolUse: true
    )

    // MARK: - Catalog

    func defaultModelCatalog() -> [EnhancedAIModel] {
        let full = Self.fullCaps
        let text = Self.textCaps

        return [
            // MARK: Anthropic
            EnhancedAIModel(
                id: "claude-opus-5",
                provider: .anthropic,
                modelID: "claude-opus-5",
                displayName: "Claude Opus 5",
                description: "Default — long-horizon agentic coding and the strongest all-rounder",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.005, outputPricePer1K: 0.025, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-fable-5",
                provider: .anthropic,
                modelID: "claude-fable-5",
                displayName: "Claude Fable 5",
                description: "Anthropic's most capable model — premium, pick it deliberately",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: true,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.010, outputPricePer1K: 0.050, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-sonnet-5",
                provider: .anthropic,
                modelID: "claude-sonnet-5",
                displayName: "Claude Sonnet 5",
                description: "Near-Opus coding quality at a fraction of the price",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.002, outputPricePer1K: 0.010, currency: "USD")
            ),
            EnhancedAIModel(
                id: "claude-haiku-4-5",
                provider: .anthropic,
                modelID: "claude-haiku-4-5",
                displayName: "Claude Haiku 4.5",
                description: "Fastest and cheapest — drafting, lookups, light edits",
                contextWindow: 200_000,
                maxOutput: 64_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.001, outputPricePer1K: 0.005, currency: "USD")
            ),

            // MARK: OpenAI
            EnhancedAIModel(
                id: "gpt-5.6-sol",
                provider: .openAI,
                modelID: "gpt-5.6-sol",
                displayName: "GPT-5.6 Sol",
                description: "OpenAI's flagship — complex professional and agentic work",
                contextWindow: 1_050_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.004, outputPricePer1K: 0.020, currency: "USD")
            ),
            EnhancedAIModel(
                id: "gpt-5.6-terra",
                provider: .openAI,
                modelID: "gpt-5.6-terra",
                displayName: "GPT-5.6 Terra",
                description: "Balanced intelligence and cost",
                contextWindow: 1_050_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: ModelPricing(inputPricePer1K: 0.002, outputPricePer1K: 0.012, currency: "USD")
            ),

            // MARK: Google
            EnhancedAIModel(
                id: "gemini-3.1-pro-preview",
                provider: .google,
                modelID: "gemini-3.1-pro-preview",
                displayName: "Gemini 3.1 Pro",
                description: "Google's flagship — strong multimodal reasoning",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "gemini-3.7-flash",
                provider: .google,
                modelID: "gemini-3.7-flash",
                displayName: "Gemini 3.7 Flash",
                description: "Fast Gemini for agentic workflows and high-volume work",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),

            // MARK: OpenRouter (passthrough routes)
            EnhancedAIModel(
                id: "anthropic/claude-sonnet-5",
                provider: .openRouter,
                modelID: "anthropic/claude-sonnet-5",
                displayName: "Claude Sonnet 5 (OpenRouter)",
                description: "Sonnet 5 routed through OpenRouter",
                contextWindow: 1_000_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "openai/gpt-5.6-sol",
                provider: .openRouter,
                modelID: "openai/gpt-5.6-sol",
                displayName: "GPT-5.6 Sol (OpenRouter)",
                description: "GPT-5.6 Sol routed through OpenRouter",
                contextWindow: 1_050_000,
                maxOutput: 128_000,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "google/gemini-3.1-pro-preview",
                provider: .openRouter,
                modelID: "google/gemini-3.1-pro-preview",
                displayName: "Gemini 3.1 Pro (OpenRouter)",
                description: "Gemini 3.1 Pro routed through OpenRouter",
                contextWindow: 1_000_000,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: full,
                pricing: nil
            ),
            EnhancedAIModel(
                id: "qwen/qwen3-coder",
                provider: .openRouter,
                modelID: "qwen/qwen3-coder",
                displayName: "Qwen3 Coder (OpenRouter)",
                description: "The legacy Qwen coding lane, via OpenRouter",
                contextWindow: 262_144,
                maxOutput: 65_536,
                requiresPaidTier: false,
                capabilities: text,
                pricing: nil
            )
        ]
    }
}
