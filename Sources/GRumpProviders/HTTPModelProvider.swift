import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GRumpCore

public enum HTTPModelAPI: String, Codable, Sendable {
    case openAICompatible
    case anthropic
}

public struct HTTPModelConfiguration: Sendable {
    public let api: HTTPModelAPI
    public let endpoint: URL
    public let model: String
    public let apiKey: String?
    public let headers: [String: String]
    public let maxTokens: Int

    public init(api: HTTPModelAPI, endpoint: URL, model: String, apiKey: String? = nil,
                headers: [String: String] = [:], maxTokens: Int = 8_192) {
        self.api = api; self.endpoint = endpoint; self.model = model; self.apiKey = apiKey
        self.headers = headers; self.maxTokens = maxTokens
    }
}

/// Language-model adapter used by the headless CLI. It intentionally uses
/// provider wire formats instead of depending on any GUI model or view model.
public struct HTTPModelProvider: ModelProvider {
    private let configuration: HTTPModelConfiguration
    private let session: URLSession

    public init(configuration: HTTPModelConfiguration, session: URLSession = .shared) {
        self.configuration = configuration; self.session = session
    }

    public func stream(_ request: ModelRequest) -> AsyncThrowingStream<ModelEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let events = try await complete(request)
                    for event in events { continuation.yield(event) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private func complete(_ modelRequest: ModelRequest) async throws -> [ModelEvent] {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in configuration.headers { request.setValue(value, forHTTPHeaderField: key) }
        switch configuration.api {
        case .openAICompatible:
            if let key = configuration.apiKey, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try openAIBody(modelRequest).encoded()
        case .anthropic:
            guard let key = configuration.apiKey, !key.isEmpty else { throw ModelProviderError("ANTHROPIC_API_KEY is required") }
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try anthropicBody(modelRequest).encoded()
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ModelProviderError("Model endpoint returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(String(decoding: data.prefix(4_096), as: UTF8.self))")
        }
        let value = try JSONValue.decode(data: data)
        return try configuration.api == .anthropic ? parseAnthropic(value) : parseOpenAI(value)
    }

    private func openAIBody(_ request: ModelRequest) -> JSONValue {
        let messages: [JSONValue] = request.messages.map { message in
            if let invocation = message.toolInvocation {
                return ["role": "assistant", "content": .null, "tool_calls": [[
                    "id": .string(invocation.id), "type": "function", "function": [
                        "name": .string(invocation.name),
                        "arguments": .string((try? invocation.arguments.encoded()).map { String(decoding: $0, as: UTF8.self) } ?? "{}")
                    ]
                ]]]
            }
            if let result = message.toolResult {
                return ["role": "tool", "tool_call_id": .string(result.invocationID), "content": .string(message.content)]
            }
            return ["role": .string(message.role.rawValue), "content": .string(message.content)]
        }
        let tools: [JSONValue] = request.tools.map { definition in
            ["type": "function", "function": ["name": .string(definition.name), "description": .string(definition.description), "parameters": definition.inputSchema]]
        }
        return ["model": .string(configuration.model), "messages": .array(messages), "tools": .array(tools), "stream": false]
    }

    private func anthropicBody(_ request: ModelRequest) -> JSONValue {
        let system = request.messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
        let messages: [JSONValue] = request.messages.filter { $0.role != .system }.map { message in
            if let invocation = message.toolInvocation {
                return ["role": "assistant", "content": [["type": "tool_use", "id": .string(invocation.id), "name": .string(invocation.name), "input": invocation.arguments]]]
            }
            if let result = message.toolResult {
                return ["role": "user", "content": [["type": "tool_result", "tool_use_id": .string(result.invocationID), "content": .string(message.content), "is_error": .bool(result.isError)]]]
            }
            return ["role": .string(message.role == .assistant ? "assistant" : "user"), "content": .string(message.content)]
        }
        let tools: [JSONValue] = request.tools.map { definition in
            ["name": .string(definition.name), "description": .string(definition.description), "input_schema": definition.inputSchema]
        }
        return ["model": .string(configuration.model), "system": .string(system), "messages": .array(messages),
                "tools": .array(tools), "max_tokens": .integer(Int64(configuration.maxTokens))]
    }

    private func parseOpenAI(_ value: JSONValue) throws -> [ModelEvent] {
        guard case .array(let choices)? = value["choices"], let message = choices.first?["message"]?.objectValue else {
            throw ModelProviderError("Model response did not contain choices[0].message")
        }
        let text = message["content"]?.stringValue ?? ""
        var events: [ModelEvent] = text.isEmpty ? [] : [.text(text)]
        if case .array(let calls)? = message["tool_calls"] {
            for call in calls {
                guard let id = call["id"]?.stringValue, let function = call["function"]?.objectValue,
                      let name = function["name"]?.stringValue else { continue }
                let arguments = try JSONValue.decode(data: Data((function["arguments"]?.stringValue ?? "{}").utf8))
                events.append(.toolInvocation(.init(id: id, name: name, arguments: arguments)))
            }
        }
        events.append(.completed(.init(role: .assistant, content: text)))
        return events
    }

    private func parseAnthropic(_ value: JSONValue) throws -> [ModelEvent] {
        guard case .array(let blocks)? = value["content"] else { throw ModelProviderError("Anthropic response did not contain content") }
        var text = "", events: [ModelEvent] = []
        for block in blocks {
            switch block["type"]?.stringValue {
            case "text":
                let delta = block["text"]?.stringValue ?? ""; text += delta
                if !delta.isEmpty { events.append(.text(delta)) }
            case "tool_use":
                guard let id = block["id"]?.stringValue, let name = block["name"]?.stringValue else { continue }
                events.append(.toolInvocation(.init(id: id, name: name, arguments: block["input"] ?? .object([:]))))
            default: continue
            }
        }
        events.append(.completed(.init(role: .assistant, content: text)))
        return events
    }
}

public struct ModelProviderError: Error, Sendable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
