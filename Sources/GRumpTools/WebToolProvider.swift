import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import GRumpCore

public struct WebToolProvider: ToolProvider {
    public let identifier = "web"
    public static let names: Set<String> = ["web_search", "read_url", "fetch_json", "download_file", "http_request", "graphql_query"]
    public init() {}
    public var tools: [RegisteredTool] {
        Self.names.sorted().compactMap { name in
            guard let definition = BuiltinToolCatalog.definition(named: name) else { return nil }
            return RegisteredTool(definition: definition) { invocation, context in try await Self.execute(invocation, context) }
        }
    }

    private static func execute(_ invocation: ToolInvocation, _ context: ExecutionContext) async throws -> ToolResult {
        let a = try ToolArguments.object(invocation)
        if invocation.name == "web_search" {
            let query = try ToolArguments.string("query", in: a)!
            var components = URLComponents(string: "https://html.duckduckgo.com/html/")!; components.queryItems = [.init(name: "q", value: query)]
            return try await fetch(invocation, url: components.url!, method: "GET", headers: [:], body: nil, expectJSON: false, context: context)
        }
        if invocation.name == "download_file" {
            let url = try validatedURL(ToolArguments.string("url", in: a)!)
            let destination = try context.resolveWorkspacePath(try ToolArguments.string("path", in: a)!)
            let (data, response) = try await URLSession.shared.data(from: url)
            try validate(response: response, data: data)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination, options: .atomic)
            return .success(invocation, text: "Downloaded \(data.count) bytes to \(destination.path)", json: ["path": .string(destination.path), "bytes": .integer(Int64(data.count))])
        }
        let url = try validatedURL(ToolArguments.string("url", in: a)!)
        var method = try ToolArguments.string("method", in: a, required: false) ?? "GET"
        guard ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"].contains(method.uppercased()) else {
            throw ToolError(code: .invalidArguments, message: "Unsupported HTTP method")
        }
        var headers: [String: String] = [:]
        if case .object(let object)? = a["headers"] { headers = object.compactMapValues(\.stringValue) }
        else if let encoded = a["headers"]?.stringValue, let parsed = try? JSONValue.decode(data: Data(encoded.utf8)), case .object(let object) = parsed {
            headers = object.compactMapValues(\.stringValue)
        }
        var body: Data?
        if invocation.name == "graphql_query" {
            method = "POST"; headers["Content-Type"] = "application/json"
            let variables: JSONValue
            if let encoded = a["variables"]?.stringValue { variables = try JSONValue.decode(data: Data(encoded.utf8)) }
            else { variables = a["variables"] ?? .object([:]) }
            let payload: JSONValue = ["query": .string(try ToolArguments.string("query", in: a)!), "variables": variables]
            body = try payload.encoded()
        } else if let bodyValue = a["body"] {
            body = bodyValue.stringValue.map { Data($0.utf8) } ?? (try? bodyValue.encoded())
        }
        return try await fetch(invocation, url: url, method: method, headers: headers, body: body,
                               expectJSON: invocation.name == "fetch_json" || invocation.name == "graphql_query", context: context)
    }

    private static func fetch(_ invocation: ToolInvocation, url: URL, method: String, headers: [String: String], body: Data?, expectJSON: Bool, context: ExecutionContext) async throws -> ToolResult {
        var request = URLRequest(url: url); request.httpMethod = method.uppercased(); request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        if expectJSON {
            let value = try JSONValue.decode(data: data)
            return .success(invocation, text: String(decoding: try value.encoded(prettyPrinted: true), as: UTF8.self), json: value)
        }
        return .success(invocation, text: String(decoding: data.prefix(1_000_000), as: UTF8.self), json: ["status": .integer(Int64((response as? HTTPURLResponse)?.statusCode ?? 0)), "bytes": .integer(Int64(data.count))])
    }

    private static func validatedURL(_ value: String?) throws -> URL {
        guard let value, let url = URL(string: value), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil else {
            throw ToolError(code: .invalidArguments, message: "A valid http(s) URL is required")
        }
        return url
    }
    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ToolError(code: .executionFailed, message: "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(String(decoding: data.prefix(4096), as: UTF8.self))")
        }
    }
}
