import Foundation
import GRumpCore

public enum AgentHandleStatus: Codable, Sendable, Equatable { case running, completed, cancelled, failed(String) }

public actor AgentHandleStore {
    private struct Entry { let session: AgentSession; var status: AgentHandleStatus; var events: [AgentEvent]; var task: Task<Void, Never>? }
    private var entries: [String: Entry] = [:]
    public init() {}

    @discardableResult
    public func start(session: AgentSession, prompt: String) async -> String {
        let handle = session.id
        entries[handle] = Entry(session: session, status: .running, events: [], task: nil)
        let task = Task { [weak self] in
            for await event in await session.run(prompt) {
                await self?.record(event, handle: handle)
            }
        }
        entries[handle]?.task = task
        return handle
    }

    public func continueAgent(handle: String, prompt: String) async throws {
        guard var entry = entries[handle] else { throw ToolError(code: .invalidArguments, message: "Unknown agent handle") }
        entry.status = .running
        entry.task = Task { [weak self, session = entry.session] in
            for await event in await session.run(prompt) { await self?.record(event, handle: handle) }
        }
        entries[handle] = entry
    }
    public func status(handle: String) -> AgentHandleStatus? { entries[handle]?.status }
    public func result(handle: String) -> [AgentEvent]? { entries[handle]?.events }
    public func cancel(handle: String) async throws {
        guard var entry = entries[handle] else { throw ToolError(code: .invalidArguments, message: "Unknown agent handle") }
        entry.task?.cancel(); await entry.session.cancel(); entry.status = .cancelled; entries[handle] = entry
    }
    private func record(_ event: AgentEvent, handle: String) {
        guard var entry = entries[handle] else { return }
        entry.events.append(event)
        switch event { case .completed: entry.status = .completed; case .cancelled: entry.status = .cancelled; case .failed(let message): entry.status = .failed(message); default: break }
        entries[handle] = entry
    }
}
