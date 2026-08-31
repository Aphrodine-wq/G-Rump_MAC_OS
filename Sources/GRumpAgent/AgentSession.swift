import Foundation
import GRumpCore
import GRumpTools
import GRumpProviders

public actor AgentSession {
    public let id: String
    private let model: any ModelProvider
    private let registry: ToolRegistry
    private let executor: ToolExecutor
    private let memory: any MemoryStore
    private let skills: any SkillStore
    private let context: ExecutionContext
    private let approvalProvider: any ApprovalProvider
    private var history: [AgentMessage]
    private var activeTask: Task<Void, Never>?

    public init(id: String = UUID().uuidString, model: any ModelProvider, registry: ToolRegistry,
                memory: any MemoryStore, skills: any SkillStore, approvalProvider: any ApprovalProvider,
                context: ExecutionContext, policy: PolicyEngine = .init()) {
        self.id = id; self.model = model; self.registry = registry; self.memory = memory; self.skills = skills
        self.context = context; self.approvalProvider = approvalProvider
        self.executor = ToolExecutor(registry: registry, policy: policy)
        self.history = []
    }

    public func run(_ prompt: String) -> AsyncStream<AgentEvent> {
        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream()
        let task = Task {
                defer { activeTask = nil }
                do {
                    let approval = EventingApprovalProvider(base: approvalProvider) { request in
                        continuation.yield(.approvalRequested(request))
                    }
                    let executionContext = context.replacingApprovalProvider(approval)
                    let root = context.workspaceRoots.first ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    if history.count > 80 { history = Array(history.suffix(80)) }
                    var messages = try await memory.context(for: root) + history
                    let enabledSkills = try await skills.enabledSkills(for: root)
                    if !enabledSkills.isEmpty {
                        messages.append(AgentMessage(role: .system, content: enabledSkills.map { "# \($0.name)\n\($0.instructions)" }.joined(separator: "\n\n")))
                    }
                    let user = AgentMessage(role: .user, content: prompt)
                    messages.append(user); history.append(user)
                    if await memory.isEnabled { try await memory.append(user, workspace: root) }

                    for _ in 0..<64 {
                        let request = ModelRequest(messages: messages, tools: await registry.definitions())
                        var invocations: [ToolInvocation] = []
                        var completion: AgentMessage?
                        var lastError: Error?
                        for attempt in 0..<3 {
                            do {
                                for try await event in model.stream(request) {
                                    switch event {
                                    case .text(let delta): continuation.yield(.text(delta: delta))
                                    case .reasoning(let delta): continuation.yield(.reasoning(delta: delta))
                                    case .toolInvocation(let invocation): invocations.append(invocation)
                                    case .completed(let message): completion = message
                                    }
                                }
                                lastError = nil
                                break
                            } catch {
                                lastError = error
                                if attempt < 2 {
                                    continuation.yield(.reasoning(delta: "Model request failed; retrying (\(attempt + 1)/2)."))
                                }
                            }
                        }
                        if let lastError { throw lastError }

                        if let completion {
                            messages.append(completion); history.append(completion)
                            if await memory.isEnabled { try await memory.append(completion, workspace: root) }
                        }
                        guard !invocations.isEmpty else {
                            let message = completion ?? AgentMessage(role: .assistant, content: "")
                            continuation.yield(.completed(message)); continuation.finish(); return
                        }

                        for invocation in invocations {
                            continuation.yield(.toolStarted(invocation))
                            let message = AgentMessage(role: .assistant, content: "", toolInvocation: invocation)
                            messages.append(message); history.append(message)
                        }
                        let executor = self.executor
                        let indexedResults = await withTaskGroup(of: (Int, ToolResult).self, returning: [(Int, ToolResult)].self) { group in
                            for (index, invocation) in invocations.enumerated() {
                                group.addTask { (index, await executor.execute(invocation, context: executionContext)) }
                            }
                            var results: [(Int, ToolResult)] = []
                            for await result in group { results.append(result) }
                            return results.sorted { $0.0 < $1.0 }
                        }
                        for (_, result) in indexedResults {
                            continuation.yield(.toolCompleted(result))
                            let message = AgentMessage(role: .tool, content: result.content.compactMap(\.text).joined(separator: "\n"), toolResult: result)
                            messages.append(message); history.append(message)
                        }
                    }
                    continuation.yield(.failed("Agent exceeded the 64-turn safety limit")); continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.cancelled); continuation.finish()
                } catch {
                    continuation.yield(.failed(String(describing: error))); continuation.finish()
                }
        }
        activeTask = task
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    public func cancel() async {
        activeTask?.cancel()
        await context.cancellation.cancel()
    }
}

private struct EventingApprovalProvider: ApprovalProvider {
    let base: any ApprovalProvider
    let notify: @Sendable (ApprovalRequest) -> Void
    func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision {
        notify(request)
        return await base.requestApproval(request)
    }
}
