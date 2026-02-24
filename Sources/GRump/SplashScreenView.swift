import SwiftUI

struct SplashScreenView: View {
    @EnvironmentObject var themeManager: ThemeManager
    var onFinished: () -> Void

    @State private var showLeftEye = false
    @State private var showRightEye = false
    @State private var frownProgress: CGFloat = 0
    @State private var showTitle = false
    @State private var fadeOut = false
    @State private var glowOpacity: CGFloat = 0
    @State private var faceScale: CGFloat = 0.7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let faceSize: CGFloat = 160

    @State private var readyToAnimate = false

    var body: some View {
        ZStack {
            // Light background with soft purple radial glow
            themeManager.palette.bgDark
                .ignoresSafeArea()
            RadialGradient(
                colors: [themeManager.palette.effectiveAccent.opacity(0.12), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 200
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                // Face
                ZStack {
                    // Glow ring behind face
                    Circle()
                        .fill(themeManager.palette.effectiveAccent.opacity(glowOpacity * 0.15))
                        .frame(width: faceSize * 1.6, height: faceSize * 1.6)
                        .blur(radius: 30)

                    // Face circle — white with gradient border
                    Circle()
                        .fill(themeManager.palette.bgCard)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [themeManager.palette.effectiveAccent, themeManager.palette.effectiveAccentLightVariant],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 5
                                )
                        )
                        .frame(width: faceSize, height: faceSize)
                        .shadow(color: themeManager.palette.effectiveAccent.opacity(0.25), radius: 24, y: 8)

                    // Left eye
                    Circle()
                        .fill(themeManager.palette.effectiveAccent)
                        .frame(width: faceSize * 0.15, height: faceSize * 0.15)
                        .offset(x: -faceSize * 0.17, y: -faceSize * 0.1)
                        .scaleEffect(showLeftEye ? 1 : 0)
                        .opacity(showLeftEye ? 1 : 0)

                    // Right eye
                    Circle()
                        .fill(themeManager.palette.effectiveAccent)
                        .frame(width: faceSize * 0.15, height: faceSize * 0.15)
                        .offset(x: faceSize * 0.17, y: -faceSize * 0.1)
                        .scaleEffect(showRightEye ? 1 : 0)
                        .opacity(showRightEye ? 1 : 0)

                    // Frown arc
                    FrownArc()
                        .trim(from: 0, to: frownProgress)
                        .stroke(
                            themeManager.palette.effectiveAccent,
                            style: StrokeStyle(lineWidth: faceSize * 0.055, lineCap: .round)
                        )
                        .frame(width: faceSize, height: faceSize)
                }
                .drawingGroup()
                .scaleEffect(faceScale)

                // Title (no tagline)
                Text("G-Rump")
                    .font(Typography.splashTitle)
                    .foregroundColor(.textPrimary)
                    .opacity(showTitle ? 1 : 0)
                    .offset(y: showTitle ? 0 : 12)
            }
        }
        .opacity(fadeOut ? 0 : 1)
        .onAppear {
            // Defer animation start to allow the window to complete its first layout pass.
            // This prevents the initial frame drop that causes the laggy feel.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                readyToAnimate = true
                runAnimation()
            }
        }
    }

    private func runAnimation() {
        if reduceMotion {
            // Skip animations entirely — show immediately then fade out
            faceScale = 1.0
            glowOpacity = 1.0
            showLeftEye = true
            showRightEye = true
            frownProgress = 1.0
            showTitle = true
            withAnimation(.easeIn(duration: 0.3).delay(0.8)) {
                fadeOut = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                onFinished()
            }
            return
        }
        // Face scales in with spring
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.1)) {
            faceScale = 1.0
        }
        // Glow appears
        withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
            glowOpacity = 1.0
        }
        // Left eye pops in with spring
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65).delay(0.3)) {
            showLeftEye = true
        }
        // Right eye pops in with spring
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65).delay(0.45)) {
            showRightEye = true
        }
        // Frown draws with smooth easing
        withAnimation(.easeInOut(duration: 0.5).delay(0.7)) {
            frownProgress = 1.0
        }
        // Title fades up
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(1.3)) {
            showTitle = true
        }
        // Fade out
        withAnimation(.easeIn(duration: 0.35).delay(1.6)) {
            fadeOut = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2050))
            onFinished()
        }
    }
}
