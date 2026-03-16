import Foundation
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import os.signpost

// MARK: - Performance Advisor
//
// Monitors G-Rump's own performance and the system's thermal/memory state.
// Uses Apple-native APIs:
//   - os_signpost: instrument agent operations for Instruments.app
//   - ProcessInfo.thermalState: detect thermal throttling
//   - DispatchSource.memoryPressure: detect memory pressure
//   - mach_task_basic_info: track own memory usage
//   - MetricKit (iOS): receive diagnostic payloads
//
// The advisor can auto-reduce agent concurrency under pressure and
// surface performance insights in the UI.

// MARK: - Signpost Categories

enum GRumpSignpost {
    static let log = OSLog(subsystem: "com.grump.app", category: "Performance")
    static let agentLog = OSLog(subsystem: "com.grump.app", category: "Agent")
    static let networkLog = OSLog(subsystem: "com.grump.app", category: "Network")
    static let toolLog = OSLog(subsystem: "com.grump.app", category: "ToolExecution")

    /// Mark the beginning of an agent task for Instruments profiling.
    static func beginAgentTask(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.begin, log: agentLog, name: name, signpostID: id)
    }

    static func endAgentTask(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: agentLog, name: name, signpostID: id)
    }

    /// Mark a network request interval.
    static func beginNetworkRequest(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.begin, log: networkLog, name: name, signpostID: id)
    }

    static func endNetworkRequest(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: networkLog, name: name, signpostID: id)
    }

    /// Mark a tool execution interval.
    static func beginToolExecution(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.begin, log: toolLog, name: name, signpostID: id)
    }

    static func endToolExecution(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: toolLog, name: name, signpostID: id)
    }

    /// Emit a point-in-time event.
    static func event(_ log: OSLog, name: StaticString, _ message: String) {
        os_signpost(.event, log: log, name: name, "%{public}s", message)
    }
}

// MARK: - Performance Advisor

@MainActor
final class PerformanceAdvisor: ObservableObject {

    static let shared = PerformanceAdvisor()

    // MARK: - Published State

    @Published private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    @Published private(set) var memoryPressure: MemoryPressureLevel = .normal
    @Published private(set) var appMemoryMB: Double = 0
    @Published private(set) var systemMemoryGB: Double = 0
    @Published private(set) var cpuUsagePercent: Double = 0
    @Published private(set) var isUnderPressure: Bool = false
    @Published private(set) var advisories: [PerformanceAdvisory] = []

    enum MemoryPressureLevel: String {
        case normal = "Normal"
        case warning = "Warning"
        case critical = "Critical"

        var color: String {
            switch self {
            case .normal: return "green"
            case .warning: return "yellow"
            case .critical: return "red"
            }
        }
    }

    struct PerformanceAdvisory: Identifiable {
        let id = UUID()
        let timestamp: Date
        let severity: Severity
        let message: String
        let suggestion: String

        enum Severity: String {
            case info = "Info"
            case warning = "Warning"
            case critical = "Critical"

            var icon: String {
                switch self {
                case .info: return "info.circle"
                case .warning: return "exclamationmark.triangle"
                case .critical: return "xmark.octagon"
                }
            }
        }
    }

    // MARK: - Private

    private var thermalObserver: NSObjectProtocol?
    private var memorySource: DispatchSourceMemoryPressure?
    private var monitorTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        systemMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        startMonitoring()
    }

    nonisolated func cleanup() {
        // Call from a MainActor context before deallocation if needed
    }

    // MARK: - Start/Stop Monitoring

    func startMonitoring() {
        // Thermal state observation
        thermalState = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleThermalChange()
            }
        }

        // Memory pressure monitoring via GCD
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                let flags = source.data
                if flags.contains(.critical) {
                    self?.handleMemoryPressure(.critical)
                } else if flags.contains(.warning) {
                    self?.handleMemoryPressure(.warning)
                }
            }
        }
        source.resume()
        memorySource = source

        // Periodic stats polling (every 5 seconds)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStats()
            }
        }
        updateStats()
    }

    func stopMonitoring() {
        if let observer = thermalObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        memorySource?.cancel()
        monitorTimer?.invalidate()
    }

    // MARK: - Handlers

    private func handleThermalChange() {
        thermalState = ProcessInfo.processInfo.thermalState

        switch thermalState {
        case .serious:
            addAdvisory(
                severity: .warning,
                message: "System is thermally throttling (Serious)",
                suggestion: "Reduce concurrent agent tasks. Consider pausing heavy operations."
            )
            isUnderPressure = true
        case .critical:
            addAdvisory(
                severity: .critical,
                message: "System thermal state is Critical",
                suggestion: "Agent concurrency reduced automatically. Stop non-essential tasks."
            )
            isUnderPressure = true
        case .nominal, .fair:
            isUnderPressure = thermalState != .nominal && memoryPressure != .normal
        @unknown default:
            break
        }
    }

    private func handleMemoryPressure(_ level: MemoryPressureLevel) {
        memoryPressure = level

        switch level {
        case .warning:
            addAdvisory(
                severity: .warning,
                message: "System memory pressure: Warning",
                suggestion: "Close unused conversations to free memory."
            )
        case .critical:
            addAdvisory(
                severity: .critical,
                message: "System memory pressure: Critical",
                suggestion: "Memory critically low. Reduce open conversations and stop agent tasks."
            )
        case .normal:
            break
        }

        isUnderPressure = level != .normal || thermalState == .serious || thermalState == .critical
    }

    // MARK: - Stats Update

    private func updateStats() {
        appMemoryMB = getAppMemoryMB()
    }

    private func getAppMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576
    }

    // MARK: - Advisory Management

    private func addAdvisory(severity: PerformanceAdvisory.Severity, message: String, suggestion: String) {
        let advisory = PerformanceAdvisory(
            timestamp: Date(),
            severity: severity,
            message: message,
            suggestion: suggestion
        )
        advisories.insert(advisory, at: 0)
        // Keep last 50 advisories
        if advisories.count > 50 {
            advisories = Array(advisories.prefix(50))
        }
    }

    func clearAdvisories() {
        advisories.removeAll()
    }

    // MARK: - Recommended Concurrency

    /// Recommended max concurrent agent tasks based on system state.
    var recommendedMaxConcurrency: Int {
        if thermalState == .critical || memoryPressure == .critical {
            return 1
        }
        if thermalState == .serious || memoryPressure == .warning {
            return 2
        }
        // Based on available RAM
        if systemMemoryGB >= 32 { return 8 }
        if systemMemoryGB >= 16 { return 5 }
        if systemMemoryGB >= 8 { return 3 }
        return 2
    }

    // MARK: - Performance Summary

    /// Summary string for the status bar or settings.
    var statusSummary: String {
        let thermal: String
        switch thermalState {
        case .nominal: thermal = "Cool"
        case .fair: thermal = "Warm"
        case .serious: thermal = "Hot"
        case .critical: thermal = "Throttled"
        @unknown default: thermal = "Unknown"
        }

        return String(format: "Memory: %.0f MB · Thermal: %@ · RAM: %.0f GB · Max Agents: %d",
                      appMemoryMB, thermal, systemMemoryGB, recommendedMaxConcurrency)
    }

    // MARK: - Instruments Integration

    /// Launch Instruments with a specific template for the current process.
    #if os(macOS)
    func launchInstruments(template: InstrumentsTemplate = .timeProfiler) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        switch template {
        case .timeProfiler:
            process.arguments = ["-a", "Instruments", "--args", "-t", "Time Profiler", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        case .allocations:
            process.arguments = ["-a", "Instruments", "--args", "-t", "Allocations", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        case .leaks:
            process.arguments = ["-a", "Instruments", "--args", "-t", "Leaks", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        case .network:
            process.arguments = ["-a", "Instruments", "--args", "-t", "Network", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        case .swiftConcurrency:
            process.arguments = ["-a", "Instruments", "--args", "-t", "Swift Concurrency", "-p", "\(ProcessInfo.processInfo.processIdentifier)"]
        }

        try? process.run()
    }

    enum InstrumentsTemplate: String, CaseIterable, Identifiable {
        case timeProfiler = "Time Profiler"
        case allocations = "Allocations"
        case leaks = "Leaks"
        case network = "Network"
        case swiftConcurrency = "Swift Concurrency"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .timeProfiler: return "clock"
            case .allocations: return "memorychip"
            case .leaks: return "drop.triangle"
            case .network: return "network"
            case .swiftConcurrency: return "arrow.triangle.branch"
            }
        }
    }
    #endif
}
