import SwiftUI

// MARK: - Provider Tab Views
// Extracted from SettingsView.swift for maintainability.

extension SettingsView {

    // MARK: - Providers Section

    var providersSection: some View {
        let isPaid = platformUser?.tier == "pro" || platformUser?.tier == "team"
        let registry = AIModelRegistry.shared

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(AIProvider.allCases, id: \.rawValue) { provider in
                    providerListItem(provider, registry: registry)
                }
            }
            .frame(width: 180)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(width: 1)

            ScrollView {
                settingsCard {
                    switch selectedProvider {
                    case .openRouter:
                        providerBlock(
                            provider: .openRouter,
                            subtitle: isPaid
                                ? "Pro models available on your plan."
                                : "Upgrade to Pro/Team for flagship models.",
                            registry: registry
                        ) {
                            let availableModels = AIModel.modelsForTier(platformUser?.tier)
                            ForEach(availableModels) { model in
                                modelRow(model)
                            }
                        }
                    case .openAI:
                        providerBlock(
                            provider: .openAI,
                            subtitle: "Direct access to Codex 5.3, GPT-4o, o3, o4 Mini, and more.",
                            registry: registry
                        ) {
                            ForEach(registry.getModels(for: .openAI), id: \.id) { model in
                                enhancedModelRow(model)
                            }
                        }
                    case .anthropic:
                        providerBlock(
                            provider: .anthropic,
                            subtitle: "Direct access to Claude Opus 4.6, Sonnet 4.6, Haiku 3.5.",
                            registry: registry
                        ) {
                            ForEach(registry.getModels(for: .anthropic), id: \.id) { model in
                                enhancedModelRow(model)
                            }
                        }
                    case .google:
                        providerBlock(
                            provider: .google,
                            subtitle: "Direct access to Gemini 3.1 Pro and Flash.",
                            registry: registry
                        ) {
                            ForEach(registry.getModels(for: .google), id: \.id) { model in
                                enhancedModelRow(model)
                            }
                        }
                    case .ollama:
                        providerBlock(
                            provider: .ollama,
                            subtitle: "Run models locally. No API key needed.",
                            registry: registry
                        ) {
                            let models = registry.getModels(for: .ollama)
                            let installedNames = Set(models.map(\.modelID))

                            HStack(spacing: Spacing.md) {
                                Circle()
                                    .fill(ollamaDetected ? Color.accentGreen : Color.accentOrange)
                                    .frame(width: 8, height: 8)
                                Text(ollamaDetected ? "Ollama detected" : "Ollama not detected")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(ollamaDetected ? .accentGreen : .textMuted)
                            }

                            if let status = ollamaStatusMessage {
                                Text(status)
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            }

                            if models.isEmpty {
                                Text("No Ollama models found locally yet.")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            } else {
                                ForEach(models, id: \.id) { model in
                                    enhancedModelRow(model)
                                }
                            }

                            if ollamaDetected {
                                Divider()

                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    Text("Quick downloads")
                                        .font(Typography.captionSmallSemibold)
                                        .foregroundColor(.textSecondary)

                                    ForEach(ollamaQuickModels, id: \.name) { quickModel in
                                        HStack(spacing: Spacing.lg) {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(quickModel.label)
                                                    .font(Typography.bodySmallSemibold)
                                                    .foregroundColor(.textPrimary)
                                                Text(quickModel.name)
                                                    .font(Typography.codeSmall)
                                                    .foregroundColor(.textMuted)
                                            }
                                            Spacer()
                                            if installedNames.contains(quickModel.name) {
                                                Text("Installed")
                                                    .font(Typography.microSemibold)
                                                    .foregroundColor(.accentGreen)
                                            } else {
                                                Button {
                                                    Task { await downloadOllamaModel(quickModel.name, using: registry) }
                                                } label: {
                                                    if ollamaPullingModels.contains(quickModel.name) {
                                                        ProgressView()
                                                            .controlSize(.small)
                                                    } else {
                                                        Text("Download")
                                                            .font(Typography.captionSmallSemibold)
                                                    }
                                                }
                                                .buttonStyle(.bordered)
                                                .disabled(ollamaPullingModels.contains(quickModel.name))
                                            }
                                        }
                                        .padding(Spacing.lg)
                                        .background(themeManager.palette.bgInput)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                                    }
                                }
                            }

                            Button {
                                Task { await refreshOllamaStatus(using: registry) }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    if ollamaRefreshing {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                    Text("Detect & refresh")
                                        .font(Typography.captionSmallSemibold)
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(ollamaRefreshing)
                        }
                    case .onDevice:
                        providerBlock(
                            provider: .onDevice,
                            subtitle: "Apple Silicon inference via Core ML — zero network, zero telemetry.",
                            registry: registry
                        ) {
                            let models = registry.getModels(for: .onDevice)
                            if models.isEmpty {
                                Text("No on-device models downloaded yet. Use the catalog below.")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            } else {
                                ForEach(models, id: \.id) { model in
                                    enhancedModelRow(model)
                                }
                            }

                            Divider()

                            HStack(spacing: Spacing.md) {
                                Image(systemName: "memorychip")
                                    .foregroundColor(themeManager.palette.effectiveAccent)
                                Text("\(coreMLRegistry.systemRAMGB) GB RAM detected")
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(.textSecondary)
                                Text("— recommended: \(coreMLRegistry.recommendedQuantLevel()) quantization")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            }

                            ForEach(CoreMLModelCatalogEntry.Category.allCases, id: \.self) { category in
                                let entries = CoreMLModelRegistryService.catalog.filter { $0.category == category }
                                if !entries.isEmpty {
                                    VStack(alignment: .leading, spacing: Spacing.md) {
                                        Text(category.rawValue)
                                            .font(Typography.captionSmallSemibold)
                                            .foregroundColor(.textSecondary)
                                            .padding(.top, Spacing.sm)

                                        ForEach(entries) { entry in
                                            coreMLModelRow(entry: entry)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            for provider in AIProvider.allCases {
                let config = registry.getProviderConfig(for: provider)
                providerAPIKeys[provider.rawValue] = config?.apiKey ?? ""
                providerBaseURLs[provider.rawValue] = config?.baseURL ?? provider.defaultBaseURL
            }
            Task { await refreshOllamaStatus(using: registry) }
        }
    }

    func providerListItem(_ provider: AIProvider, registry: AIModelRegistry) -> some View {
        let isSelected = selectedProvider == provider
        let isConfigured = registry.isProviderConfigured(provider)

        return Button(action: { selectedProvider = provider }) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: providerIcon(provider))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                    .frame(width: 22)

                Text(provider.displayName)
                    .font(isSelected ? Typography.bodySmallSemibold : Typography.bodySmall)
                    .foregroundColor(isSelected ? themeManager.palette.textPrimary : themeManager.palette.textSecondary)

                Spacer()

                if isConfigured {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? themeManager.palette.effectiveAccent.opacity(0.10) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func providerBlock<Content: View>(
        provider: AIProvider,
        subtitle: String,
        registry: AIModelRegistry,
        @ViewBuilder models: @escaping () -> Content
    ) -> some View {
        let isConfigured = registry.isProviderConfigured(provider)

        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: providerIcon(provider))
                    .font(Typography.bodyMedium)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .frame(width: 28, alignment: .center)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.md) {
                        Text(provider.displayName)
                            .font(Typography.bodySemibold)
                            .foregroundColor(.textPrimary)
                        if isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.accentGreen)
                        } else if provider.requiresAPIKey {
                            Text("Not configured")
                                .font(Typography.micro)
                                .foregroundColor(.textMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themeManager.palette.bgInput)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }

                Spacer()
            }

            if provider.requiresAPIKey {
                Divider()
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("API Key")
                        .font(Typography.captionSemibold)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.md) {
                        SecureField("Enter API key…", text: Binding(
                            get: { providerAPIKeys[provider.rawValue] ?? "" },
                            set: { providerAPIKeys[provider.rawValue] = $0 }
                        ))
                        .font(Typography.bodySmall)
                        .fontDesign(.monospaced)
                        .padding(Spacing.lg)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                        Button("Save") {
                            let key = providerAPIKeys[provider.rawValue] ?? ""
                            let baseURL = providerBaseURLs[provider.rawValue]
                            var config = ProviderConfiguration(provider: provider, apiKey: key, baseURL: baseURL)
                            config.isEnabled = true
                            registry.setProviderConfig(config)
                        }
                        .font(Typography.captionSmallSemibold)
                        .buttonStyle(.borderedProminent)
                        .tint(themeManager.palette.effectiveAccent)
                    }
                }
            }

            Divider()

            Text("Models")
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)

            models()
        }
    }

    func providerIcon(_ provider: AIProvider) -> String {
        switch provider {
        case .openRouter: return "globe"
        case .openAI: return "brain"
        case .anthropic: return "sparkles"
        case .google: return "globe.americas"
        case .ollama: return "desktopcomputer"
        case .onDevice: return "apple.logo"
        }
    }

    @MainActor
    func refreshOllamaStatus(using registry: AIModelRegistry) async {
        ollamaRefreshing = true
        defer { ollamaRefreshing = false }

        let detected = await registry.isOllamaRunning()
        ollamaDetected = detected

        if detected {
            _ = await registry.refreshOllamaModels()
            if registry.getModels(for: .ollama).isEmpty {
                ollamaStatusMessage = "Ollama is running, but no models are installed yet. Use Quick downloads below."
            } else {
                ollamaStatusMessage = nil
            }
        } else {
            ollamaStatusMessage = "Start Ollama locally, then press Detect & refresh."
        }
    }

    @MainActor
    func downloadOllamaModel(_ modelName: String, using registry: AIModelRegistry) async {
        guard !ollamaPullingModels.contains(modelName) else { return }
        ollamaPullingModels.insert(modelName)
        defer { ollamaPullingModels.remove(modelName) }

        do {
            try await registry.pullOllamaModel(modelName)
            ollamaStatusMessage = "Downloaded \(modelName)."
            await refreshOllamaStatus(using: registry)
        } catch {
            ollamaStatusMessage = "Failed to download \(modelName): \(error.localizedDescription)"
        }
    }

    func enhancedModelRow(_ model: EnhancedAIModel) -> some View {
        HStack(spacing: Spacing.xxl) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(.textPrimary)
                HStack(spacing: Spacing.md) {
                    Text(model.description)
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Text("·")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    Text(formatContextWindow(model.contextWindow))
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
            }
            Spacer()
            if let pricing = model.pricing {
                Text("$\(String(format: "%.4f", pricing.inputPricePer1K))/1K")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            } else {
                Text("Free / Local")
                    .font(Typography.micro)
                    .foregroundColor(.accentGreen)
            }
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin))
    }

    // MARK: - Core ML Model Row

    func coreMLModelRow(entry: CoreMLModelCatalogEntry) -> some View {
        let state = coreMLRegistry.state(for: entry.id)
        let tooLarge = coreMLRegistry.isModelTooLarge(entry)

        return HStack(spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.sm) {
                    Text(entry.name)
                        .font(Typography.bodySmallSemibold)
                        .foregroundColor(.textPrimary)
                    if tooLarge {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentOrange)
                            .help("May exceed available RAM (\(entry.recommendedRAMGB) GB recommended)")
                    }
                }
                Text("\(entry.description)")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
                    .lineLimit(1)
                HStack(spacing: Spacing.md) {
                    Text(entry.parameterCount)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                    Text("·")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                    Text(entry.quantization)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                    Text("·")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                    Text(entry.sizeFormatted)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
            }
            Spacer()

            switch state {
            case .notDownloaded:
                Button {
                    coreMLRegistry.downloadModel(entry)
                } label: {
                    Text("Download")
                        .font(Typography.captionSmallSemibold)
                }
                .buttonStyle(.bordered)

            case .downloading(let progress, let bytesReceived, let totalBytes):
                HStack(spacing: Spacing.md) {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: progress)
                            .frame(width: 80)
                        Text("\(ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))")
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }
                    Button {
                        coreMLRegistry.pauseDownload(entry.id)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        coreMLRegistry.cancelDownload(entry.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                }

            case .paused(let bytesReceived, let totalBytes):
                HStack(spacing: Spacing.md) {
                    Text("Paused (\(ByteCountFormatter.string(fromByteCount: bytesReceived, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)))")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                    Button {
                        coreMLRegistry.downloadModel(entry)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        coreMLRegistry.cancelDownload(entry.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                }

            case .downloaded:
                HStack(spacing: Spacing.md) {
                    Text("Installed")
                        .font(Typography.microSemibold)
                        .foregroundColor(.accentGreen)
                    Button(role: .destructive) {
                        coreMLRegistry.deleteModel(entry)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                }

            case .error(let message):
                HStack(spacing: Spacing.md) {
                    Text(message)
                        .font(Typography.micro)
                        .foregroundColor(.red)
                        .lineLimit(1)
                    Button {
                        coreMLRegistry.downloadModel(entry)
                    } label: {
                        Text("Retry")
                            .font(Typography.captionSmallSemibold)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Spacing.lg)
        .background(themeManager.palette.bgInput)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
