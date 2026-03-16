// MARK: - Onboarding Step 3: Theme & Appearance
//
// Theme picker with live preview card, light/dark/fun theme grids,
// and a theme chip selector.

import SwiftUI

extension OnboardingView {

    // MARK: - Step 3: Theme & Appearance

    var stepThemeAppearance: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Spacing.lg) {
                // Live Preview Card (at top like screenshot)
                themePreviewCard
                    .frame(maxWidth: 360)

                // Header below preview
                Text("Pick your style")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .padding(.top, Spacing.sm)

                // Theme Selection - Symmetrical Layout with Flexible Grids
                VStack(alignment: .center, spacing: Spacing.lg) {
                    // System centered at top
                    themeChip(.system)

                    // Two columns: Light and Dark themes in 2-column grids
                    HStack(alignment: .top, spacing: Spacing.xxl) {
                        // Light Themes Column - 2-column grid
                        VStack(alignment: .center, spacing: Spacing.md) {
                            Text("Light")
                                .font(Typography.captionSemibold)
                                .foregroundColor(themeManager.palette.textMuted)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                ForEach(AppTheme.lightThemes, id: \.self) { appTheme in
                                    themeChip(appTheme)
                                }
                            }
                            .frame(width: 140)
                        }
                        .frame(maxWidth: .infinity)

                        // Dark Themes Column - 2-column grid
                        VStack(alignment: .center, spacing: Spacing.md) {
                            Text("Dark")
                                .font(Typography.captionSemibold)
                                .foregroundColor(themeManager.palette.textMuted)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                                ForEach(AppTheme.darkThemes, id: \.self) { appTheme in
                                    themeChip(appTheme)
                                }
                            }
                            .frame(width: 140)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Fun Themes section
                    VStack(alignment: .center, spacing: Spacing.md) {
                        Text("Fun")
                            .font(Typography.captionSemibold)
                            .foregroundColor(themeManager.palette.textMuted)
                            .padding(.top, Spacing.sm)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                            ForEach(AppTheme.funThemes, id: \.self) { appTheme in
                                themeChip(appTheme)
                            }
                        }
                        .frame(maxWidth: 380)
                    }
                }
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, Spacing.huge)
        }
    }

    // MARK: - Theme Preview Card (Live Preview)

    var themePreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Fake Window Title Bar - more compact like screenshot
            HStack(spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red.opacity(0.9)).frame(width: 10, height: 10)
                    Circle().fill(Color.orange.opacity(0.9)).frame(width: 10, height: 10)
                    Circle().fill(Color.green.opacity(0.9)).frame(width: 10, height: 10)
                }
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(themeManager.palette.bgCard)

            // Fake Message Content - scaled down
            HStack(alignment: .top, spacing: Spacing.md) {
                // Frowny Avatar
                ZStack {
                    Circle()
                        .fill(themeManager.palette.effectiveAccent.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "face.smiling.inverse")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }

                // Message Bubble
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Hello! I'm ready to help you code.")
                        .font(.system(size: 11))
                        .foregroundColor(themeManager.palette.textPrimary)

                    // Fake Code Block
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(themeManager.palette.effectiveAccent)
                            .frame(width: 2, height: 14)
                        Text("print(\"Hello World\")")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(themeManager.palette.textSecondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(themeManager.palette.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(themeManager.palette.bgDark)

            // Fake Input Area - more compact
            HStack(spacing: Spacing.md) {
                Circle()
                    .fill(themeManager.palette.borderSubtle)
                    .frame(width: 20, height: 20)

                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(themeManager.palette.bgInput)
                    .frame(height: 24)

                Circle()
                    .fill(themeManager.palette.effectiveAccent)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(themeManager.palette.bgSidebar)
        }
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 24, x: 0, y: 12)
        .animation(.easeInOut(duration: Anim.quick), value: themeManager.theme)
        .animation(.easeInOut(duration: Anim.quick), value: themeManager.accentColor)
    }

    func themeChip(_ appTheme: AppTheme) -> some View {
        let isSelected = themeManager.theme == appTheme
        return Button {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                themeManager.theme = appTheme
            }
        } label: {
            VStack(spacing: Spacing.sm) {
                Image(systemName: appTheme.icon)
                    .font(.system(size: 18))
                Text(appTheme.displayName)
                    .font(Typography.microSemibold)
            }
            .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textSecondary)
            .frame(minWidth: 64, minHeight: 52)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.15) : themeManager.palette.bgInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
