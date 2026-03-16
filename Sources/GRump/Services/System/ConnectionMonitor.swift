import Foundation
import Combine
import Network

/// Monitors network connectivity and API endpoint health.
/// Provides real-time connection status for graceful degradation during streaming.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    @Published private(set) var isConnected: Bool = true
    @Published private(set) var connectionType: ConnectionType = .unknown
    @Published private(set) var lastLatency: TimeInterval?
    @Published private(set) var status: Status = .connected

    enum Status: Equatable {
        case connected
        case degraded(String)
        case disconnected
        case checking
    }

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }

    private var monitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "com.grump.connection-monitor")
    private var healthCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Start / Stop

    func start() {
        guard monitor == nil else { return }

        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.connectionType = self.mapConnectionType(path)

                if path.status == .satisfied {
                    self.status = .connected
                } else {
                    self.status = .disconnected
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
        monitor = pathMonitor

        // Periodic health check every 30 seconds
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAPIHealth()
            }
        }
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    // MARK: - Health Check

    /// Ping the API endpoint to measure latency and verify connectivity.
    func checkAPIHealth() async {
        status = .checking

        let startTime = Date()
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = Date().timeIntervalSince(startTime)
            lastLatency = latency

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 401 {
                    // 401 is expected without auth, but means the endpoint is reachable
                    if latency > 5.0 {
                        status = .degraded("High latency: \(String(format: "%.1fs", latency))")
                    } else {
                        status = .connected
                    }
                } else if httpResponse.statusCode == 429 {
                    status = .degraded("Rate limited")
                } else if httpResponse.statusCode >= 500 {
                    status = .degraded("API server error (\(httpResponse.statusCode))")
                } else {
                    status = .connected
                }
            }
        } catch {
            if isConnected {
                status = .degraded("API unreachable: \(error.localizedDescription)")
            } else {
                status = .disconnected
            }
        }
    }

    // MARK: - Helpers

    private func mapConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) { return .wifi }
        if path.usesInterfaceType(.cellular) { return .cellular }
        if path.usesInterfaceType(.wiredEthernet) { return .wired }
        return .unknown
    }

    /// Formatted latency string for display.
    var formattedLatency: String? {
        guard let latency = lastLatency else { return nil }
        if latency < 1 {
            return String(format: "%.0fms", latency * 1000)
        }
        return String(format: "%.1fs", latency)
    }

    /// Whether it's safe to start a streaming request.
    var canStream: Bool {
        isConnected && status != .disconnected
    }
}
