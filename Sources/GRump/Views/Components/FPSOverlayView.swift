import SwiftUI

/// Optional overlay that shows the frame loop tick rate (e.g. 120 Hz).
/// Enable with UserDefaults "ShowFPSOverlay" = true (e.g. for debug builds).
struct FPSOverlayView: View {
    @EnvironmentObject var frameLoop: FrameLoopService
    @EnvironmentObject var themeManager: ThemeManager
    @State private var lastTick: UInt64 = 0
    @State private var lastTime: Date = Date()
    @State private var displayedRate: Double = 0

    var body: some View {
        Group {
            if displayedRate > 0 {
                Text("Loop: \(Int(displayedRate)) Hz")
                    .font(Typography.microSemibold)
                    .foregroundColor(.textMuted)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(themeManager.palette.bgCard.opacity(0.9))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
            }
        }
        .onChange(of: frameLoop.tick) { _, newTick in
            let now = Date()
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed >= 0.25 {
                let delta = newTick - lastTick
                displayedRate = Double(delta) / elapsed
                lastTick = newTick
                lastTime = now
            }
        }
        .onAppear {
            lastTick = frameLoop.tick
            lastTime = Date()
        }
    }
}
