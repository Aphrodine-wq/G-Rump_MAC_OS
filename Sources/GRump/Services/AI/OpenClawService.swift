import Foundation
import os
import Combine

// MARK: - OpenClaw Gateway Service
//
// Connects to OpenClaw's WebSocket gateway as a device node.
// Receives coding tasks from any channel (Slack, Discord, iMessage, etc.)
// and routes them through G-Rump's agent system for execution.
// Streams responses back through the gateway.

@MainActor
final class OpenClawService: ObservableObject {
    static let shared = OpenClawService()

    // MARK: - Persistence Keys

    private enum Keys {
        static let enabled = "OpenClaw_Enabled"
        static let gatewayURL = "OpenClaw_GatewayURL"
    }

    // MARK: - Published State

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
    }
    @Published var connectionState: OpenClawConnectionState = .disconnected
    @Published var activeSessions: [OpenClawSession] = []
    @Published var gatewayURL: String {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: Keys.gatewayURL) }
    }

    // MARK: - Private

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var readerTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.grump.openclaw", category: "Gateway")
    private let costControl = OpenClawCostControl.shared
    private let nodeId = UUID().uuidString

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Keys.enabled)
        gatewayURL = defaults.string(forKey: Keys.gatewayURL) ?? "ws://127.0.0.1:18789"
    }

    // MARK: - Lifecycle

    func connect() {
        guard isEnabled else {
            logger.info("OpenClaw integration is disabled")
            return
        }
        guard connectionState != .connected && connectionState != .connecting else { return }

        connectionState = .connecting
        logger.info("Connecting to OpenClaw gateway at \(self.gatewayURL)")

        guard let url = URL(string: gatewayURL) else {
            connectionState = .error("Invalid gateway URL")
            return
        }

        // Enforce wss:// for non-localhost connections
        let host = url.host ?? ""
        let isLocalhost = host == "127.0.0.1" || host == "localhost" || host == "::1"
        guard url.scheme == "ws" || url.scheme == "wss" else {
            connectionState = .error("Gateway URL must use ws:// or wss:// scheme")
            return
        }
        if !isLocalhost && url.scheme != "wss" {
            connectionState = .error("Remote connections require wss:// (encrypted). Use wss:// for non-localhost URLs.")
            return
        }

        let session = URLSession(configuration: .default)
        urlSession = session
        let ws = session.webSocketTask(with: url)
        webSocket = ws
        ws.resume()

        // Start reading messages
        readerTask = Task { [weak self] in
            await self?.readMessages()
        }

        // Register as a device node
        Task { [weak self] in
            await self?.registerNode()
        }

        // Start heartbeat
        heartbeatTask = Task { [weak self] in
            await self?.heartbeatLoop()
        }
    }

    func disconnect() {
        readerTask?.cancel()
        heartbeatTask?.cancel()
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        connectionState = .disconnected
        activeSessions.removeAll()
        logger.info("Disconnected from OpenClaw gateway")
    }

    // MARK: - Node Registration

    private func registerNode() async {
        let capabilities = buildCapabilities()
        let message: [String: Any] = [
            "type": "node.register",
            "nodeId": nodeId,
            "name": "G-Rump",
            "version": "1.0.0",
            "capabilities": capabilities,
            "costPolicy": costControl.currentPolicy()
        ]
        await send(message)
    }

    private func buildCapabilities() -> [String: Any] {
        return [
            "agent": true,
            "tools": true,
            "streaming": true,
            "models": AIModel.allCases.map(\.rawValue),
            "maxConcurrentSessions": 3
        ] as [String: Any]
    }

    // MARK: - Message Loop

    private func readMessages() async {
        guard let ws = webSocket else { return }

        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        connectionState = .error(error.localizedDescription)
                    }
                    logger.error("WebSocket read error: \(error.localizedDescription)")
                    // Attempt reconnect after delay
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled && isEnabled {
                        await MainActor.run { connect() }
                    }
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "node.registered":
            connectionState = .connected
            logger.info("Registered as OpenClaw device node")

        case "session.start":
            await handleSessionStart(json)

        case "session.message":
            await handleSessionMessage(json)

        case "session.end":
            await handleSessionEnd(json)

        case "node.ping":
            await send(["type": "node.pong", "nodeId": nodeId])

        case "error":
            let msg = json["message"] as? String ?? "Unknown error"
            logger.error("OpenClaw error: \(msg)")

        default:
            logger.debug("Unknown OpenClaw message type: \(type)")
        }
    }

    // MARK: - Session Handling

    private func handleSessionStart(_ json: [String: Any]) async {
        guard let sessionId = json["sessionId"] as? String else { return }

        // Cost control check
        guard costControl.canStartSession() else {
            await send([
                "type": "session.reject",
                "sessionId": sessionId,
                "reason": "Credit budget exceeded"
            ])
            return
        }

        // Rate limit check
        guard costControl.checkRateLimit() else {
            await send([
                "type": "session.reject",
                "sessionId": sessionId,
                "reason": "Rate limit exceeded"
            ])
            return
        }

        let channel = json["channel"] as? String ?? "unknown"
        let user = json["user"] as? String ?? "unknown"
        let session = OpenClawSession(
            id: sessionId,
            channel: channel,
            user: user,
            startedAt: Date()
        )
        activeSessions.append(session)
        costControl.sessionStarted(sessionId: sessionId)

        await send([
            "type": "session.accepted",
            "sessionId": sessionId,
            "nodeId": nodeId
        ])

        logger.info("Started OpenClaw session \(sessionId) from \(channel)/\(user)")
    }

    private func handleSessionMessage(_ json: [String: Any]) async {
        guard let sessionId = json["sessionId"] as? String,
              let content = json["content"] as? String else { return }

        // Cost control per-message check
        guard costControl.canProcessMessage(sessionId: sessionId) else {
            await send([
                "type": "session.response",
                "sessionId": sessionId,
                "content": "Session credit budget exceeded. Please start a new session.",
                "done": true
            ])
            return
        }

        // Model allowlist check
        let requestedModel = json["model"] as? String
        if let model = requestedModel, !costControl.isModelAllowed(model) {
            await send([
                "type": "session.response",
                "sessionId": sessionId,
                "content": "Model '\(model)' is not allowed for OpenClaw sessions. Allowed models: \(costControl.allowedModels.joined(separator: ", "))",
                "done": true
            ])
            return
        }

        // Route through G-Rump's agent system
        // This is where the message enters the normal ChatViewModel flow
        costControl.messageProcessed(sessionId: sessionId)

        // Update session tracking counters
        if let idx = activeSessions.firstIndex(where: { $0.id == sessionId }) {
            activeSessions[idx].messageCount += 1
            activeSessions[idx].creditsUsed += 1.0
        }

        // Stream the response back
        await send([
            "type": "session.response",
            "sessionId": sessionId,
            "content": "Processing your request...",
            "done": false
        ])

        // The actual ChatViewModel integration happens through the delegate pattern
        // defined below. The view model subscribes to OpenClaw sessions and processes them.
        NotificationCenter.default.post(
            name: .openClawMessageReceived,
            object: nil,
            userInfo: [
                "sessionId": sessionId,
                "content": content,
                "model": requestedModel as Any
            ]
        )
    }

    private func handleSessionEnd(_ json: [String: Any]) async {
        guard let sessionId = json["sessionId"] as? String else { return }
        activeSessions.removeAll { $0.id == sessionId }
        costControl.sessionEnded(sessionId: sessionId)
        logger.info("Ended OpenClaw session \(sessionId)")
    }

    // MARK: - Send Response

    func sendResponse(sessionId: String, content: String, done: Bool) async {
        await send([
            "type": "session.response",
            "sessionId": sessionId,
            "content": content,
            "done": done
        ])
    }

    func sendToolUse(sessionId: String, toolName: String, status: String) async {
        await send([
            "type": "session.tool_use",
            "sessionId": sessionId,
            "tool": toolName,
            "status": status
        ])
    }

    // MARK: - Heartbeat

    private func heartbeatLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            guard !Task.isCancelled else { break }
            await send(["type": "node.heartbeat", "nodeId": nodeId])
        }
    }

    // MARK: - Transport

    private func send(_ message: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else { return }
        do {
            try await webSocket?.send(.string(text))
        } catch {
            logger.error("Failed to send WebSocket message: \(error.localizedDescription)")
        }
    }
}

// MARK: - Types

enum OpenClawConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.clockwise"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

struct OpenClawSession: Identifiable, Equatable {
    let id: String
    let channel: String
    let user: String
    let startedAt: Date
    var messageCount: Int = 0
    var creditsUsed: Double = 0
}

// MARK: - Notification

extension Notification.Name {
    static let openClawMessageReceived = Notification.Name("openClawMessageReceived")
}
