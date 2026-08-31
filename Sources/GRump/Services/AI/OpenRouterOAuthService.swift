import Combine
import CryptoKit
import Foundation
import Network
import Security
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// OpenRouter's public OAuth PKCE flow for user-facing, local-first apps.
/// The resulting user-controlled API key is stored in the same Keychain entry
/// used by manually entered OpenRouter keys.
@MainActor
final class OpenRouterOAuthService: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case openingBrowser
        case waitingForAuthorization
        case exchangingCode
        case connected
        case failed(String)

        var isConnecting: Bool {
            switch self {
            case .openingBrowser, .waitingForAuthorization, .exchangingCode: return true
            default: return false
            }
        }
    }

    @Published private(set) var state: ConnectionState = .idle
    private var connectionTask: Task<Void, Never>?
    private var loopbackServer: OAuthLoopbackServer?

    func connect() {
        guard !state.isConnecting else { return }
        connectionTask?.cancel()
        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let verifier = try Self.makeCodeVerifier()
                let challenge = Self.makeCodeChallenge(verifier: verifier)
                let callbackNonce = UUID().uuidString.lowercased()
                let server = try OAuthLoopbackServer(callbackPath: "/oauth/openrouter/\(callbackNonce)")
                loopbackServer = server
                let callbackURL = try await server.start()
                let authorizationURL = try Self.makeAuthorizationURL(
                    callbackURL: callbackURL,
                    codeChallenge: challenge
                )

                state = .openingBrowser
                try Self.openBrowser(authorizationURL)
                state = .waitingForAuthorization

                let code = try await server.waitForAuthorizationCode(timeout: 180)
                guard !Task.isCancelled else { throw CancellationError() }
                state = .exchangingCode
                let key = try await Self.exchange(code: code, verifier: verifier)
                guard !Task.isCancelled else { throw CancellationError() }

                AIModelRegistry.shared.setAPIKey(key, for: .openRouter)
                MultiProviderAIService.shared.ensureProviderConnection(.openRouter)
                state = .connected
            } catch is CancellationError {
                state = .idle
            } catch {
                state = .failed(error.localizedDescription)
            }
            loopbackServer?.stop()
            loopbackServer = nil
            connectionTask = nil
        }
    }

    func cancel() {
        connectionTask?.cancel()
        loopbackServer?.stop()
        loopbackServer = nil
        connectionTask = nil
        state = .idle
    }

    nonisolated static func makeAuthorizationURL(callbackURL: URL, codeChallenge: String) throws -> URL {
        var components = URLComponents(string: "https://openrouter.ai/auth")
        components?.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw OpenRouterOAuthError.invalidAuthorizationURL }
        return url
    }

    nonisolated static func makeCodeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private nonisolated static func makeCodeVerifier() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OpenRouterOAuthError.randomGenerationFailed
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func openBrowser(_ url: URL) throws {
        #if os(macOS)
        guard NSWorkspace.shared.open(url) else { throw OpenRouterOAuthError.browserLaunchFailed }
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private nonisolated static func exchange(code: String, verifier: String) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/auth/keys") else {
            throw OpenRouterOAuthError.invalidExchangeURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ExchangeRequest(
            code: code,
            codeVerifier: verifier,
            codeChallengeMethod: "S256"
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenRouterOAuthError.exchangeRejected
        }
        let payload = try JSONDecoder().decode(ExchangeResponse.self, from: data)
        guard !payload.key.isEmpty else { throw OpenRouterOAuthError.missingKey }
        return payload.key
    }

    private struct ExchangeRequest: Encodable {
        let code: String
        let codeVerifier: String
        let codeChallengeMethod: String

        enum CodingKeys: String, CodingKey {
            case code
            case codeVerifier = "code_verifier"
            case codeChallengeMethod = "code_challenge_method"
        }
    }

    private struct ExchangeResponse: Decodable {
        let key: String
    }
}

private enum OpenRouterOAuthError: LocalizedError {
    case invalidAuthorizationURL
    case invalidExchangeURL
    case randomGenerationFailed
    case browserLaunchFailed
    case authorizationTimedOut
    case authorizationDenied(String)
    case invalidCallback
    case exchangeRejected
    case missingKey

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationURL: return "Could not create the OpenRouter authorization URL."
        case .invalidExchangeURL: return "The OpenRouter token endpoint is invalid."
        case .randomGenerationFailed: return "Could not create secure OAuth credentials."
        case .browserLaunchFailed: return "Could not open the authorization page."
        case .authorizationTimedOut: return "OpenRouter authorization timed out."
        case .authorizationDenied(let message): return "OpenRouter authorization was denied: \(message)"
        case .invalidCallback: return "OpenRouter returned an invalid authorization response."
        case .exchangeRejected: return "OpenRouter rejected the authorization code."
        case .missingKey: return "OpenRouter did not return an API key."
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Single-use, loopback-only HTTP callback receiver. The randomized path and
/// PKCE verifier prevent another local process from completing the flow.
private final class OAuthLoopbackServer: @unchecked Sendable {
    private let callbackPath: String
    private let queue = DispatchQueue(label: "com.grump.oauth.openrouter")
    private let listener: NWListener
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var callbackURL: URL?
    private var isFinished = false

    init(callbackPath: String) throws {
        self.callbackPath = callbackPath
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                startContinuation = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
            }
        }
    }

    func waitForAuthorizationCode(timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard !isFinished else {
                    continuation.resume(throwing: OpenRouterOAuthError.invalidCallback)
                    return
                }
                codeContinuation = continuation
                queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(throwing: OpenRouterOAuthError.authorizationTimedOut)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            listener.cancel()
            if !isFinished { finish(throwing: CancellationError()) }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(callbackPath)") else {
                startContinuation?.resume(throwing: OpenRouterOAuthError.invalidCallback)
                startContinuation = nil
                return
            }
            callbackURL = url
            startContinuation?.resume(returning: url)
            startContinuation = nil
        case .failed(let error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            finish(throwing: error)
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            if let error {
                respond(connection, status: "400 Bad Request", body: "Authorization failed.")
                finish(throwing: error)
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.components(separatedBy: "\r\n").first else {
                respond(connection, status: "400 Bad Request", body: "Invalid authorization response.")
                finish(throwing: OpenRouterOAuthError.invalidCallback)
                return
            }
            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2,
                  let components = URLComponents(string: "http://127.0.0.1\(parts[1])"),
                  components.path == callbackPath else {
                respond(connection, status: "404 Not Found", body: "Not found.")
                return
            }

            if let errorMessage = components.queryItems?.first(where: { $0.name == "error" })?.value {
                respond(connection, status: "403 Forbidden", body: "Authorization was not completed. You can close this window.")
                finish(throwing: OpenRouterOAuthError.authorizationDenied(errorMessage))
                return
            }
            guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                  !code.isEmpty else {
                respond(connection, status: "400 Bad Request", body: "No authorization code was returned.")
                finish(throwing: OpenRouterOAuthError.invalidCallback)
                return
            }

            respond(connection, status: "200 OK", body: "OpenRouter is connected to G-Rump. You can close this window.")
            finish(returning: code)
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let escaped = body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = "<!doctype html><meta charset=\"utf-8\"><title>G-Rump</title><body style=\"font:16px system-ui;background:#111;color:#eee;padding:48px\"><h1>G-Rump</h1><p>\(escaped)</p></body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(returning code: String) {
        guard !isFinished else { return }
        isFinished = true
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
        listener.cancel()
    }

    private func finish(throwing error: Error) {
        guard !isFinished else { return }
        isFinished = true
        codeContinuation?.resume(throwing: error)
        codeContinuation = nil
        listener.cancel()
    }
}
