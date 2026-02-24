import Foundation

// MARK: - Streaming Extension
extension ChatViewModel {
    
    /// Send a message and start streaming response
    func sendMessage() {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isAIProviderConfigured && apiKey.trimmingCharacters(in: .whitespaces).isEmpty && platformUser == nil && !localOllamaReady {
            errorMessage = "No provider configured. Open Settings (\u{2318},) to add an API key, or start Ollama locally."
            return
        }

        let userMessage = Message(role: .user, content: trimmed)
        currentConversation?.messages.append(userMessage)
        currentConversation?.updateTitle()
        syncConversation()

        // Apple Intelligence: classify intent and detect frustration
        let intel = AppleIntelligenceService.shared
        let intent = intel.classifyUserIntent(trimmed)
        let frustrated = intel.isUserFrustrated(trimmed)
        if frustrated {
            // Inject empathetic context for the agent
            lastUserSentiment = .frustrated
        } else {
            lastUserSentiment = .neutral
        }
        lastUserIntent = intent

        // Enable undo send for 5 seconds
        lastSentText = trimmed
        undoSendAvailable = true
        undoSendTask?.cancel()
        undoSendTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            undoSendAvailable = false
            lastSentText = nil
        }

        userInput = ""
        if let id = currentConversation?.id {
            saveDraft("", forConversationId: id)
        }
        startStreaming(task: trimmed)
    }
    
    /// Start streaming with appropriate agent mode
    private func startStreaming(task: String) {
        isLoading = true
        isPaused = false
        errorMessage = nil
        streamingContent = ""
        activeToolCalls = []
        parallelAgents = []
        orchestrationPlan = nil
        synthesisingContent = ""

        streamTask?.cancel()
        streamTask = Task {
            if self.agentMode == .parallel {
                await self.runParallelAgentLoop(userTask: task)
            } else if self.agentMode == .standard && isSimpleConversationalMessage(task) {
                await self.runFastReply()
            } else {
                await self.runAgentLoop()
            }
            streamTask = nil
            isLoading = false
        }
    }
    
    /// Stop the current generation
    func stopGeneration() {
        streamTask?.cancel()
        isLoading = false
        isPaused = false
    }

    /// Pause the agent mid-run. Conversation state is preserved. Call resumeAgent() to continue.
    func pauseGeneration() {
        streamTask?.cancel()
        isLoading = false
        isPaused = true
    }

    /// Resume the agent after a pause. Continues from the current conversation state.
    func resumeAgent() {
        guard isPaused, currentConversation != nil else { return }
        isPaused = false
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
    
    /// Restart streaming with current conversation state
    func restartStreaming() {
        orchestrationPlan = nil
        synthesisingContent = ""
        streamTask?.cancel()
        streamTask = Task {
            await self.runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }
}
