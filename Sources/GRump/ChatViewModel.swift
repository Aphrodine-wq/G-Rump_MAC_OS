import Foundation
import Combine
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import ApplicationServices
import ScreenCaptureKit
#else
import UIKit
#endif
import UserNotifications

#if os(macOS)
enum SystemRunApprovalResponse {
    case allowOnce
    case allowAlways
    case deny
}
#endif

// MARK: - Agent Mode (Chat, Plan, Build, Debate, Spec)

enum AgentMode: String, CaseIterable, Identifiable, Codable {
    case standard
    case plan
    case fullStack
    case argue
    case spec
    case parallel
    case speculative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Chat"
        case .plan: return "Plan"
        case .fullStack: return "Build"
        case .argue: return "Debate"
        case .spec: return "Spec"
        case .parallel: return "Parallel"
        case .speculative: return "Explore"
        }
    }

    var icon: String {
        switch self {
        case .standard: return "text.bubble"
        case .plan: return "list.bullet.clipboard"
        case .fullStack: return "hammer.fill"
        case .argue: return "bubble.left.and.bubble.right"
        case .spec: return "doc.text.magnifyingglass"
        case .parallel: return "arrow.triangle.branch"
        case .speculative: return "point.3.connected.trianglepath.dotted"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Direct chat with full tool access and autonomous execution."
        case .plan: return "Creates a detailed plan before writing any code."
        case .fullStack: return "Builds complete features end-to-end across the full stack."
        case .argue: return "Debates both sides before recommending an approach."
        case .spec: return "Asks clarifying questions to refine requirements before acting."
        case .parallel: return "Runs multiple sub-agents in parallel for complex tasks."
        case .speculative: return "Explores 2-3 competing approaches in parallel and picks the winner."
        }
    }
    
    /// Per-mode accent color for minimal visual differentiation.
    var modeAccentColor: Color {
        switch self {
        case .standard:    return .purple
        case .plan:        return .blue
        case .fullStack:   return .green
        case .argue:       return .orange
        case .spec:        return .teal
        case .parallel:    return .indigo
        case .speculative: return .yellow
        }
    }

    var toastMessage: String {
        switch self {
        case .standard: return "Switched to Chat mode"
        case .plan: return "Switched to Plan mode"
        case .fullStack: return "Switched to Build mode"
        case .argue: return "Switched to Debate mode"
        case .spec: return "Switched to Spec mode"
        case .parallel: return "Switched to Parallel mode"
        case .speculative: return "Switched to Explore mode"
        }
    }
}

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var streamingContent: String = ""
    @Published var importExportMessage: String?
    @Published var activeToolCalls: [ToolCallStatus] = []
    @Published var workingDirectory: String = "" {
        didSet { activityStore.setPersistencePath(workingDirectory.isEmpty ? nil : "\(workingDirectory)/.grump/activity.json") }
    }
    /// When non-nil, the agent is in a multi-step run; UI can show "Step currentAgentStep of currentAgentStepMax".
    @Published var currentAgentStep: Int? = nil
    @Published var currentAgentStepMax: Int? = nil
    /// When true, the agent was paused (not stopped). User can resume.
    @Published var isPaused: Bool = false

    // MARK: - LSP Bridge (set by ContentView)
    var lspDiagnostics: [String: [LSPDiagnostic]] = [:]
    var lspStatusMessage: String = "Not started"

    // MARK: - Parallel Multi-Agent State
    /// Active when agentMode == .parallel. Shows per-sub-agent streaming state.
    @Published var parallelAgents: [ParallelAgentState] = []
    /// The orchestration plan message shown before agents start.
    @Published var orchestrationPlan: String? = nil
    /// The final synthesized response from the orchestrator.
    @Published var synthesisingContent: String = ""

    private let orchestrator = AgentOrchestrator()

    /// Real-time streaming performance metrics (tokens/sec, elapsed, phase).
    let streamMetrics = StreamMetrics()

    /// Smart follow-up suggestions generated after each assistant response.
    @Published var followUpSuggestions: [FollowUpSuggestion] = []

    /// Multi-file context resolver for automatic file awareness.
    let contextResolver = ContextResolver()

    // MARK: - Next-Level Intelligence Subsystems

    /// Detects when the agent is stuck in a repeating failure pattern and forces a strategy pivot.
    let cognitiveLoopDetector = CognitiveLoopDetector()
    /// Calibrated confidence scoring — adapts agent autonomy based on certainty.
    let confidenceCalibration = ConfidenceCalibration()
    /// Adversarial self-review — red team critic for Build mode output.
    let adversarialReview = AdversarialReviewEngine()
    /// Causal regression tracking — traces build/test failures to the commit that caused them.
    let regressionTracker = CausalRegressionTracker()
    /// Intent continuity — persists high-level goals across sessions with progress tracking.
    let intentContinuity = IntentContinuityService()
    /// Tracks code changes made during the current agent run for adversarial review.
    var currentRunCodeChanges: [CodeChange] = []

    // MARK: - Speculative Branching State
    /// Active when agentMode == .speculative. Shows per-branch state.
    @Published var speculativeBranches: [SpeculativeBranchState] = []
    /// Index of the winning branch after evaluation.
    @Published var speculativeWinnerIndex: Int? = nil

    /// Preserved partial response content when a stream error occurs.
    @Published var streamErrorPartialContent: String?
    /// The error message from a failed stream, for inline retry UI.
    @Published var streamErrorMessage: String?

    #if os(macOS)
    /// When non-nil, the UI should show an approval dialog for system_run. Call respondToSystemRunApproval when the user chooses.
    @Published var pendingSystemRunApproval: (command: String, resolvedPath: String)?
    var systemRunApprovalContinuation: CheckedContinuation<SystemRunApprovalResponse, Never>?

    func respondToSystemRunApproval(_ response: SystemRunApprovalResponse) {
        guard let cont = systemRunApprovalContinuation else { return }
        systemRunApprovalContinuation = nil
        pendingSystemRunApproval = nil
        cont.resume(returning: response)
    }
    #endif

    // Legacy properties for backward compatibility
    @Published var apiKey: String {
        didSet { 
            KeychainStorage.set(account: "OpenRouterAPIKey", value: apiKey)
            // Update OpenRouter configuration
            if let config = aiService.modelRegistry.getProviderConfig(for: .openRouter) {
                let updatedConfig = ProviderConfiguration(
                    provider: .openRouter,
                    apiKey: apiKey,
                    baseURL: config.baseURL
                )
                aiService.modelRegistry.setProviderConfig(updatedConfig)
            }
        }
    }
    @Published var platformUser: PlatformUser?
    @Published private(set) var localOllamaDetected: Bool = false
    @Published private(set) var localOllamaReady: Bool = false
    @Published var selectedModel: AIModel {
        didSet { 
            guard oldValue != selectedModel else { return }
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "SelectedModel")
            // Update AI service to use equivalent enhanced model
            if let enhancedModel = aiService.availableModels.first(where: { $0.modelID == selectedModel.rawValue }) {
                aiService.selectModel(enhancedModel)
            }
        }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "SystemPrompt") }
    }
    /// Agent mode for next message (Plan, Full Stack, Argue, Spec). Per-message override.
    @Published var agentMode: AgentMode {
        didSet { UserDefaults.standard.set(agentMode.rawValue, forKey: "AgentMode") }
    }

    /// Selected model mode (Thinking, Fast, 1M, etc.) — nil for models without modes.
    @Published var selectedModelMode: ModelMode? {
        didSet {
            if let mode = selectedModelMode {
                UserDefaults.standard.set(mode.id, forKey: "SelectedModelMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "SelectedModelMode")
            }
        }
    }

    // New multi-provider system
    @Published private var aiService = MultiProviderAIService()
    
    private let openRouterService = OpenRouterService()
    let activityStore = ActivityStore()
    internal var streamTask: Task<Void, Never>?
    /// The OpenClaw session ID currently being processed, if any.
    internal var activeOpenClawSessionId: String?
    private var cancellables = Set<AnyCancellable>()
    var syncDebounceTask: Task<Void, Never>?
    var syncDirty = false

    var suggestions: [Suggestion] {
        SuggestionEngine.suggest(activityEntries: activityStore.entries, workingDirectory: workingDirectory)
    }
    private static let appDirectoryName = "GRump"
    private static let legacyAppDirectoryName = "ClaudeLite"
    private static let draftsUserDefaultsKey = "GRumpConversationDrafts"

    var messages: [Message] {
        currentConversation?.messages ?? []
    }

    /// Model actually used for requests (project config can override selectedModel).
    /// Validated against tier; falls back to first allowed model if project config specifies a Pro model for free user.
    var effectiveModel: AIModel {
        // First try to get the enhanced model from AI service
        if let enhancedModel = aiService.currentModel {
            // Convert back to legacy AIModel for compatibility
            return AIModel(rawValue: enhancedModel.modelID) ?? selectedModel
        }
        
        // Fallback to legacy system
        let candidate = projectConfig?.model.flatMap { AIModel(rawValue: $0) } ?? selectedModel
        let allowed = AIModel.modelsForTier(platformTier)
        return allowed.contains(candidate) ? candidate : AIModel.defaultForTier(platformTier)
    }
    
    /// Enhanced model currently selected
    var currentEnhancedModel: EnhancedAIModel? {
        return aiService.currentModel
    }
    
    /// Current AI provider
    var currentAIProvider: AIProvider {
        return aiService.currentProvider
    }
    
    /// Whether the current AI provider is configured
    var isAIProviderConfigured: Bool {
        return aiService.isConfigured
    }

    /// All models for a given provider from the registry
    func modelsForProvider(_ provider: AIProvider) -> [EnhancedAIModel] {
        if provider == .onDevice {
            return aiService.availableModels.filter { $0.provider == .onDevice }
        }
        return aiService.modelRegistry.getModels(for: provider)
    }

    /// All local models (Ollama + On-Device)
    var localModels: [EnhancedAIModel] {
        modelsForProvider(.ollama) + modelsForProvider(.onDevice)
    }

    /// Whether a provider has any models available
    func providerHasModels(_ provider: AIProvider) -> Bool {
        !modelsForProvider(provider).isEmpty
    }

    /// Select a provider and model from the picker
    func selectProviderAndModel(provider: AIProvider, model: EnhancedAIModel) {
        aiService.selectProvider(provider)
        aiService.selectModel(model)
    }

    /// Select just a provider (model auto-selected)
    func selectProvider(_ provider: AIProvider) {
        aiService.selectProvider(provider)
    }

    
    init() {
        // Initialize AI service
        self.aiService = MultiProviderAIService()
        
        // Load legacy API key
        if let key = KeychainStorage.get(account: "OpenRouterAPIKey") {
            self.apiKey = key
        } else if let legacy = UserDefaults.standard.string(forKey: "OpenRouterAPIKey"), !legacy.isEmpty {
            self.apiKey = legacy
            KeychainStorage.set(account: "OpenRouterAPIKey", value: legacy)
            UserDefaults.standard.removeObject(forKey: "OpenRouterAPIKey")
        } else {
            self.apiKey = ""
        }
        
        // Load legacy model selection
        let savedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? AIModel.claudeSonnet4.rawValue
        let migratedModel = Self.migrateLegacyModelID(savedModel)
        self.selectedModel = AIModel(rawValue: migratedModel) ?? .claudeSonnet4
        self.systemPrompt = UserDefaults.standard.string(forKey: "SystemPrompt") ?? GRumpDefaults.defaultSystemPrompt
        let savedMode = UserDefaults.standard.string(forKey: "AgentMode") ?? AgentMode.standard.rawValue
        self.agentMode = AgentMode(rawValue: savedMode) ?? .standard
        self.workingDirectory = UserDefaults.standard.string(forKey: "WorkingDirectory") ?? ""
        self.projectConfig = ProjectConfig.load(from: self.workingDirectory)
        if !self.workingDirectory.isEmpty {
            activityStore.setPersistencePath("\(self.workingDirectory)/.grump/activity.json")
        }

        // Show an empty conversation immediately so UI renders fast
        createNewConversation()

        // Load conversations on the next main-actor tick (fast, file I/O only)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.loadConversations()
            if !self.conversations.isEmpty {
                self.currentConversation = self.conversations.first
                if let id = self.currentConversation?.id {
                    self.userInput = self.loadDraft(forConversationId: id)
                }
            }
        }

        // Network calls (Ollama, platform) run detached so they never
        // block the main-actor cooperative queue during startup.
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            if await PlatformService.isLoggedIn {
                await self.refreshPlatformUser()
            }
            await self.refreshLocalOllamaAvailability()
        }

        // Set up AI service observers
        aiService.$currentProvider
            .sink { [weak self] provider in
                // Update legacy selectedModel when provider changes
                if let enhancedModel = self?.aiService.currentModel {
                    // Try to find equivalent legacy model
                    if let legacyModel = AIModel(rawValue: enhancedModel.modelID) {
                        self?.selectedModel = legacyModel
                    }
                }
            }
            .store(in: &cancellables)
        
        aiService.$currentModel
            .sink { [weak self] enhancedModel in
                // Update legacy selectedModel when model changes
                if let enhancedModel = enhancedModel,
                   let legacyModel = AIModel(rawValue: enhancedModel.modelID) {
                    self?.selectedModel = legacyModel
                }
            }
            .store(in: &cancellables)

        aiService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        activityStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Subscribe to OpenClaw messages from the gateway
        NotificationCenter.default.publisher(for: .openClawMessageReceived)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let userInfo = notification.userInfo,
                      let sessionId = userInfo["sessionId"] as? String,
                      let content = userInfo["content"] as? String else { return }
                let model = userInfo["model"] as? String
                Task { @MainActor in
                    await self.handleOpenClawMessage(sessionId: sessionId, content: content, model: model)
                }
            }
            .store(in: &cancellables)
    }

    /// Fetches /api/me and updates platformUser (credits, tier). Call after login or after a chat run.
    func refreshPlatformUser() async {
        guard PlatformService.isLoggedIn else {
            await MainActor.run {
                platformUser = nil
                ensureSelectedModelValidForTier()
            }
            return
        }
        do {
            let user = try await PlatformService.fetchMe()
            await MainActor.run {
                platformUser = user
                ensureSelectedModelValidForTier()
            }
        } catch {
            await MainActor.run {
                platformUser = nil
                ensureSelectedModelValidForTier()
            }
        }
    }

    func refreshLocalOllamaAvailability() async {
        let registry = aiService.modelRegistry
        let detected = await registry.isOllamaRunning()

        if detected {
            _ = await registry.refreshOllamaModels()
        }

        let hasPulledModels = !registry.getModels(for: .ollama).isEmpty

        localOllamaDetected = detected
        localOllamaReady = detected && hasPulledModels

        guard localOllamaReady else { return }

        let hasPlatformAuth = platformUser != nil
        let hasLegacyAPIKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !hasPlatformAuth && !hasLegacyAPIKey else { return }

        aiService.selectProvider(.ollama)
        aiService.refreshModels()
        if aiService.currentModel == nil, let fallback = aiService.availableModels.first {
            aiService.selectModel(fallback)
        }
    }

    func logoutPlatform() {
        PlatformService.logout()
        platformUser = nil
    }

    func saveDraft(_ text: String, forConversationId id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.draftsUserDefaultsKey) as? [String: String] ?? [:]
        if text.isEmpty {
            dict.removeValue(forKey: id.uuidString)
        } else {
            dict[id.uuidString] = text
        }
        UserDefaults.standard.set(dict, forKey: Self.draftsUserDefaultsKey)
    }

    func loadDraft(forConversationId id: UUID) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: Self.draftsUserDefaultsKey) as? [String: String] ?? [:]
        return dict[id.uuidString] ?? ""
    }

    /// Maps removed OpenRouter model IDs to current equivalents so existing users keep a sensible selection.
    private static func migrateLegacyModelID(_ id: String) -> String {
        switch id {
        case "anthropic/claude-3.7-sonnet": return AIModel.claudeSonnet4.rawValue
        default: return id
        }
    }

    
    /// Project-level config loaded from .grump/config.json or grump.json when working directory is set.
    @Published var projectConfig: ProjectConfig?

    /// Tool allowlist from applied workflow preset. When set, overrides project config tool list.
    @Published var appliedPresetToolAllowlist: [String]?
    /// Name of applied preset, for display. When non-nil, a preset is active.
    @Published var appliedPresetName: String?
    /// Max agent steps from applied preset. When set, overrides user default (project config still wins).
    @Published var appliedPresetMaxAgentSteps: Int?

    /// Commands run or denied via system_run this session (for Security history view).
    @Published var systemRunHistory: [SystemRunHistoryEntry] = []

        
    var conversationThreads: [MessageThread] {
        currentConversation?.threads ?? []
    }
    
    /// Get all branches for the current conversation
    var conversationBranches: [MessageBranch] {
        currentConversation?.branches ?? []
    }
    
    
    
    
    
    // MARK: - Undo Send

    /// Stores the last sent message text so it can be undone within a short window.
    @Published var undoSendAvailable = false
    var lastSentText: String?
    var undoSendTask: Task<Void, Never>?

    // MARK: - Apple Intelligence Context

    enum UserSentiment { case neutral, frustrated }

    /// Last detected user sentiment (from AppleIntelligenceService).
    var lastUserSentiment: UserSentiment = .neutral
    /// Last classified user intent (from AppleIntelligenceService).
    var lastUserIntent: AppleIntelligenceService.UserIntent = .general

    
    
    
    /// Load tools from enabled MCP servers.
    private func loadMCPTools() async -> [[String: Any]] {
        let configs = MCPServerConfigStorage.load().filter { $0.enabled }
        var all: [[String: Any]] = []
        for cfg in configs {
            let tools = await MCPService.fetchTools(serverId: cfg.id, transport: cfg.transport)
            all.append(contentsOf: tools)
        }
        return all
    }

    /// Effective model, prompt, tools, and max steps (project config > preset > user default).
    private func effectiveAgentConfig() -> (model: AIModel, prompt: String, tools: [[String: Any]], maxSteps: Int) {
        let storedMax = UserDefaults.standard.object(forKey: "MaxAgentSteps") as? Int ?? 200
        let baseMax = min(1000, max(5, storedMax))
        let presetMax = appliedPresetMaxAgentSteps.map { min(1000, max(5, $0)) } ?? baseMax
        guard let cfg = projectConfig else {
            var prompt = prependModeInstructions(to: prependSkillsContent(to: prependSoulContent(to: systemPrompt)))
            if !workingDirectory.isEmpty {
                prompt += "\n\nCurrent working directory: \(workingDirectory)"
            }
            appendSymbolGraphSummary(to: &prompt)
            appendProjectMemory(to: &prompt)
            appendTemporalIntelligence(to: &prompt)
            appendIntentContext(to: &prompt)
            appendConfidenceWarning(to: &prompt)
            let allowlist = appliedPresetToolAllowlist ?? nil
            let userDenylist = ToolsSettingsStorage.loadDenylist()
            let tools = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: userDenylist)
            return (selectedModel, prompt, tools, presetMax)
        }
        let (model, prompt, toolAllowlist, maxSteps) = cfg.merged(
            currentModel: selectedModel,
            currentPrompt: systemPrompt,
            currentMaxSteps: presetMax
        )
        var finalPrompt = prependModeInstructions(to: prependSkillsContent(to: prependSoulContent(to: prompt)))
        if !workingDirectory.isEmpty {
            finalPrompt += "\n\nCurrent working directory: \(workingDirectory)"
        }
        cfg.appendFacts(to: &finalPrompt)
        cfg.appendContext(to: &finalPrompt, baseDir: workingDirectory)
        appendSymbolGraphSummary(to: &finalPrompt)
        appendProjectMemory(to: &finalPrompt)
        appendTemporalIntelligence(to: &finalPrompt)
        appendIntentContext(to: &finalPrompt)
        appendConfidenceWarning(to: &finalPrompt)
        let allowlist = appliedPresetToolAllowlist ?? toolAllowlist
        let userDenylist = ToolsSettingsStorage.loadDenylist()
        let tools = ToolDefinitions.toolsFiltered(allowlist: allowlist, userDenylist: userDenylist)
        return (model, finalPrompt, tools, maxSteps)
    }

    /// Prepends mode-specific instructions to the base prompt.
    private func prependModeInstructions(to basePrompt: String) -> String {
        let instructions: String
        switch agentMode {
        case .standard:
            instructions = """
            MODE: Chat.
            IMPORTANT — Your FIRST response should start with a brief acknowledgment (1-2 sentences) confirming you understand the request. This reassures the user that the system is working. Then proceed with your full answer, tool calls, or implementation.
            """
        case .plan:
            instructions = """
            MODE: Plan.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Acknowledge what the user wants to build, then ask 2-3 focused clarifying questions (e.g. target platform, key constraints, scale, must-have vs nice-to-have features). This reassures the user the system is working and gathers context before you invest time planning.
            Once the user answers (or if they say "just go" / "skip"), THEN produce the full detailed plan with architecture, steps, tradeoffs, and timeline. Do not implement until the user approves the plan.
            """
        case .fullStack:
            instructions = """
            MODE: Full Stack.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Confirm what the user wants to build and ask 2-3 quick clarifying questions (e.g. target platform, preferred tech stack, database needs, deployment target). This gives immediate feedback that the system understood the request.
            Once the user answers (or says "just go" / "skip"), produce a Mermaid chart of the entire system from a software engineer's perspective (architecture, components, data flow), then implement step by step based on that architecture.
            """
        case .argue:
            instructions = """
            MODE: Argue.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Restate the user's position in your own words to confirm you understand it, then immediately present your strongest counter-argument or alternative. This gives instant feedback that the system is engaged.
            Continue the debate across follow-up messages. Push back, challenge assumptions, and explore tradeoffs until you converge on the best solution. Do not implement until the debate concludes.
            """
        case .spec:
            instructions = """
            MODE: Spec.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Confirm what the user wants to spec out, then present 3-5 structured clarifying questions (numbered, specific, with example answers where helpful). This reassures the user that the system understood their request and is gathering the right context.
            Once the user answers (or says "just go" / "skip"), produce the full detailed spec. Proceed only after gathering enough context.
            """
        case .parallel:
            instructions = """
            MODE: Parallel.
            IMPORTANT — Your FIRST response must be SHORT (under 150 words). Acknowledge the task, then briefly outline how you plan to decompose it into parallel subtasks (e.g. "I'll split this into 3 parallel agents: one for X, one for Y, one for Z"). This gives the user immediate confidence that the system is working and shows the orchestration strategy.
            Then proceed to decompose, assign each subtask to the best-fit model, run them in parallel, and synthesize the results into a single coherent response.
            """
        case .speculative:
            instructions = """
            MODE: Explore (Speculative Branching).
            The system will automatically generate 2-3 competing solution approaches in parallel, \
            evaluate each one, and present the winner. You are one branch of this exploration. \
            Commit fully to your assigned approach — do not hedge or mention alternatives.
            """
        }
        let antiXML = "\nIMPORTANT: Do NOT output raw XML, function calls, or tool invocation markup (e.g. <execute>, <function>, <tool_call>) in your text response. Use the native tool_calls API mechanism instead. Any XML tool markup in your text will be stripped and may cause unexpected behavior."
        return instructions + antiXML + "\n\n" + basePrompt
    }

    /// Prepends SOUL.md identity content as the foundation layer.
    private func prependSoulContent(to basePrompt: String) -> String {
        guard let soul = SoulStorage.loadSoul(workingDirectory: workingDirectory) else { return basePrompt }
        let soulBlock = "\n\n--- Soul: \(soul.name) ---\n" + soul.body + "\n\n--- End of soul ---\n\n"
        return soulBlock + basePrompt
    }

    /// Prepends enabled skill instructions to the base prompt.
    /// Combines explicitly enabled skills + context-aware auto-suggested skills (score > 0.7).
    private func prependSkillsContent(to basePrompt: String) -> String {
        let skills = SkillsStorage.loadSkills(workingDirectory: workingDirectory)
        let enabledIds = SkillsSettingsStorage.loadAllowlist()
        var activeSkills = skills.filter { enabledIds.contains($0.id) }

        // Context-aware auto-injection: find relevant skills not already enabled
        if let lastMessage = messages.last(where: { $0.role == .user })?.content {
            let fileExtensions = detectFileExtensions()
            let candidates = skills.filter { !enabledIds.contains($0.id) }
            let suggested = candidates
                .map { ($0, $0.relevanceScore(for: lastMessage, fileExtensions: fileExtensions)) }
                .filter { $0.1 > 0.7 }
                .sorted { $0.1 > $1.1 }
                .prefix(3)
                .map(\.0)
            activeSkills.append(contentsOf: suggested)
        }

        guard !activeSkills.isEmpty else { return basePrompt }
        let skillBlocks = activeSkills.map { skill in
            let header = "\n\n--- Skill: \(skill.name) ---\n"
            return header + skill.body
        }
        return skillBlocks.joined() + "\n\n--- End of skills ---\n\n" + basePrompt
    }

    /// Detect file extensions in the working directory for context-aware skill matching.
    private func detectFileExtensions() -> Set<String> {
        guard !workingDirectory.isEmpty else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: workingDirectory) else { return [] }
        var extensions: Set<String> = []
        for item in items.prefix(50) { // Sample up to 50 files
            let ext = (item as NSString).pathExtension
            if !ext.isEmpty { extensions.insert(".\(ext)") }
        }
        return extensions
    }

    // MARK: - Agent Loop (Multi-turn with parallel tool execution)

    internal func runAgentLoop() async {
        // Phase 3: Cache config + MCP tools once for entire agent run
        let (_, cachedPrompt, nativeTools, maxIterations) = effectiveAgentConfig()
        let mcpTools = await loadMCPTools()
        let tools = nativeTools + mcpTools

        var iterationCount = 0
        currentAgentStepMax = maxIterations

        repeat {
            if Task.isCancelled { break }
            iterationCount += 1
            currentAgentStep = iterationCount

            var textBuffer = ""
            var toolCallBuffers: [Int: (id: String, name: String, args: String)] = [:]

            let apiMessages = buildAPIMessages(cachedPrompt: cachedPrompt)
            let stream: AsyncThrowingStream<StreamEvent, Error>
            
            // Use platform backend if available, otherwise use configured provider
            if let token = PlatformService.authToken, !token.isEmpty {
                stream = openRouterService.streamMessageViaBackend(
                    messages: apiMessages,
                    model: effectiveModel.rawValue,
                    backendBaseURL: PlatformService.baseURL,
                    authToken: token,
                    tools: tools
                )
            } else {
                stream = aiService.streamMessage(
                    messages: apiMessages,
                    tools: tools
                )
            }

            var finishReason = ""
            var lastStreamPublishTime = Date()
            var lastPublishedLength = 0

            // Start metrics tracking for this iteration
            if iterationCount == 1 { streamMetrics.startStream() }
            streamMetrics.setPhase(.waiting)

            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .text(let chunk):
                        textBuffer += chunk
                        // Approximate token count (~4 chars per token)
                        let approxTokens = max(1, chunk.count / 4)
                        streamMetrics.recordTokens(approxTokens)

                        let now = Date()
                        let elapsed = now.timeIntervalSince(lastStreamPublishTime)
                        let charGrowth = textBuffer.count - lastPublishedLength
                        // Adaptive throttle: tune interval based on model speed
                        let adaptiveInterval = streamMetrics.recommendedUpdateInterval
                        let adaptiveBatch = streamMetrics.recommendedBatchSize
                        let shouldPublish = elapsed >= adaptiveInterval || charGrowth >= adaptiveBatch || chunk.contains("\n")
                        if shouldPublish {
                            lastStreamPublishTime = now
                            lastPublishedLength = textBuffer.count
                            // Strip any XML tool-call markup before displaying
                            if XMLToolCallParser.containsXMLToolCalls(textBuffer) {
                                let parsed = XMLToolCallParser.parse(textBuffer)
                                streamingContent = parsed.strippedText
                            } else {
                                streamingContent = textBuffer
                            }
                            FrameLoopService.shared.markStreaming(for: 0.5)
                        }

                    case .toolCallDelta(let deltas):
                        for delta in deltas {
                            let idx = delta.index ?? 0
                            var existing = toolCallBuffers[idx] ?? (id: delta.id ?? "", name: "", args: "")
                            if let id = delta.id, !id.isEmpty { existing.id = id }
                            if let name = delta.function?.name { existing.name += name }
                            if let args = delta.function?.arguments { existing.args += args }
                            toolCallBuffers[idx] = existing
                        }

                    case .done(let reason):
                        finishReason = reason
                    }
                }
                // Parse and strip XML tool calls from final buffer
                if XMLToolCallParser.containsXMLToolCalls(textBuffer) {
                    let parsed = XMLToolCallParser.parse(textBuffer)
                    textBuffer = parsed.strippedText
                    // Inject parsed XML tool calls into toolCallBuffers
                    for xmlCall in parsed.toolCalls {
                        let nextIdx = (toolCallBuffers.keys.max() ?? -1) + 1
                        toolCallBuffers[nextIdx] = (
                            id: "xml-\(UUID().uuidString.prefix(8))",
                            name: xmlCall.name,
                            args: xmlCall.argumentsJSON
                        )
                    }
                    if finishReason == nil && !parsed.toolCalls.isEmpty {
                        finishReason = "tool_calls"
                    }
                }
                // Ensure final content is published (throttle may have skipped last chunk)
                streamingContent = textBuffer
            } catch is CancellationError {
                currentAgentStep = nil
                currentAgentStepMax = nil
                streamingContent = ""
                streamMetrics.endStream()
                return
            } catch {
                if !textBuffer.isEmpty {
                    let partial = Message(role: .assistant, content: textBuffer + "\n\n(Partial response: stream interrupted.)")
                    currentConversation?.messages.append(partial)
                    syncConversation()
                }

                if shouldRetry(error: error, attempt: iterationCount) {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay(attempt: iterationCount) * 1_000_000_000))
                    continue
                }

                currentAgentStep = nil
                currentAgentStepMax = nil
                let friendly = friendlyErrorMessage(error)
                errorMessage = friendly
                streamingContent = ""
                streamMetrics.endStream(error: friendly)

                // Preserve partial content + error for inline retry UI
                streamErrorPartialContent = textBuffer.isEmpty ? nil : textBuffer
                streamErrorMessage = friendly

                // Notify user of task failure
                if let conv = currentConversation {
                    GRumpNotificationService.shared.notifyTaskFailed(
                        conversationId: conv.id,
                        conversationTitle: conv.title,
                        errorMessage: friendly
                    )
                }
                return
            }

            if Task.isCancelled {
                currentAgentStep = nil
                currentAgentStepMax = nil
                if !textBuffer.isEmpty {
                    let toolCalls: [ToolCall]? = toolCallBuffers.isEmpty ? nil : toolCallBuffers.sorted(by: { $0.key < $1.key }).map {
                        ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.args)
                    }
                    let assistantMsg = Message(role: .assistant, content: textBuffer, toolCalls: toolCalls)
                    currentConversation?.messages.append(assistantMsg)
                    syncConversation()
                }
                streamingContent = ""
                return
            }

            // Commit assistant message
            let toolCalls: [ToolCall]? = toolCallBuffers.isEmpty ? nil : toolCallBuffers.sorted(by: { $0.key < $1.key }).map {
                ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.args)
            }
            if !textBuffer.isEmpty || toolCalls != nil {
                let assistantMsg = Message(role: .assistant, content: textBuffer, toolCalls: toolCalls)
                currentConversation?.messages.append(assistantMsg)
                syncConversation()
                streamingContent = ""
            }

            if toolCallBuffers.isEmpty || finishReason == "stop" {
                break
            }

            // Execute tool calls in parallel
            streamMetrics.setPhase(.toolUse)
            let sortedCalls = toolCallBuffers.sorted(by: { $0.key < $1.key })

            // Update UI with active tool calls
            let now = Date()
            activeToolCalls = sortedCalls.map { (_, call) in
                ToolCallStatus(
                    id: call.id, 
                    name: call.name, 
                    arguments: call.args, 
                    status: .running, 
                    result: nil,
                    progress: 0.0,
                    startTime: now,
                    currentStep: getInitialStep(for: call.name),
                    totalSteps: getEstimatedSteps(for: call.name),
                    currentStepNumber: 0
                )
            }

            // Phase 3: Pipeline — pre-build next API messages while tools execute
            let pipelinedMessages = buildAPIMessages(cachedPrompt: cachedPrompt)
            _ = pipelinedMessages // Pre-computed, ready for next iteration

            let results = await executeToolCallsParallel(sortedCalls.map { $0.value })

            // Post tool results (truncate large outputs to preserve context budget)
            for (idx, (_, call)) in sortedCalls.enumerated() {
                let result = truncateToolResult(results[idx], maxChars: 12000)
                let toolMsg = Message(role: .tool, content: result, toolCallId: call.id)
                currentConversation?.messages.append(toolMsg)

                if idx < activeToolCalls.count {
                    activeToolCalls[idx].status = result.lowercased().hasPrefix("error") ? .failed : .completed
                    activeToolCalls[idx].result = String(result.prefix(200))
                    activeToolCalls[idx].progress = 1.0
                    activeToolCalls[idx].endTime = Date()
                    activeToolCalls[idx].currentStepNumber = activeToolCalls[idx].totalSteps
                    activeToolCalls[idx].currentStep = result.lowercased().hasPrefix("error") ? "Failed" : "Completed"
                }

                let success = !result.lowercased().hasPrefix("error")
                var metadata: ActivityEntry.Metadata?
                if let data = call.args.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadata = ActivityEntry.Metadata(
                        filePath: args["path"] as? String ?? (args["paths"] as? [String])?.first,
                        command: args["command"] as? String
                    )
                }
                activityStore.append(ActivityEntry(
                    toolName: call.name,
                    summary: String(result.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines),
                    success: success,
                    conversationId: currentConversation?.id,
                    metadata: metadata
                ))

                // --- Cognitive Loop Detector: record each tool action ---
                if let pivot = await cognitiveLoopDetector.recordAction(
                    toolName: call.name,
                    arguments: call.args,
                    result: result,
                    wasError: !success
                ) {
                    // Inject pivot strategy as a system message to break the loop
                    let pivotMsg = Message(role: .system, content: pivot.systemMessage)
                    currentConversation?.messages.append(pivotMsg)
                }

                // --- Code Change Tracking: record file modifications for adversarial review ---
                let writeTools: Set<String> = ["edit_file", "write_file", "create_file", "append_file"]
                if writeTools.contains(call.name), success,
                   let data = call.args.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = args["path"] as? String {
                    let op: CodeChange.Operation = call.name == "create_file" ? .created : .edited
                    currentRunCodeChanges.append(CodeChange(filePath: path, operation: op, content: String(result.prefix(2000))))
                }

                // --- Causal Regression Tracker: analyze build/test failures ---
                let buildTestTools: Set<String> = ["run_build", "run_tests"]
                if buildTestTools.contains(call.name), !success {
                    if let analysis = await regressionTracker.analyze(
                        errorOutput: result,
                        failedCommand: call.name,
                        workingDirectory: workingDirectory
                    ) {
                        let analysisMsg = Message(role: .system, content: analysis.markdownSummary)
                        currentConversation?.messages.append(analysisMsg)
                    }
                }
            }
            // Phase 4: Single sync after all tool results instead of per-result
            syncConversation()

        } while iterationCount < maxIterations

        currentAgentStep = nil
        currentAgentStepMax = nil

        if iterationCount >= maxIterations {
            let warningMsg = Message(role: .assistant, content: "I've reached the maximum iteration limit (\(maxIterations) turns). The task may be partially complete. You can continue by sending another message.")
            currentConversation?.messages.append(warningMsg)
            syncConversation()
        }

        activeToolCalls = []
        streamMetrics.endStream()

        // --- Adversarial Self-Review (Build mode only) ---
        if agentMode == .fullStack && !currentRunCodeChanges.isEmpty {
            let userMessage = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
            if let report = await adversarialReview.review(
                codeChanges: currentRunCodeChanges,
                conversationContext: userMessage,
                apiKey: apiKey,
                authToken: PlatformService.authToken,
                primaryModel: effectiveModel
            ) {
                let reviewMsg = Message(role: .assistant, content: report.markdownSummary)
                currentConversation?.messages.append(reviewMsg)
                syncConversation()
            }
        }
        currentRunCodeChanges = []

        // --- Confidence Calibration: record outcome ---
        let lastToolResults = activityStore.entries.suffix(10).map { (name: $0.toolName, success: $0.success) }
        let hasErrors = lastToolResults.contains { !$0.success }
        confidenceCalibration.recordOutcome(
            predictedLevel: confidenceCalibration.currentLevel,
            actualSuccess: !hasErrors
        )

        // --- Cognitive Loop Detector: record pivot outcome ---
        let loopPivots = await cognitiveLoopDetector.totalPivots
        if loopPivots > 0 {
            await cognitiveLoopDetector.recordPivotOutcome(success: !hasErrors)
        }
        await cognitiveLoopDetector.reset()

        // --- Intent Continuity: extract or update intent ---
        if let firstUserMsg = currentConversation?.messages.first(where: { $0.role == .user })?.content {
            if intentContinuity.activeIntent == nil {
                if let extracted = IntentContinuityService.extractIntent(from: firstUserMsg) {
                    intentContinuity.createIntent(goal: extracted.goal, milestones: extracted.milestones)
                }
            } else {
                intentContinuity.updateActiveIntent(conversationId: currentConversation?.id.uuidString)
            }
        }

        // --- Confidence Assessment for next run ---
        let _ = confidenceCalibration.assess(
            recentToolResults: lastToolResults,
            lspDiagnostics: lspDiagnostics,
            targetFiles: currentRunCodeChanges.map(\.filePath),
            taskDescription: currentConversation?.messages.last(where: { $0.role == .user })?.content ?? "",
            memoryHits: 0,
            loopDetectorPivots: loopPivots
        )

        // Generate smart follow-up suggestions from the last assistant message
        if let lastAssistant = currentConversation?.messages.last(where: { $0.role == .assistant }) {
            followUpSuggestions = FollowUpGenerator.generate(from: lastAssistant.content, agentMode: agentMode)
        }

        flushSync() // Ensure final state is persisted immediately
        saveToProjectMemoryIfEnabled()
        // Notify user of task completion (only fires when app is backgrounded)
        if let conv = currentConversation {
            let lastAssistant = conv.messages.last(where: { $0.role == .assistant })?.content ?? "Task completed."
            GRumpNotificationService.shared.notifyTaskComplete(
                conversationId: conv.id,
                conversationTitle: conv.title,
                modelName: effectiveModel.displayName,
                resultSummary: String(lastAssistant.prefix(200))
            )
        }
        if PlatformService.isLoggedIn {
            Task { await refreshPlatformUser() }
        }
    }

    // MARK: - Parallel Multi-Agent Loop

    internal func runParallelAgentLoop(userTask: String) async {
        let advisedMax = PerformanceAdvisor.shared.recommendedMaxConcurrency
        let userMax = UserDefaults.standard.object(forKey: "ParallelAgentsMax") as? Int ?? 4
        let maxConcurrent = min(userMax, advisedMax)
        let localOrchestrator = AgentOrchestrator(maxConcurrentAgents: maxConcurrent)
        let token = PlatformService.authToken
        let key = apiKey

        await localOrchestrator.run(
            userTask: userTask,
            conversationHistory: currentConversation?.messages ?? [],
            apiKey: key,
            authToken: (token?.isEmpty == false) ? token : nil,
            fallbackModel: effectiveModel,
            onEvent: { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleOrchestratorEvent(event)
                }
            }
        )

        activeToolCalls = []
        parallelAgents = parallelAgents.map { var a = $0; if a.status == .running { a.status = .completed }; return a }
        flushSync()
        saveToProjectMemoryIfEnabled()
        // Notify user of parallel task completion
        if let conv = currentConversation {
            let lastAssistant = conv.messages.last(where: { $0.role == .assistant })?.content ?? "Parallel task completed."
            GRumpNotificationService.shared.notifyTaskComplete(
                conversationId: conv.id,
                conversationTitle: conv.title,
                modelName: effectiveModel.displayName,
                resultSummary: String(lastAssistant.prefix(200))
            )
        }
        if PlatformService.isLoggedIn {
            Task { await refreshPlatformUser() }
        }
    }

    // MARK: - Speculative Branching Loop

    internal func runSpeculativeBranchLoop(userTask: String) async {
        let engine = SpeculativeBranchingEngine()
        let token = PlatformService.authToken
        let key = apiKey

        // Post a header message
        let headerMsg = Message(role: .assistant, content: "**Explore Mode** — Generating competing approaches...")
        currentConversation?.messages.append(headerMsg)
        syncConversation()

        await engine.run(
            userTask: userTask,
            conversationHistory: currentConversation?.messages ?? [],
            apiKey: key,
            authToken: (token?.isEmpty == false) ? token : nil,
            fallbackModel: effectiveModel,
            onEvent: { [weak self] event in
                guard let self else { return }
                Task { @MainActor in
                    self.handleSpeculativeBranchEvent(event)
                }
            }
        )

        flushSync()
        saveToProjectMemoryIfEnabled()
        if let conv = currentConversation {
            let lastAssistant = conv.messages.last(where: { $0.role == .assistant })?.content ?? "Exploration completed."
            GRumpNotificationService.shared.notifyTaskComplete(
                conversationId: conv.id,
                conversationTitle: conv.title,
                modelName: effectiveModel.displayName,
                resultSummary: String(lastAssistant.prefix(200))
            )
        }
        if PlatformService.isLoggedIn {
            Task { await refreshPlatformUser() }
        }
    }

    private func handleSpeculativeBranchEvent(_ event: SpeculativeBranchEvent) {
        switch event {
        case .strategiesReady(let strategies):
            speculativeBranches = strategies.map { strategy in
                SpeculativeBranchState(
                    id: strategy.id,
                    strategyName: strategy.name,
                    branchIndex: strategy.branchIndex,
                    status: .pending
                )
            }
            let planLines = strategies.map { s in
                "• **Approach \(s.branchIndex + 1)**: \(s.name) — \(s.approach)"
            }.joined(separator: "\n")
            let planMsg = Message(role: .assistant, content: "**Speculative Branches** — \(strategies.count) approaches:\n\n\(planLines)")
            currentConversation?.messages.append(planMsg)
            syncConversation()

        case .branchStarted(let branchId, _, let model):
            if let idx = speculativeBranches.firstIndex(where: { $0.id == branchId }) {
                speculativeBranches[idx].status = .running
                speculativeBranches[idx].modelName = model
            }

        case .branchChunk(let branchId, let text):
            if let idx = speculativeBranches.firstIndex(where: { $0.id == branchId }) {
                speculativeBranches[idx].streamingText += text
            }

        case .branchCompleted(let branchId, let result):
            if let idx = speculativeBranches.firstIndex(where: { $0.id == branchId }) {
                speculativeBranches[idx].status = .completed
                speculativeBranches[idx].result = result
            }

        case .branchFailed(let branchId, let error):
            if let idx = speculativeBranches.firstIndex(where: { $0.id == branchId }) {
                speculativeBranches[idx].status = .failed
                speculativeBranches[idx].result = error
            }

        case .evaluationStarted:
            for idx in speculativeBranches.indices {
                if speculativeBranches[idx].status == .completed {
                    speculativeBranches[idx].status = .evaluating
                }
            }

        case .evaluationComplete(let winner, let allResults):
            for result in allResults {
                if let idx = speculativeBranches.firstIndex(where: { $0.id == result.id }) {
                    speculativeBranches[idx].evaluationScore = result.evaluationScore
                    speculativeBranches[idx].isWinner = result.isWinner
                    speculativeBranches[idx].status = .completed
                }
            }
            if let winIdx = speculativeBranches.firstIndex(where: { $0.isWinner }) {
                speculativeWinnerIndex = winIdx
            }

            // Post the winning response
            streamingContent = ""
            let winnerMsg = Message(role: .assistant, content: "**Winner: \(winner.strategyName)** (score: \(Int(winner.evaluationScore * 100))%)\n\(winner.evaluationReason.isEmpty ? "" : "\n*\(winner.evaluationReason)*\n")\n---\n\n\(winner.content)")
            currentConversation?.messages.append(winnerMsg)
            syncConversation()

        case .error(let msg):
            errorMessage = msg
            streamingContent = ""
        }
    }

    private func handleOrchestratorEvent(_ event: OrchestratorEvent) {
        switch event {

        case .planReady(let graph):
            // Build initial agent states
            parallelAgents = graph.tasks.map { task in
                ParallelAgentState(
                    id: task.id,
                    agentIndex: task.agentIndex,
                    taskDescription: task.description,
                    taskType: task.taskType,
                    modelName: AIModel(rawValue: task.assignedModel)?.displayName ?? task.assignedModel
                )
            }
            // Post an orchestration plan message into the conversation
            let planLines = graph.tasks.map { t in
                "• **Agent \(t.agentIndex)** [\(t.taskType.displayName) · \(AIModel(rawValue: t.assignedModel)?.displayName ?? t.assignedModel)]: \(t.description)"
            }.joined(separator: "\n")
            let planMsg = Message(role: .assistant, content: "**Parallel Execution Plan** — \(graph.tasks.count) agents:\n\n\(planLines)")
            currentConversation?.messages.append(planMsg)
            orchestrationPlan = planMsg.content
            syncConversation()

        case .taskStarted(let taskId, _, _, _):
            if let idx = parallelAgents.firstIndex(where: { $0.id == taskId }) {
                parallelAgents[idx].status = .running
            }

        case .taskChunk(let taskId, let text):
            if let idx = parallelAgents.firstIndex(where: { $0.id == taskId }) {
                parallelAgents[idx].streamingText += text
            }

        case .taskCompleted(let taskId, let result):
            if let idx = parallelAgents.firstIndex(where: { $0.id == taskId }) {
                parallelAgents[idx].status = .completed
                parallelAgents[idx].result = result
                parallelAgents[idx].streamingText = result
            }

        case .taskFailed(let taskId, let error):
            if let idx = parallelAgents.firstIndex(where: { $0.id == taskId }) {
                parallelAgents[idx].status = .failed
                parallelAgents[idx].result = error
            }

        case .synthesisChunk(let text):
            synthesisingContent += text
            streamingContent = synthesisingContent

        case .finished(let finalResponse):
            streamingContent = ""
            synthesisingContent = ""
            let finalMsg = Message(role: .assistant, content: finalResponse)
            currentConversation?.messages.append(finalMsg)
            syncConversation()

        case .error(let msg):
            errorMessage = msg
            streamingContent = ""
        }
    }

    /// Returns the active memory stores based on user settings.
    private func activeMemoryStores() -> [ProjectMemoryStore] {
        guard !workingDirectory.isEmpty else { return [] }
        var stores: [ProjectMemoryStore] = []
        let semanticEnabled = UserDefaults.standard.object(forKey: "SemanticMemoryEnabled") as? Bool ?? true
        if semanticEnabled {
            stores.append(SemanticMemoryStore(baseDirectory: workingDirectory))
        }
        // Plain-text store always active for backward compatibility
        stores.append(MemoryStore(baseDirectory: workingDirectory))
        return stores
    }

    private func appendSymbolGraphSummary(to prompt: inout String) {
        let sgs = SymbolGraphService.shared
        guard sgs.symbolCount > 0 else { return }
        let summary = sgs.apiSummary(maxTokens: 3000)
        guard !summary.contains("No symbol graph loaded") else { return }
        prompt += "\n\n# Project Symbol Graph\n\n" + summary
    }

    private func appendProjectMemory(to prompt: inout String) {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }

        let queryText = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
        for store in activeMemoryStores() {
            if let block = store.memoryBlock(for: queryText) {
                prompt += block
                return
            }
        }
    }

    /// Appends temporal code intelligence summary (hotspots, coupling, decay) to the system prompt.
    private func appendTemporalIntelligence(to prompt: inout String) {
        guard !workingDirectory.isEmpty else { return }
        if let snapshot = TemporalCodeIntelligenceService.shared.snapshot {
            let summary = snapshot.promptSummary(maxTokens: 800)
            if !summary.isEmpty {
                prompt += "\n\n" + summary
            }
        }
    }

    /// Appends active intent context (cross-session goal continuity) to the system prompt.
    private func appendIntentContext(to prompt: inout String) {
        guard let intent = intentContinuity.activeIntent else { return }
        prompt += "\n\n" + intent.promptFragment
    }

    /// Appends confidence calibration warning when confidence is low.
    private func appendConfidenceWarning(to prompt: inout String) {
        if let fragment = confidenceCalibration.lowConfidencePromptFragment() {
            prompt += "\n\n" + fragment
        }
    }

    private func saveToProjectMemoryIfEnabled() {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }
        let msgs = currentConversation?.messages ?? []
        guard let lastAssistant = msgs.last(where: { $0.role == .assistant }),
              let lastUser = msgs.last(where: { $0.role == .user }) else { return }

        let toolSummary = buildToolCallSummary(from: msgs)
        let convId = currentConversation?.id.uuidString ?? ""
        for store in activeMemoryStores() {
            store.addEntry(
                conversationId: convId,
                userMessage: lastUser.content,
                assistantContent: lastAssistant.content,
                toolCallSummary: toolSummary
            )
        }
    }

    /// Build a compact summary of tool calls from conversation messages.
    /// e.g. "Edited 3 files (foo.swift, bar.ts, baz.py), ran tests (passed), committed"
    func buildToolCallSummary(from messages: [Message]) -> String {
        var toolCounts: [String: Int] = [:]
        var filePaths: [String] = []
        var commandResults: [String] = []

        for msg in messages {
            guard msg.role == .assistant, let calls = msg.toolCalls else { continue }
            for call in calls {
                toolCounts[call.name, default: 0] += 1
                if let data = call.arguments.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let path = args["path"] as? String {
                        let name = (path as NSString).lastPathComponent
                        if !filePaths.contains(name) { filePaths.append(name) }
                    }
                    if let cmd = args["command"] as? String {
                        let short = cmd.components(separatedBy: " ").first ?? cmd
                        if !commandResults.contains(short) { commandResults.append(short) }
                    }
                }
            }
        }

        guard !toolCounts.isEmpty else { return "" }

        var parts: [String] = []
        let editTools = ["edit_file", "write_file", "create_file", "append_file"]
        let editCount = editTools.compactMap { toolCounts[$0] }.reduce(0, +)
        if editCount > 0 {
            let fileList = filePaths.prefix(5).joined(separator: ", ")
            parts.append("Edited \(editCount) file\(editCount == 1 ? "" : "s")\(fileList.isEmpty ? "" : " (\(fileList))")")
        }
        if let readCount = toolCounts["read_file"].map({ $0 + (toolCounts["batch_read_files"] ?? 0) }), readCount > 0 {
            parts.append("Read \(readCount) file\(readCount == 1 ? "" : "s")")
        }
        let searchTools = ["search_files", "grep_search", "find_and_replace"]
        let searchCount = searchTools.compactMap { toolCounts[$0] }.reduce(0, +)
        if searchCount > 0 { parts.append("Searched \(searchCount)x") }
        if let n = toolCounts["run_command"], n > 0 {
            let cmds = commandResults.prefix(3).joined(separator: ", ")
            parts.append("Ran \(n) command\(n == 1 ? "" : "s")\(cmds.isEmpty ? "" : " (\(cmds))")")
        }
        if let n = toolCounts["run_tests"], n > 0 { parts.append("Ran tests") }
        if let n = toolCounts["git_commit"], n > 0 { parts.append("Committed") }
        if let n = toolCounts["web_search"], n > 0 { parts.append("Web search \(n)x") }
        if let n = toolCounts["delete_file"], n > 0 { parts.append("Deleted \(n) file\(n == 1 ? "" : "s")") }

        return parts.joined(separator: ", ")
    }


    // MARK: - Retry Logic

    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        if attempt > 3 { return false }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(urlError.code)
        }
        if let serviceError = error as? OpenRouterService.ServiceError {
            if case .apiError(let code, _) = serviceError {
                return [429, 500, 502, 503, 504].contains(code)
            }
        }
        return false
    }

    private func retryDelay(attempt: Int) -> Double {
        return Double(min(attempt * attempt, 20))
    }

    // MARK: - Simple Intent Detection

    /// Returns true if the message is short and conversational (no coding intent).
    /// Used to skip the full agent loop and do a single fast LLM call instead.
    func isSimpleConversationalMessage(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard text.count < 50 else { return false }
        // Contains file paths
        if lower.contains("/") || lower.contains("\\") { return false }
        // Contains code blocks
        if lower.contains("```") { return false }
        // Coding keywords that signal agent work
        let codingKeywords = [
            "fix", "build", "create", "file", "debug", "implement", "refactor",
            "test", "deploy", "write", "code", "function", "class", "error",
            "bug", "install", "run", "compile", "delete", "move", "rename",
            "update", "add", "remove", "change", "modify", "edit", "search",
            "find", "replace", "git", "commit", "push", "pull", "merge",
            "docker", "npm", "pip", "brew", "cargo", "swift", "make",
            "database", "api", "server", "endpoint", "route", "component",
            "module", "package", "import", "export", "migrate", "scaffold",
            "generate", "config", "setup", "init", "analyze", "lint", "format"
        ]
        for keyword in codingKeywords {
            // Match whole word boundaries
            let pattern = "\\b\(keyword)\\b"
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return false
            }
        }
        return true
    }

    /// Fast single-turn LLM call with no tools (for simple conversational messages).
    internal func runFastReply() async {
        let apiMessages = buildAPIMessages()
        var textBuffer = ""

        let stream: AsyncThrowingStream<StreamEvent, Error>
        if let token = PlatformService.authToken, !token.isEmpty {
            stream = openRouterService.streamMessageViaBackend(
                messages: apiMessages,
                model: effectiveModel.rawValue,
                backendBaseURL: PlatformService.baseURL,
                authToken: token,
                tools: []
            )
        } else {
            stream = aiService.streamMessage(
                messages: apiMessages,
                tools: []
            )
        }

        var lastStreamPublishTime = Date()
        let streamThrottleInterval: TimeInterval = 0.025 // 40Hz for better responsiveness
        let streamThrottleChars = 40 // Reduced for faster updates
        var lastPublishedLength = 0

        do {
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .text(let chunk):
                    textBuffer += chunk
                    let now = Date()
                    let elapsed = now.timeIntervalSince(lastStreamPublishTime)
                    let charGrowth = textBuffer.count - lastPublishedLength
                    let shouldPublish = elapsed >= streamThrottleInterval || charGrowth >= streamThrottleChars || chunk.contains("\n")
                    if shouldPublish {
                        lastStreamPublishTime = now
                        lastPublishedLength = textBuffer.count
                        streamingContent = textBuffer
                        FrameLoopService.shared.markStreaming(for: 0.5) // Use streaming mode
                    }
                case .toolCallDelta:
                    break
                case .done:
                    break
                }
            }
            streamingContent = textBuffer
        } catch is CancellationError {
            streamingContent = ""
            return
        } catch {
            if !textBuffer.isEmpty {
                let partial = Message(role: .assistant, content: textBuffer + "\n\n(Partial response: stream interrupted.)")
                currentConversation?.messages.append(partial)
                syncConversation()
            }
            errorMessage = friendlyErrorMessage(error)
            streamingContent = ""
            return
        }

        if !textBuffer.isEmpty {
            let reply = Message(role: .assistant, content: textBuffer)
            currentConversation?.messages.append(reply)
            streamingContent = ""
            syncConversation()
            flushSync()
        }
    }

    // MARK: - Helpers

    private func buildAPIMessages(cachedPrompt: String? = nil) -> [Message] {
        var apiMessages: [Message] = []
        var prompt = cachedPrompt ?? effectiveAgentConfig().prompt

        // Apple Intelligence: inject intent + sentiment context
        var intelContext: [String] = []
        if lastUserIntent != .general {
            intelContext.append("[User intent: \(lastUserIntent.rawValue)]")
        }
        if lastUserSentiment == .frustrated {
            intelContext.append("[User appears frustrated — be empathetic, acknowledge the difficulty, and focus on solutions.]")
        }
        if !intelContext.isEmpty {
            prompt += "\n\n" + intelContext.joined(separator: "\n")
        }

        if !prompt.isEmpty {
            apiMessages.append(Message(role: .system, content: prompt))
        }

        if let conversation = currentConversation {
            let msgs = conversation.messages
            let estimatedTokens = msgs.reduce(0) { $0 + estimateTokens($1.content) }
            let contextLimit = selectedModel.contextWindow - selectedModel.maxOutput - 2000

            if estimatedTokens > contextLimit {
                apiMessages.append(contentsOf: truncateMessages(msgs, targetTokens: contextLimit))
            } else {
                apiMessages.append(contentsOf: msgs)
            }
        }
        return apiMessages
    }

    /// Estimate token count for a message, accounting for role overhead and tool call metadata.
    private func estimateTokens(_ text: String) -> Int {
        // ~4 chars per token for English text, plus overhead per message
        max(1, text.count / 4) + 4
    }

    /// Estimate tokens for an entire message including tool calls.
    private func estimateMessageTokens(_ msg: Message) -> Int {
        var tokens = estimateTokens(msg.content)
        if let toolCalls = msg.toolCalls {
            for tc in toolCalls {
                tokens += estimateTokens(tc.name) + estimateTokens(tc.arguments) + 10
            }
        }
        return tokens
    }

    /// Truncate tool result content that is excessively large.
    /// Keeps the first and last portions so the model retains key info.
    func truncateToolResult(_ result: String, maxChars: Int = 8000) -> String {
        guard result.count > maxChars else { return result }
        let headSize = maxChars * 3 / 4
        let tailSize = maxChars / 4
        let head = String(result.prefix(headSize))
        let tail = String(result.suffix(tailSize))
        let omitted = result.count - headSize - tailSize
        return head + "\n\n[... \(omitted) characters omitted ...]\n\n" + tail
    }

    private func truncateMessages(_ messages: [Message], targetTokens: Int) -> [Message] {
        // 1. Always keep system messages (they carry instructions)
        let systemMsgs = messages.filter { $0.role == .system }
        let nonSystemMsgs = messages.filter { $0.role != .system }

        let systemTokens = systemMsgs.reduce(0) { $0 + estimateMessageTokens($1) }
        let budget = targetTokens - systemTokens
        guard budget > 0 else {
            // Even system prompt is too large; keep just the last system message
            return Array(systemMsgs.suffix(1))
        }

        // 2. Walk backwards through non-system messages, fitting as many as possible
        var result: [Message] = []
        var tokenCount = 0

        for msg in nonSystemMsgs.reversed() {
            var m = msg
            var msgTokens = estimateMessageTokens(m)

            // Truncate very large tool results to save budget
            if m.role == .tool && m.content.count > 8000 {
                m = Message(role: .tool, content: truncateToolResult(m.content), toolCallId: m.toolCallId)
                msgTokens = estimateMessageTokens(m)
            }

            if tokenCount + msgTokens > budget { break }
            result.insert(m, at: 0)
            tokenCount += msgTokens
        }

        // 3. Prepend system messages
        let droppedCount = nonSystemMsgs.count - result.count
        if droppedCount > 0 {
            let note = Message(role: .system, content: "[Context note: \(droppedCount) earlier messages were omitted to fit context window. The most recent messages are preserved.]")
            result.insert(note, at: 0)
        }
        return systemMsgs + result
    }

    
    /// Immediately flush any pending conversation save.
    func flushSync() {
        guard syncDirty else { return }
        syncDirty = false
        syncDebounceTask?.cancel()
        saveConversations()
    }

    // MARK: - Persistence

    private static var conversationsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(appDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let newURL = appDir.appendingPathComponent("conversations.json")

        if !FileManager.default.fileExists(atPath: newURL.path) {
            let legacyURL = appSupport
                .appendingPathComponent(legacyAppDirectoryName, isDirectory: true)
                .appendingPathComponent("conversations.json")
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                try? FileManager.default.copyItem(at: legacyURL, to: newURL)
            }
        }
        return newURL
    }

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: Self.conversationsFileURL, options: .atomic)
        } catch {
            GRumpLogger.persistence.error("Failed to save conversations: \(error.localizedDescription)")
        }
    }

    private func loadConversations() {
        let url = Self.conversationsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            GRumpLogger.persistence.error("Failed to load conversations: \(error.localizedDescription)")
        }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut: return "Request timed out. Please retry or choose a faster model."
            case .notConnectedToInternet: return "No internet connection. Check your network and try again."
            case .networkConnectionLost: return "Network connection lost. Please retry."
            case .cannotConnectToHost: return "Could not connect to server. Check your connection."
            case .dnsLookupFailed: return "DNS lookup failed. Check your internet connection."
            default: return "Network error: \(urlError.localizedDescription)"
            }
        }
        if let serviceError = error as? OpenRouterService.ServiceError {
            if case .apiError(let code, let msg) = serviceError {
                if code == 503 { return "Service temporarily unavailable. Please retry in a moment." }
                if code == 429 { return "Rate limit reached. Please wait a moment and try again." }
                if let m = msg { return m }
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Export / Import

    /// Returns a Markdown string for a single conversation (User/Assistant sections, code blocks preserved).
    func markdownString(for conversation: Conversation) -> String {
        var sections: [String] = []
        for message in conversation.messages where message.role != .system {
            switch message.role {
            case .user:
                sections.append("## User\n\n" + message.content)
            case .assistant:
                sections.append("## Assistant\n\n" + message.content)
            case .tool:
                sections.append("*(Tool result)*\n\n" + message.content)
            case .system:
                break
            }
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    #if os(macOS)
    /// Presents the save panel and exports conversations as JSON. Call from main thread.
    func runExportJSONPanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "g-rump-conversations.json"
        panel.message = "Export conversations as JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportConversations(to: url, conversationIds: nil)
    }

    /// Presents the save panel and exports conversations as Markdown. If onlyCurrent is true, exports only the current conversation. Call from main thread.
    func runExportMarkdownPanel(onlyCurrent: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let defaultName = onlyCurrent ? ((currentConversation?.title ?? "conversation").grumpSanitizedForFilename + ".md") : "g-rump-conversations.md"
        panel.nameFieldStringValue = defaultName
        panel.message = onlyCurrent ? "Export current conversation as Markdown" : "Export conversations as Markdown"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ids = onlyCurrent ? currentConversation.map { Set([$0.id]) } : nil
        exportConversationsAsMarkdown(to: url, conversationIds: ids)
    }

    /// Presents the open panel and imports conversations from JSON. Call from main thread.
    func runImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a conversations JSON file to import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importConversations(from: url)
    }
    #endif

    /// Exports one or more conversations as a single Markdown file.
    func exportConversationsAsMarkdown(to url: URL, conversationIds: Set<UUID>?) {
        let list = conversationIds.map { ids in conversations.filter { ids.contains($0.id) } } ?? conversations
        let parts = list.map { conv in
            "# \(conv.title)\n\n" + markdownString(for: conv)
        }
        let markdown = parts.joined(separator: "\n\n---\n\n")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            importExportMessage = "Exported \(list.count) conversation\(list.count == 1 ? "" : "s") as Markdown."
        } catch {
            GRumpLogger.general.error("Export as Markdown failed: \(error.localizedDescription)")
            importExportMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    func exportConversations(to url: URL, conversationIds: Set<UUID>?) {
        let list = conversationIds.map { ids in conversations.filter { ids.contains($0.id) } } ?? conversations
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: url, options: .atomic)
        } catch {
            GRumpLogger.general.error("Export failed: \(error.localizedDescription)")
        }
    }

    func importConversations(from url: URL) {
        importExportMessage = nil
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([Conversation].self, from: data)
            let count = imported.count
            conversations.append(contentsOf: imported)
            saveConversations()
            importExportMessage = "Imported \(count) conversation\(count == 1 ? "" : "s")."
        } catch {
            importExportMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Retry

    func retryLastMessage() {
        guard var conversation = currentConversation else { return }
        while let last = conversation.messages.last, last.role == .assistant || last.role == .tool {
            conversation.messages.removeLast()
        }
        currentConversation = conversation
        syncConversation()

        isLoading = true
        errorMessage = nil
        streamingContent = ""
        activeToolCalls = []

        streamTask?.cancel()
        streamTask = Task {
            await runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }
    
    // MARK: - Tool Progress Helpers
    
    private func getInitialStep(for toolName: String) -> String {
        switch toolName {
        case "read_file", "batch_read_files":
            return "Reading file..."
        case "write_file", "edit_file", "create_file":
            return "Writing file..."
        case "run_command", "system_run":
            return "Executing command..."
        case "search_files", "grep_search":
            return "Searching..."
        case "web_search":
            return "Searching web..."
        case "list_directory", "tree_view":
            return "Listing directory..."
        default:
            return "Processing..."
        }
    }
    
    private func getEstimatedSteps(for toolName: String) -> Int {
        switch toolName {
        case "read_file", "write_file", "edit_file":
            return 3 // Read -> Process -> Write
        case "run_command", "system_run":
            return 2 // Execute -> Process result
        case "search_files", "grep_search":
            return 2 // Search -> Process results
        case "web_search":
            return 3 // Search -> Fetch -> Process
        case "batch_read_files":
            return 4 // Discover -> Read multiple -> Process -> Format
        default:
            return 2
        }
    }
}

#if os(macOS)
private extension String {
    var grumpSanitizedForFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let s = unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .map(String.init)
            .joined()
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "conversation" : String(trimmed.prefix(80))
    }
}
#endif
