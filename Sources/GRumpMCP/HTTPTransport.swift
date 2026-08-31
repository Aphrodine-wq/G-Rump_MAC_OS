import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import GRumpCore

public struct HTTPMCPConfiguration: Sendable {
    public let host: String
    public let port: Int
    public let bearerToken: String
    public init(host: String = "127.0.0.1", port: Int = 18_790, bearerToken: String) {
        self.host = host; self.port = port; self.bearerToken = bearerToken
    }
}

public final class HTTPMCPTransport: @unchecked Sendable {
    private let group: MultiThreadedEventLoopGroup
    private var channel: Channel?

    public init() { group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount) }

    public func serve(_ server: GRumpMCPServer, configuration: HTTPMCPConfiguration) async throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPMCPHandler(server: server, configuration: configuration))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
        channel = try await bootstrap.bind(host: configuration.host, port: configuration.port).get()
        try await channel?.closeFuture.get()
    }

    public func stop() async throws {
        try await channel?.close().get()
        try await group.shutdownGracefully()
    }

    deinit { try? group.syncShutdownGracefully() }
}

private final class HTTPMCPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let server: GRumpMCPServer
    private let configuration: HTTPMCPConfiguration
    private var requestHead: HTTPRequestHead?
    private var body: ByteBuffer?

    init(server: GRumpMCPServer, configuration: HTTPMCPConfiguration) {
        self.server = server; self.configuration = configuration
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head): requestHead = head; body = context.channel.allocator.buffer(capacity: 0)
        case .body(var chunk): body?.writeBuffer(&chunk)
        case .end:
            guard let head = requestHead else { return }
            var buffer = body ?? context.channel.allocator.buffer(capacity: 0)
            let payload = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
            requestHead = nil; body = nil
            let bridge = HTTPContextBridge(context)
            Task {
                let response = await self.process(head: head, body: payload)
                bridge.send(response)
            }
        }
    }

    private func process(head: HTTPRequestHead, body: Data) async -> HTTPResponseValue {
        guard head.uri == "/mcp" else { return .text(status: .notFound, "Not found") }
        guard head.method == .POST else { return .text(status: .methodNotAllowed, "POST required") }
        guard originAllowed(head.headers.first(name: "Origin")) else { return .text(status: .forbidden, "Origin rejected") }
        guard constantTimeEqual(head.headers.first(name: "Authorization") ?? "", "Bearer \(configuration.bearerToken)") else {
            return .text(status: .unauthorized, "Bearer authentication required")
        }
        do {
            let message = try JSONValue.decode(data: body)
            let protocolHint = head.headers.first(name: "MCP-Protocol-Version")
            let negotiated = MCPVersionAdapter.negotiate(protocolHint).rawValue
            guard let response = await server.handle(message, protocolHint: protocolHint) else {
                return .init(status: .accepted, body: Data(), contentType: "application/json")
            }
            if head.headers["Accept"].contains(where: { $0.lowercased().contains("text/event-stream") }) {
                var messages: [JSONValue] = []
                if let token = message["params"]?["_meta"]?["progressToken"] {
                    messages.append(progressNotification(token, progress: 0, message: "Tool started"))
                }
                messages.append(response)
                if message["params"]?["name"]?.stringValue == "grump_tools_activate_pack" {
                    messages.append(["jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": .object([:])])
                }
                if let token = message["params"]?["_meta"]?["progressToken"] {
                    messages.append(progressNotification(token, progress: 1, message: "Tool completed"))
                }
                let frames = try messages.map { "event: message\ndata: \(String(decoding: try $0.encoded(), as: UTF8.self))\n\n" }.joined()
                return .init(status: .ok, body: Data(frames.utf8), contentType: "text/event-stream", protocolVersion: negotiated)
            }
            return .init(status: .ok, body: try response.encoded(), contentType: "application/json", protocolVersion: negotiated)
        } catch {
            let value: JSONValue = ["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": .string("Parse error: \(error)")]]
            return .init(status: .badRequest, body: (try? value.encoded()) ?? Data(), contentType: "application/json")
        }
    }

    private func originAllowed(_ value: String?) -> Bool {
        guard let value else { return true }
        guard let url = URL(string: value), let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8), right = Array(rhs.utf8)
        var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }
        return difference == 0
    }

    private func progressNotification(_ token: JSONValue, progress: Int64, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "method": "notifications/progress", "params": [
            "progressToken": token, "progress": .integer(progress), "total": 1, "message": .string(message)
        ]]
    }
}

private struct HTTPResponseValue: Sendable {
    let status: HTTPResponseStatus
    let body: Data
    let contentType: String
    let protocolVersion: String
    init(status: HTTPResponseStatus, body: Data, contentType: String, protocolVersion: String = MCPProtocolVersion.july2026.rawValue) {
        self.status = status; self.body = body; self.contentType = contentType; self.protocolVersion = protocolVersion
    }
    static func text(status: HTTPResponseStatus, _ value: String) -> HTTPResponseValue { .init(status: status, body: Data(value.utf8), contentType: "text/plain; charset=utf-8") }
}

private final class HTTPContextBridge: @unchecked Sendable {
    private let context: ChannelHandlerContext
    init(_ context: ChannelHandlerContext) { self.context = context }
    func send(_ response: HTTPResponseValue) {
        context.eventLoop.execute {
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: response.contentType)
            headers.add(name: "Content-Length", value: String(response.body.count))
            headers.add(name: "Cache-Control", value: "no-store")
            headers.add(name: "MCP-Protocol-Version", value: response.protocolVersion)
            self.context.write(NIOAny(HTTPServerResponsePart.head(.init(version: .http1_1, status: response.status, headers: headers))), promise: nil)
            if !response.body.isEmpty {
                var buffer = self.context.channel.allocator.buffer(capacity: response.body.count)
                buffer.writeBytes(response.body)
                self.context.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
            }
            self.context.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
        }
    }
}
