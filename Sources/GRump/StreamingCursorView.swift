import SwiftUI

/// Claude-style premium streaming cursor — a subtle pulsing vertical line
/// that appears at the end of streaming text. Fades in/out smoothly and
/// uses the theme's accent color with a gentle glow effect.
struct StreamingCursorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var opacity: Double = 1.0
    
    /// Height matches the current line height of body text.
    var lineHeight: CGFloat = 18
    /// Width of the cursor line.
    var cursorWidth: CGFloat = 2
    
    var body: some View {
        RoundedRectangle(cornerRadius: cursorWidth / 2, style: .continuous)
            .fill(themeManager.palette.effectiveAccent)
            .frame(width: cursorWidth, height: lineHeight)
            .opacity(opacity)
            .shadow(color: themeManager.palette.effectiveAccent.opacity(0.4), radius: 3, x: 0, y: 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = 0.3
                }
            }
    }
}

/// A minimal "Generating..." status line shown below streaming content.
/// Claude-style: clean shimmer effect with subtle animation.
struct StreamingStatusLine: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var metrics: StreamMetrics
    
    @State private var shimmerOffset: CGFloat = -120
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Pulsing dot
            Circle()
                .fill(themeManager.palette.effectiveAccent)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())
            
            // Status text with shimmer
            statusText
                .font(Typography.captionSmallMedium)
                .foregroundColor(themeManager.palette.textMuted)
                .overlay(shimmerOverlay)
            
            Spacer()
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        }
    }
    
    private var statusText: some View {
        Group {
            switch metrics.phase {
            case .idle:
                Text("")
            case .waiting:
                Text("Thinking...")
            case .streaming:
                Text("Generating...")
            case .toolUse:
                Text("Running tools...")
            case .complete:
                Text("Done")
            case .error(let msg):
                Text("Error: \(msg)")
                    .foregroundColor(.red)
            }
        }
    }
    
    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [
                .clear,
                themeManager.palette.effectiveAccent.opacity(0.25),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 60)
        .offset(x: shimmerOffset)
        .mask(statusText.font(Typography.captionSmallMedium))
    }
}

/// Smooth pulse animation modifier for dots and indicators.
struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.3
                    opacity = 0.5
                }
            }
    }
}

/// Premium streaming message row that replaces GRumpStreamingBubble.
/// Shows the actual streamed content with progressive markdown rendering,
/// a Claude-style cursor, and a minimal status line.
struct PremiumStreamingRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let content: String
    var agentMode: AgentMode = .standard
    @ObservedObject var metrics: StreamMetrics
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Avatar + streaming content
            HStack(alignment: .top, spacing: Spacing.md) {
                FrownyFaceLogo(size: 32, mood: modeMood)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Progressive markdown rendering with cursor
                    HStack(alignment: .bottom, spacing: 0) {
                        MarkdownTextView(
                            text: content,
                            onCodeBlockTap: nil
                        )
                        .textSelection(.enabled)
                        
                        StreamingCursorView(lineHeight: 16, cursorWidth: 2)
                            .padding(.leading, 1)
                            .padding(.bottom, 2)
                    }
                }
                
                Spacer()
            }
            
            // Minimal status line
            StreamingStatusLine(metrics: metrics)
                .padding(.leading, 44) // Align with content (past avatar)
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .leading) {
            // Thin mode-color accent bar on the left edge
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(agentMode.modeAccentColor)
                .frame(width: 3)
                .padding(.vertical, Spacing.md)
                .padding(.leading, Spacing.lg)
                .opacity(agentMode == .standard ? 0 : 0.7)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }
    
    private var modeMood: LogoMood {
        switch agentMode {
        case .standard, .parallel, .speculative: return .neutral
        case .plan: return .thinking
        case .fullStack: return .happy
        case .argue: return .error
        case .spec: return .thinking
        }
    }
}
