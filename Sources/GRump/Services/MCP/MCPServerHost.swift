import Foundation
import GRumpKit

#if os(macOS)
import os

/// GUI lifecycle facade for the shared GRumpKit MCP server.
/// Schemas, dispatch, authentication, and protocol handling live in GRumpMCP.
actor MCPServerHost {
    static let shared = MCPServerHost()

    private(set) var isRunning = false
    private(set) var port: UInt16?
    var workspaceRoot: String = FileManager.default.currentDirectoryPath

    private var transport: HTTPMCPTransport?
    private var serverTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.grump.mcp", category: "ServerHost")

    func start(port: UInt16 = 18_790) async throws {
        guard !isRunning else { return }
        let root = URL(fileURLWithPath: workspaceRoot).standardizedFileURL
        let runtime = try await HarnessRuntime.create(workspace: root)
        let server = GRumpMCPServer(registry: runtime.registry, executor: runtime.executor,
                                    context: runtime.context, memory: runtime.memory, skills: runtime.skills)
        let transport = HTTPMCPTransport()
        let token = try Self.loadOrCreateToken(paths: GRumpPaths())

        self.transport = transport
        self.port = port
        self.isRunning = true
        self.serverTask = Task { [weak self] in
            do {
                try await transport.serve(server, configuration: .init(port: Int(port), bearerToken: token))
            } catch is CancellationError {
                // Normal shutdown.
            } catch {
                self?.logger.error("MCP server failed: \(error.localizedDescription)")
            }
            await self?.didStop()
        }
        logger.info("MCP server starting on 127.0.0.1:\(port)")
    }

    func stop() async {
        serverTask?.cancel()
        serverTask = nil
        if let transport { try? await transport.stop() }
        didStop()
        logger.info("MCP server stopped")
    }

    private func didStop() {
        transport = nil
        isRunning = false
        port = nil
    }

    private static func loadOrCreateToken(paths: GRumpPaths) throws -> String {
        let file = paths.configDirectory.appendingPathComponent("mcp-token")
        if let existing = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty { return existing }
        try FileManager.default.createDirectory(at: paths.configDirectory, withIntermediateDirectories: true)
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        try Data((token + "\n").utf8).write(to: file, options: .atomic)
        return token
    }
}
#endif
