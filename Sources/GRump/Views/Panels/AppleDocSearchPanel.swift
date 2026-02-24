import SwiftUI

// MARK: - Apple Doc Search Panel

struct AppleDocSearchPanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @StateObject private var service = AppleDocSearchService()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Spacing.lg) {
                Text("Documentation")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textSecondary)

                Spacer()

                if service.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            // Search bar
            HStack(spacing: Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                TextField("Search Apple docs…", text: $searchText)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        service.search(query: searchText)
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        service.results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
            .background(themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Content
            if service.results.isEmpty && !service.isSearching {
                if let error = service.errorMessage {
                    VStack(spacing: Spacing.xxl) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(themeManager.palette.textMuted)
                        Text(error)
                            .font(Typography.bodySmall)
                            .foregroundColor(themeManager.palette.textMuted)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.recentSearches.isEmpty {
                    emptyState
                } else {
                    // Recent searches
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Recent")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textSecondary)
                            .padding(.horizontal, Spacing.xl)
                            .padding(.top, Spacing.xl)

                        ForEach(service.recentSearches, id: \.self) { query in
                            Button(action: {
                                searchText = query
                                service.search(query: query)
                            }) {
                                HStack(spacing: Spacing.lg) {
                                    Image(systemName: "clock")
                                        .font(Typography.captionSmall)
                                        .foregroundColor(themeManager.palette.textMuted)
                                    Text(query)
                                        .font(Typography.bodySmall)
                                        .foregroundColor(themeManager.palette.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, Spacing.xl)
                                .padding(.vertical, Spacing.md)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(service.results) { result in
                            DocResultRow(result: result)
                        }
                    }
                    .padding(Spacing.lg)
                }
            }

            // Quick access bar
            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(["SwiftUI", "UIKit", "Foundation", "Combine", "SwiftData"], id: \.self) { fw in
                        Button(action: {
                            searchText = fw
                            service.search(query: fw)
                        }) {
                            Text(fw)
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.textMuted)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .background(themeManager.palette.bgElevated)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .background(themeManager.palette.bgCard)
        }
        .background(themeManager.palette.bgDark)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()
            Image(systemName: "book.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(themeManager.palette.textMuted)
            Text("Apple Documentation")
                .font(Typography.bodySmallSemibold)
                .foregroundColor(themeManager.palette.textSecondary)
            Text("Search Apple developer documentation\nfor APIs, guides, and sample code")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Doc Result Row

struct DocResultRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let result: AppleDocResult
    @State private var isHovered = false

    var body: some View {
        Button(action: openURL) {
            HStack(spacing: Spacing.lg) {
                Image(systemName: result.type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(result.type.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.sm) {
                        Text(result.title)
                            .font(Typography.bodySmallMedium)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .lineLimit(1)

                        Text(result.type.rawValue)
                            .font(Typography.micro)
                            .foregroundColor(result.type.color)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 1)
                            .background(result.type.color.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textMuted)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.palette.textMuted)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(Spacing.xl)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isHovered ? themeManager.palette.bgElevated.opacity(0.5) : themeManager.palette.bgElevated.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(themeManager.palette.borderSubtle, lineWidth: Border.hairline)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }

    private func openURL() {
        #if os(macOS)
        if let url = URL(string: result.url) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
