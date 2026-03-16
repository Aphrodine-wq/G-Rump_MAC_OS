import Foundation
import SwiftUI

// MARK: - Parallel & Speculative Agent Loops Extension
//
// Contains the parallel multi-agent loop, speculative branching loop,
// and their respective event handlers.
// Extracted from ChatViewModel.swift for maintainability.

extension ChatViewModel {

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

    // MARK: - Speculative Branch Event Handler

    func handleSpeculativeBranchEvent(_ event: SpeculativeBranchEvent) {
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

    // MARK: - Orchestrator Event Handler

    func handleOrchestratorEvent(_ event: OrchestratorEvent) {
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
}
