import SwiftUI

// MARK: - Memory Panel

/// Panel view for browsing, searching, and managing persistent memories.
/// Three sections: Active Context (session), Project Knowledge, Global Preferences.
/// Each memory item supports edit, pin, and delete actions.
struct MemoryPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var selectedTier: MemoryTier = .project
    @State private var searchQuery: String = ""
    @State private var entries: [AdvancedMemoryEntry] = []
    @State private var graphNodes: [MemoryGraphNode] = []
    @State private var isLoading = false
    @State private var showGraphSection = false

    // Stats
    @State private var sessionCount = 0
    @State private var projectCount = 0
    @State private var globalCount = 0
    @State private var edgeCount = 0

    @EnvironmentObject var chatViewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider()
            tierPicker
            Divider()
            if isLoading {
                ProgressView("Loading memories…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty && searchQuery.isEmpty {
                emptyState
            } else {
                memoryList
            }
            Divider()
            statsFooter
        }
        .background(themeManager.palette.bgDark)
        .onAppear { refreshData() }
        .onChange(of: selectedTier) { _ in refreshData() }
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundColor(themeManager.palette.effectiveAccent)
                Text("Memory")
                    .font(.headline)
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                Button(action: { showGraphSection.toggle() }) {
                    Image(systemName: showGraphSection ? "circle.grid.cross.fill" : "circle.grid.cross")
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
                .help("Toggle entity graph")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(themeManager.palette.textMuted)
                    .font(.caption)
                TextField("Search memories…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        refreshData()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.palette.textMuted)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(themeManager.palette.bgCard)
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Tier Picker

    private var tierPicker: some View {
        Picker("Tier", selection: $selectedTier) {
            Text("Session (\(sessionCount))").tag(MemoryTier.session)
            Text("Project (\(projectCount))").tag(MemoryTier.project)
            Text("Global (\(globalCount))").tag(MemoryTier.global)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Memory List

    private var memoryList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if showGraphSection && !graphNodes.isEmpty {
                    graphSection
                }

                ForEach(entries) { entry in
                    MemoryEntryRow(
                        entry: entry,
                        themeManager: themeManager,
                        onPin: { togglePin(entry) },
                        onDelete: { deleteEntry(entry) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Graph Section

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundColor(themeManager.palette.effectiveAccent)
                    .font(.caption)
                Text("Entity Graph")
                    .font(.caption.bold())
                    .foregroundColor(themeManager.palette.textPrimary)
                Spacer()
                Text("\(graphNodes.count) entities, \(edgeCount) edges")
                    .font(.caption2)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            ForEach(graphNodes.prefix(15)) { node in
                HStack(spacing: 6) {
                    Image(systemName: node.entityType.icon)
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 14)
                    Text(node.label)
                        .font(.caption)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(node.connectionCount)")
                        .font(.caption2)
                        .foregroundColor(themeManager.palette.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(themeManager.palette.bgCard)
                        .cornerRadius(3)
                }
            }
        }
        .padding(10)
        .background(themeManager.palette.bgCard.opacity(0.5))
        .cornerRadius(8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36))
                .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
            Text("No memories yet")
                .font(.subheadline)
                .foregroundColor(themeManager.palette.textMuted)
            Text("Memories are automatically captured\nfrom your conversations.")
                .font(.caption)
                .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Footer

    private var statsFooter: some View {
        HStack(spacing: 12) {
            Label("\(sessionCount)", systemImage: "clock")
            Label("\(projectCount)", systemImage: "folder")
            Label("\(globalCount)", systemImage: "globe")
            Spacer()
            Button("Clear") {
                clearTier()
            }
            .font(.caption)
            .foregroundColor(.red.opacity(0.8))
        }
        .font(.caption2)
        .foregroundColor(themeManager.palette.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func refreshData() {
        isLoading = true
        Task {
            let store = chatViewModel.advancedMemory
            let graph = chatViewModel.memoryGraph

            let fetchedEntries = await store.allEntries(tier: selectedTier)
            let sCount = await store.sessionCount()
            let pCount = await store.projectCount()
            let gCount = await store.globalCount()
            let nodes = await graph.allNodes()
            let edges = await graph.edgeCount()

            await MainActor.run {
                entries = fetchedEntries
                sessionCount = sCount
                projectCount = pCount
                globalCount = gCount
                graphNodes = nodes
                edgeCount = edges
                isLoading = false
            }
        }
    }

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            refreshData()
            return
        }
        isLoading = true
        Task {
            let store = chatViewModel.advancedMemory
            let results = await store.search(query: searchQuery, tier: selectedTier, topK: 20)
            await MainActor.run {
                entries = results.map(\.entry)
                isLoading = false
            }
        }
    }

    private func togglePin(_ entry: AdvancedMemoryEntry) {
        let newImportance: MemoryImportance = entry.importance == .pinned ? .normal : .pinned
        Task {
            await chatViewModel.advancedMemory.updateImportance(id: entry.id, tier: entry.tier, importance: newImportance)
            refreshData()
        }
    }

    private func deleteEntry(_ entry: AdvancedMemoryEntry) {
        Task {
            await chatViewModel.advancedMemory.deleteEntry(id: entry.id, tier: entry.tier)
            refreshData()
        }
    }

    private func clearTier() {
        Task {
            if selectedTier == .session {
                await chatViewModel.advancedMemory.clearSession()
            }
            refreshData()
        }
    }
}

// MARK: - Memory Entry Row

struct MemoryEntryRow: View {
    let entry: AdvancedMemoryEntry
    let themeManager: ThemeManager
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 6) {
                // Importance indicator
                Circle()
                    .fill(importanceColor)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.content.prefix(isExpanded ? 2000 : 120))
                        .font(.caption)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(isExpanded ? nil : 3)

                    HStack(spacing: 6) {
                        Text(formatDate(entry.timestamp))
                            .font(.caption2)
                            .foregroundColor(themeManager.palette.textMuted)

                        if entry.accessCount > 0 {
                            Text("×\(entry.accessCount)")
                                .font(.caption2)
                                .foregroundColor(themeManager.palette.textMuted)
                        }

                        if !entry.tags.isEmpty {
                            Text(entry.tags.prefix(3).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(themeManager.palette.effectiveAccent.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 4) {
                    Button(action: onPin) {
                        Image(systemName: entry.importance == .pinned ? "pin.fill" : "pin")
                            .font(.caption2)
                            .foregroundColor(entry.importance == .pinned ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .background(themeManager.palette.bgCard.opacity(0.3))
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    private var importanceColor: Color {
        switch entry.importance {
        case .pinned: return .orange
        case .high: return .red
        case .normal: return .blue
        case .low: return .gray
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
