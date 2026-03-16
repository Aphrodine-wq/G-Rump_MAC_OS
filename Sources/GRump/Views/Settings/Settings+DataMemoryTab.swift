import SwiftUI

// MARK: - Data & Memory Settings Tab Views
// Contains: dataSection, memorySection, refreshMemoryCount
// Extracted from Settings+TabViews.swift for maintainability.

extension SettingsView {

    // MARK: - Data (Export / Import)

    var dataSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Export & Import", icon: "square.and.arrow.up", accent: themeManager.accentColor)
                #if os(macOS)
                if let exportJSON = onExportJSON, let exportMD = onExportMarkdown, let importConv = onImport {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        Text("Export conversations")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textSecondary)
                        HStack(spacing: Spacing.md) {
                            Button(action: exportJSON) {
                                Label("Export JSON…", systemImage: "doc.text")
                                    .font(Typography.bodySmallMedium)
                            }
                            .buttonStyle(.bordered)
                            Button(action: { exportMD() }) {
                                Label("Export Markdown…", systemImage: "doc.plaintext")
                                    .font(Typography.bodySmallMedium)
                            }
                            .buttonStyle(.bordered)
                        }
                        Text("Import conversations from a JSON file.")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textSecondary)
                        Button(action: importConv) {
                            Label("Import…", systemImage: "square.and.arrow.down")
                                .font(Typography.bodySmallMedium)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Export and import are available when opened from the main window.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                }
                #else
                Text("Export and import are available on macOS.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)
                #endif
            }
        }
    }

    // MARK: - Project Memory

    var memorySection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                sectionTitle("Project Memory", icon: "brain.head.profile", accent: themeManager.accentColor)
                Text("Stores conversation context in the project directory and injects relevant past memories into the agent prompt for cross-session awareness.")
                    .font(Typography.bodySmall)
                    .foregroundColor(.textMuted)

                Toggle("Enable Project Memory", isOn: $projectMemoryEnabled)

                if projectMemoryEnabled {
                    Divider()
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Toggle("Semantic Memory (On-Device RAG)", isOn: $semanticMemoryEnabled)
                            .font(Typography.bodySmall)
                        Text("Uses Apple's NaturalLanguage framework to embed memories as vectors and retrieve only the most relevant ones via cosine similarity. Fully on-device — no API calls, works offline.")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }

                    if workingDirectory.isEmpty {
                        Text("Set a working directory in Workspace to store memory.")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    } else {
                        HStack(spacing: Spacing.lg) {
                            VStack(alignment: .leading, spacing: 2) {
                                if memoryCountLoading {
                                    Text("Counting…")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                } else {
                                    Text("\(memoryEntryCount) plain-text entries")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                    Text("\(semanticMemoryCount) semantic vectors")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            Spacer()
                            Button("Clear all") {
                                let dir = workingDirectory
                                Task.detached(priority: .userInitiated) {
                                    MemoryStore(baseDirectory: dir).clear()
                                    SemanticMemoryStore(baseDirectory: dir).clear()
                                    await MainActor.run {
                                        memoryEntryCount = 0
                                        semanticMemoryCount = 0
                                    }
                                }
                            }
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                        }
                    }
                }
            }
            .onAppear { refreshMemoryCount() }
            .onChange(of: workingDirectory) { _, _ in refreshMemoryCount() }
        }
    }

    func refreshMemoryCount() {
        if workingDirectory.isEmpty {
            memoryEntryCount = 0
            semanticMemoryCount = 0
            memoryCountLoading = false
            return
        }
        memoryCountLoading = true
        let dir = workingDirectory
        Task.detached(priority: .userInitiated) {
            let count = MemoryStore(baseDirectory: dir).count()
            let semanticCount = SemanticMemoryStore(baseDirectory: dir).count()
            await MainActor.run {
                memoryEntryCount = count
                semanticMemoryCount = semanticCount
                memoryCountLoading = false
            }
        }
    }
}
