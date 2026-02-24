import SwiftUI

// MARK: - Profiling Panel

struct ProfilingPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @State private var selectedTemplate = "Time Profiler"
    @State private var isRecording = false
    @State private var measurements: [InlineMeasurement] = []
    @State private var selectedTab: ProfilingTab = .quick

    enum ProfilingTab: String, CaseIterable {
        case quick = "Quick Profile"
        case instruments = "Instruments"
    }

    private let templates = [
        ("Time Profiler", "clock.fill", "CPU usage and call stacks"),
        ("Allocations", "memorychip", "Memory allocation tracking"),
        ("Leaks", "drop.triangle", "Memory leak detection"),
        ("Network", "network", "Network activity profiling"),
        ("Core Animation", "paintbrush.pointed", "Render performance"),
        ("Energy Log", "battery.100.bolt", "Energy impact analysis")
    ]

    struct InlineMeasurement: Identifiable {
        let id = UUID()
        let label: String
        let duration: TimeInterval
        let memoryDelta: Int64?
        let timestamp: Date
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Picker("", selection: $selectedTab) {
                    ForEach(ProfilingTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)

                Spacer()

                if !measurements.isEmpty {
                    Button(action: { measurements.removeAll() }) {
                        Image(systemName: "trash")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help("Clear measurements")
                }

                if selectedTab == .quick {
                    Button(action: profileSwiftBuild) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Profile Build")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(viewModel.workingDirectory.isEmpty || isRecording)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            switch selectedTab {
            case .quick:
                quickProfileView
            case .instruments:
                instrumentsView
            }
        }
        .background(themeManager.palette.bgDark)
    }

    private func profileSwiftBuild() {
        guard !viewModel.workingDirectory.isEmpty else { return }
        isRecording = true
        let dir = viewModel.workingDirectory
        Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
            process.arguments = ["build"]
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let success = process.terminationStatus == 0
            await MainActor.run {
                self.isRecording = false
                self.measurements.append(InlineMeasurement(
                    label: "swift build\(success ? "" : " (failed)")",
                    duration: elapsed,
                    memoryDelta: nil,
                    timestamp: Date()
                ))
            }
        }
    }

    // MARK: - Quick Profile

    private var quickProfileView: some View {
        VStack(spacing: 0) {
            if measurements.isEmpty {
                VStack(spacing: Spacing.xxl) {
                    Spacer()
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 36, weight: .light))
                        .foregroundColor(themeManager.palette.textMuted)
                    Text("Quick Profiling")
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Text("Ask G-Rump to profile a code block\nor run a performance measurement")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .multilineTextAlignment(.center)

                    Button(action: addSampleMeasurement) {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                            Text("Run Sample Measurement")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.vertical, Spacing.lg)
                        .background(themeManager.palette.effectiveAccent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(measurements) { m in
                            MeasurementRow(measurement: m)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private func addSampleMeasurement() {
        let start = CFAbsoluteTimeGetCurrent()
        // Simulate a workload
        var sum: Double = 0
        for i in 0..<1_000_000 { sum += Double(i).squareRoot() }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        measurements.append(InlineMeasurement(
            label: "Sample computation (1M sqrt iterations)",
            duration: elapsed,
            memoryDelta: nil,
            timestamp: Date()
        ))
    }

    // MARK: - Instruments

    private var instrumentsView: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.md) {
                ForEach(templates, id: \.0) { name, icon, desc in
                    Button(action: { launchInstruments(template: name) }) {
                        HStack(spacing: Spacing.xl) {
                            ZStack {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(themeManager.palette.effectiveAccent.opacity(0.1))
                                    .frame(width: 40, height: 40)
                                Image(systemName: icon)
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundColor(themeManager.palette.effectiveAccent)
                            }

                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(name)
                                    .font(Typography.bodySmallSemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                                Text(desc)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(themeManager.palette.textMuted)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.forward.square")
                                .font(Typography.captionSmall)
                                .foregroundColor(themeManager.palette.textMuted)
                        }
                        .padding(Spacing.xl)
                        .background(themeManager.palette.bgElevated.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(Spacing.lg)
        }
    }

    private func launchInstruments(template: String) {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Instruments"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        #endif
    }
}

// MARK: - Measurement Row

struct MeasurementRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let measurement: ProfilingPanel.InlineMeasurement

    var body: some View {
        HStack(spacing: Spacing.xl) {
            // Duration indicator
            ZStack {
                Circle()
                    .fill(durationColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(formattedDuration)
                    .font(Typography.microSemibold)
                    .foregroundColor(durationColor)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(measurement.label)
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(2)

                HStack(spacing: Spacing.lg) {
                    Text(String(format: "%.4fs", measurement.duration))
                        .font(Typography.codeMicro)
                        .foregroundColor(themeManager.palette.textMuted)

                    if let mem = measurement.memoryDelta {
                        Text(ByteCountFormatter.string(fromByteCount: mem, countStyle: .memory))
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }

                    Text(measurement.timestamp, style: .time)
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }

            Spacer()
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgElevated.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var formattedDuration: String {
        if measurement.duration < 0.001 { return "<1ms" }
        if measurement.duration < 1.0 { return String(format: "%.0fms", measurement.duration * 1000) }
        return String(format: "%.1fs", measurement.duration)
    }

    private var durationColor: Color {
        if measurement.duration < 0.1 { return .accentGreen }
        if measurement.duration < 1.0 { return .orange }
        return .red
    }
}
