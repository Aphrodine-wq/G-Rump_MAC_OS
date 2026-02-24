import SwiftUI
#if os(macOS)
import AppKit
#endif

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel

    @State private var currentStep = 0
    @State private var signInInProgress = false
    @State private var signInError: String?
    @State private var apiKeyInput = ""
    @State private var showAPIKeyField = false
    @State private var direction: Edge = .trailing
    @State private var selectedOnboardingProvider: AIProvider = .anthropic

    private let totalSteps = 4

    var body: some View {
        ZStack {
            themeManager.palette.bgDark
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    themeManager.palette.effectiveAccent.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 64)

                Spacer(minLength: Spacing.huge)

                Group {
                    switch currentStep {
                    case 0: stepWelcomeAuth
                    case 1: stepModelSelection
                    case 2: stepThemeAppearance
                    case 3: stepWorkspace
                    default: stepWelcomeAuth
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: direction).combined(with: .opacity),
                    removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
                ))
                .id(currentStep)

                Spacer(minLength: Spacing.huge)

                navigationButtons
                    .padding(.horizontal, Spacing.colossal)
                    .padding(.bottom, Spacing.colossal)
            }
        }
        .animation(.easeInOut(duration: Anim.smooth), value: currentStep)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: Spacing.lg) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep
                          ? themeManager.palette.effectiveAccent
                          : themeManager.palette.borderCrisp.opacity(0.3))
                    .frame(width: step == currentStep ? 28 : 8, height: 8)
                    .animation(.easeInOut(duration: Anim.quick), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Welcome + Auth

    private var stepWelcomeAuth: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: Spacing.giant) {
            FrownyFaceLogo(size: 64)
                .shadow(color: themeManager.palette.effectiveAccent.opacity(0.3), radius: 16, y: 6)

            VStack(spacing: Spacing.lg) {
                Text("Welcome to G-Rump")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Your autonomous AI coding agent.\nConnect a provider to get started.")
                    .font(Typography.body)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 480)
            }

            VStack(spacing: Spacing.xl) {
                // Provider picker cards
                VStack(spacing: Spacing.md) {
                    Text("Choose a provider")
                        .font(Typography.captionSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.md) {
                        onboardingProviderCard(.anthropic, icon: "sparkles", name: "Anthropic")
                        onboardingProviderCard(.openAI, icon: "brain", name: "OpenAI")
                        onboardingProviderCard(.ollama, icon: "desktopcomputer", name: "Ollama")
                        onboardingProviderCard(.openRouter, icon: "globe", name: "OpenRouter")
                    }
                }
                .frame(maxWidth: 420)

                // API key field for cloud providers
                if selectedOnboardingProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("\(selectedOnboardingProvider.displayName) API Key")
                            .font(Typography.captionSemibold)
                            .foregroundColor(themeManager.palette.textMuted)
                        HStack(spacing: Spacing.md) {
                            SecureField(apiKeyPlaceholder(for: selectedOnboardingProvider), text: $apiKeyInput)
                                .textFieldStyle(.plain)
                                .font(Typography.bodySmall)
                                .padding(Spacing.lg)
                                .background(themeManager.palette.bgInput)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                            Button("Save") {
                                saveProviderKey()
                            }
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.lg)
                            .background(themeManager.palette.effectiveAccent)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .buttonStyle(.plain)
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if selectedOnboardingProvider == .ollama {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "info.circle")
                            .foregroundColor(themeManager.palette.effectiveAccent)
                        Text("No API key needed. Make sure Ollama is running locally.")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textSecondary)
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                }

            }
        }
        .padding(.horizontal, Spacing.huge)
        }
    }

    private func onboardingProviderCard(_ provider: AIProvider, icon: String, name: String) -> some View {
        let isSelected = selectedOnboardingProvider == provider
        return Button {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                selectedOnboardingProvider = provider
                apiKeyInput = ""
            }
        } label: {
            VStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(name)
                    .font(Typography.captionSmallSemibold)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.12) : themeManager.palette.bgInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderCrisp.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func apiKeyPlaceholder(for provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return "sk-ant-..."
        case .openAI: return "sk-..."
        case .openRouter: return "sk-or-..."
        default: return "API key..."
        }
    }

    private func saveProviderKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let config = ProviderConfiguration(provider: selectedOnboardingProvider, apiKey: key)
        AIModelRegistry.shared.setProviderConfig(config)
        viewModel.selectProvider(selectedOnboardingProvider)
        if selectedOnboardingProvider == .openRouter {
            viewModel.apiKey = key
        }
    }

    // MARK: - Step 2: Model Selection

    private var stepModelSelection: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "cpu")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Choose your model")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Pick a default model. You can change this anytime.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            ScrollView {
                LazyVStack(spacing: Spacing.md) {
                    // Show models for the selected provider
                    let providerModels = AIModelRegistry.shared.getModels(for: selectedOnboardingProvider)

                    if !providerModels.isEmpty {
                        providerSectionHeader(selectedOnboardingProvider.displayName, icon: providerIconName(selectedOnboardingProvider))
                        ForEach(providerModels, id: \.id) { model in
                            enhancedModelCard(model)
                        }
                    }

                    // Also show legacy models if OpenRouter is selected
                    if selectedOnboardingProvider == .openRouter {
                        let models = AIModel.modelsForTier(viewModel.platformUser?.tier)
                        let freeModels = models.filter { $0.tier == "Free" }
                        if !freeModels.isEmpty {
                            providerSectionHeader("Free Models", icon: "gift")
                            ForEach(freeModels) { model in
                                modelCard(model)
                            }
                        }
                    }

                    // Other providers teaser
                    if selectedOnboardingProvider.requiresAPIKey {
                        providerSectionHeader("Local Options", icon: "desktopcomputer")
                        otherProvidersTeaser
                    }
                }
                .padding(.horizontal, Spacing.huge)
            }
            .frame(maxHeight: 380)
        }
        .padding(.horizontal, Spacing.huge)
    }

    private func providerIconName(_ provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return "sparkles"
        case .openAI: return "brain"
        case .openRouter: return "globe"
        case .ollama: return "desktopcomputer"
        case .onDevice: return "apple.logo"
        }
    }

    private func enhancedModelCard(_ model: EnhancedAIModel) -> some View {
        let isSelected = viewModel.currentEnhancedModel?.id == model.id
        return Button {
            viewModel.selectProviderAndModel(provider: model.provider, model: model)
        } label: {
            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(model.displayName)
                        .font(Typography.bodySemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                    Text(model.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(model.contextWindow / 1000)K")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            .padding(Spacing.xl)
            .background(isSelected
                        ? themeManager.palette.effectiveAccent.opacity(0.1)
                        : themeManager.palette.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderCrisp.opacity(0.3), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    private func providerSectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(themeManager.palette.effectiveAccent)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
            Spacer()
        }
        .padding(.top, Spacing.lg)
    }

    private var otherProvidersTeaser: some View {
        HStack(spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("OpenAI, Anthropic, Ollama, On-Device")
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(themeManager.palette.textPrimary)
                Text("Configure API keys in Settings → Providers after setup.")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            Spacer()
            Image(systemName: "arrow.right.circle")
                .font(Typography.bodyMedium)
                .foregroundColor(themeManager.palette.textMuted)
        }
        .padding(Spacing.xl)
        .background(themeManager.palette.bgCard.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(themeManager.palette.borderCrisp.opacity(0.2), lineWidth: 1))
    }

    private func modelCard(_ model: AIModel) -> some View {
        let isSelected = viewModel.selectedModel == model
        return Button {
            viewModel.selectedModel = model
        } label: {
            HStack(spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.md) {
                        Text(model.displayName)
                            .font(Typography.bodySemibold)
                            .foregroundColor(themeManager.palette.textPrimary)
                        Text(model.tier)
                            .font(Typography.micro)
                            .foregroundColor(model.tier == "Free" ? .accentGreen : themeManager.palette.effectiveAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((model.tier == "Free" ? Color.accentGreen : themeManager.palette.effectiveAccent).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Text(model.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(model.contextWindow / 1000)K")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            .padding(Spacing.xl)
            .background(isSelected
                        ? themeManager.palette.effectiveAccent.opacity(0.1)
                        : themeManager.palette.bgCard.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isSelected ? themeManager.palette.effectiveAccent.opacity(0.5) : themeManager.palette.borderCrisp.opacity(0.3), lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: Theme & Appearance

    private var stepThemeAppearance: some View {
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

    private var themePreviewCard: some View {
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

    private func themeChip(_ appTheme: AppTheme) -> some View {
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

    // MARK: - Step 4: Workspace

    @State private var detectedTools: [(name: String, icon: String, found: Bool)] = []
    @State private var toolDetectionDone = false
    @State private var isInstallingTools = false
    @State private var installToolsMessage: String?

    private func detectTools() {
        #if os(macOS)
        let tools: [(String, String, String)] = [
            ("git", "arrow.triangle.branch", "git"),
            ("node", "curlybraces", "node"),
            ("python3", "chevron.left.forwardslash.chevron.right", "python3"),
            ("swift", "swift", "swift"),
            ("cargo", "gearshape", "cargo"),
            ("go", "gearshape.2", "go"),
            ("docker", "shippingbox", "docker"),
            ("brew", "cup.and.saucer", "brew"),
        ]
        var results: [(name: String, icon: String, found: Bool)] = []
        for (name, icon, cmd) in tools {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [cmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                results.append((name: name, icon: icon, found: process.terminationStatus == 0))
            } catch {
                results.append((name: name, icon: icon, found: false))
            }
        }
        detectedTools = results
        toolDetectionDone = true
        #endif
    }

    private var stepWorkspace: some View {
        VStack(spacing: Spacing.giant) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(themeManager.palette.effectiveAccent)

                Text("Set your workspace")
                    .font(Typography.displayMedium)
                    .foregroundColor(themeManager.palette.textPrimary)

                Text("Point G-Rump at your project's root directory so it can read files, run commands, and understand your codebase.")
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: Spacing.xl) {
                #if os(macOS)
                Button(action: runFolderPicker) {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "folder.badge.plus")
                            .font(Typography.bodyMedium)
                        Text(viewModel.workingDirectory.isEmpty ? "Choose folder..." : viewModel.workingDirectory)
                            .font(Typography.bodySmallSemibold)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: 400)
                    .padding(.vertical, Spacing.xl)
                    .padding(.horizontal, Spacing.huge)
                    .background(themeManager.palette.bgInput)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                }
                .buttonStyle(.plain)
                #endif

                if !viewModel.workingDirectory.isEmpty {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentGreen)
                        Text("Workspace set")
                            .font(Typography.bodySmallSemibold)
                            .foregroundColor(.accentGreen)
                    }
                }

                // Auto-detected tools
                if toolDetectionDone && !detectedTools.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("Detected Tools")
                            .font(Typography.captionSemibold)
                            .foregroundColor(themeManager.palette.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: Spacing.md) {
                            ForEach(Array(detectedTools.enumerated()), id: \.offset) { _, tool in
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: tool.found ? "checkmark.circle.fill" : "xmark.circle")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(tool.found ? .accentGreen : themeManager.palette.textMuted.opacity(0.5))
                                    Text(tool.name)
                                        .font(Typography.captionSmallMedium)
                                        .foregroundColor(tool.found ? themeManager.palette.textPrimary : themeManager.palette.textMuted)
                                }
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .background(tool.found ? Color.accentGreen.opacity(0.08) : themeManager.palette.bgInput.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: 400)
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgCard.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .transition(.opacity)

                    // Install All Missing button
                    let missingTools = detectedTools.filter { !$0.found }
                    if !missingTools.isEmpty {
                        Button(action: { installMissingTools() }) {
                            HStack(spacing: Spacing.md) {
                                if isInstallingTools {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(themeManager.palette.effectiveAccent)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(Typography.bodySmall)
                                }
                                Text("Install All Missing (\(missingTools.count))")
                                    .font(Typography.bodySmallSemibold)
                            }
                            .frame(maxWidth: 400)
                            .padding(.vertical, Spacing.lg)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .background(themeManager.palette.effectiveAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(themeManager.palette.effectiveAccent.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isInstallingTools)
                    }

                    if let msg = installToolsMessage {
                        Text(msg)
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                            .frame(maxWidth: 400, alignment: .leading)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .onAppear { detectTools() }
    }

    private func installMissingTools() {
        #if os(macOS)
        isInstallingTools = true
        installToolsMessage = nil

        // Check if brew exists
        let brewExists = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
                        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")

        guard brewExists else {
            // Show native install instructions when brew is not available
            installToolsMessage = "Homebrew not detected. Native installers coming soon."
            isInstallingTools = false
            return
        }

        let brewInstallable: [String: String] = [
            "node": "node",
            "python3": "python3",
            "go": "go",
            "cargo": "rust",
            "brew": "" // Can't install brew via brew
        ]
        let notBrewInstallable = ["docker", "brew"]

        let missing = detectedTools.filter { !$0.found }
        let toInstall = missing.compactMap { tool -> String? in
            guard !notBrewInstallable.contains(tool.name) else { return nil }
            return brewInstallable[tool.name] ?? tool.name
        }

        let skipped = missing.filter { notBrewInstallable.contains($0.name) }.map(\.name)

        guard !toInstall.isEmpty else {
            let skippedMsg = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", ")) (install manually)."
            installToolsMessage = "Nothing to install via Homebrew.\(skippedMsg)"
            isInstallingTools = false
            return
        }

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            // Fallback to /usr/local/bin/brew for Intel Macs
            if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/brew")
            }
            process.arguments = ["install"] + toInstall
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                await MainActor.run {
                    let skippedMsg = skipped.isEmpty ? "" : " Skipped: \(skipped.joined(separator: ", ")) (install manually)."
                    if process.terminationStatus == 0 {
                        installToolsMessage = "Installed successfully!\(skippedMsg)"
                    } else {
                        installToolsMessage = "Some installs may have failed. Check terminal.\(skippedMsg)"
                    }
                    isInstallingTools = false
                    detectTools()
                }
            } catch {
                await MainActor.run {
                    installToolsMessage = "Failed: \(error.localizedDescription)"
                    isInstallingTools = false
                }
            }
        }
        #endif
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    direction = .leading
                    withAnimation { currentStep -= 1 }
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(Typography.bodySemibold)
                    }
                    .foregroundColor(themeManager.palette.textSecondary)
                    .padding(.horizontal, Spacing.huge)
                    .padding(.vertical, Spacing.xl)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if currentStep == 0 {
                Button {
                    direction = .trailing
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Skip for now")
                        .font(Typography.bodySmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.trailing, Spacing.xl)
            }

            Button {
                if currentStep < totalSteps - 1 {
                    direction = .trailing
                    withAnimation { currentStep += 1 }
                } else {
                    hasCompletedOnboarding = true
                }
            } label: {
                Text(currentStep == totalSteps - 1 ? "Get started" : "Next")
                    .font(Typography.bodySemibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.colossal)
                    .padding(.vertical, Spacing.xl)
                    .background(themeManager.palette.effectiveAccent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    #if os(macOS)
    private func runFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewModel.setWorkingDirectory(url.path)
    }
    #endif
}
