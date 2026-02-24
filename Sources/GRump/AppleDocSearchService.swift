import SwiftUI
import Foundation

// MARK: - Apple Doc Models

struct AppleDocResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let path: String
    let type: DocType
    let summary: String
    let url: String

    enum DocType: String, Hashable {
        case classDoc = "Class"
        case structDoc = "Structure"
        case protocolDoc = "Protocol"
        case enumDoc = "Enumeration"
        case function = "Function"
        case property = "Property"
        case framework = "Framework"
        case article = "Article"
        case sampleCode = "Sample Code"
        case unknown = "Unknown"

        var icon: String {
            switch self {
            case .classDoc: return "c.square.fill"
            case .structDoc: return "s.square.fill"
            case .protocolDoc: return "p.square.fill"
            case .enumDoc: return "e.square.fill"
            case .function: return "f.square.fill"
            case .property: return "v.square.fill"
            case .framework: return "shippingbox.fill"
            case .article: return "doc.text.fill"
            case .sampleCode: return "chevron.left.forwardslash.chevron.right"
            case .unknown: return "questionmark.square.fill"
            }
        }

        var color: Color {
            switch self {
            case .classDoc: return Color(red: 0.6, green: 0.4, blue: 0.9)
            case .structDoc: return Color(red: 0.3, green: 0.7, blue: 1.0)
            case .protocolDoc: return Color(red: 1.0, green: 0.6, blue: 0.2)
            case .enumDoc: return Color(red: 0.3, green: 0.8, blue: 0.5)
            case .function: return Color(red: 0.9, green: 0.4, blue: 0.5)
            case .property: return Color(red: 0.5, green: 0.7, blue: 0.9)
            case .framework: return Color(red: 0.8, green: 0.7, blue: 0.3)
            case .article: return Color(red: 0.6, green: 0.6, blue: 0.7)
            case .sampleCode: return Color(red: 0.4, green: 0.8, blue: 0.7)
            case .unknown: return Color(red: 0.5, green: 0.5, blue: 0.6)
            }
        }
    }
}

// MARK: - Apple Doc Search Service

@MainActor
final class AppleDocSearchService: ObservableObject {
    @Published var results: [AppleDocResult] = []
    @Published var isSearching = false
    @Published var lastQuery: String = ""
    @Published var recentSearches: [String] = []
    @Published var errorMessage: String?

    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        lastQuery = query

        if !recentSearches.contains(query) {
            recentSearches.insert(query, at: 0)
            if recentSearches.count > 10 { recentSearches.removeLast() }
        }

        let searchQuery = query
        Task.detached(priority: .userInitiated) {
            let results = await Self.performSearch(query: searchQuery)
            await MainActor.run {
                self.results = results
                self.isSearching = false
                if results.isEmpty {
                    self.errorMessage = "No results for \"\(searchQuery)\""
                }
            }
        }
    }

    /// Generate context string for injecting into AI prompt
    func contextForQuery(_ query: String) -> String {
        let relevant = results.prefix(5)
        guard !relevant.isEmpty else { return "" }

        var context = "[Apple Documentation Context for: \(query)]\n"
        for doc in relevant {
            context += "- \(doc.type.rawValue): \(doc.title) — \(doc.summary)\n"
            context += "  URL: \(doc.url)\n"
        }
        return context
    }

    nonisolated private static func performSearch(query: String) async -> [AppleDocResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://developer.apple.com/tutorials/data/search.json?query=\(encoded)"

        guard let url = URL(string: urlString) else { return fallbackSearch(query: query) }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hits = json["results"] as? [[String: Any]] {
                let results: [AppleDocResult] = hits.prefix(20).compactMap { hit in
                    let title = hit["title"] as? String ?? ""
                    let path = hit["path"] as? String ?? ""
                    let type = hit["type"] as? String ?? ""
                    let summary = hit["description"] as? String ?? hit["abstract"] as? String ?? ""

                    let docType = mapDocType(type)
                    let docURL = "https://developer.apple.com\(path)"

                    return AppleDocResult(
                        title: title, path: path, type: docType,
                        summary: summary, url: docURL
                    )
                }
                return results.isEmpty ? fallbackSearch(query: query) : results
            }
        } catch {
            // Network error — fall through to fallback
        }

        return fallbackSearch(query: query)
    }

    nonisolated private static func fallbackSearch(query: String) -> [AppleDocResult] {
        // Provide common framework results as fallback when offline
        let commonAPIs: [(String, String, AppleDocResult.DocType, String)] = [
            ("SwiftUI", "/documentation/swiftui", .framework, "Build user interfaces across all Apple platforms with declarative Swift syntax."),
            ("UIKit", "/documentation/uikit", .framework, "Construct and manage a graphical, event-driven user interface for your iOS or tvOS app."),
            ("Foundation", "/documentation/foundation", .framework, "Access essential data types, collections, and operating-system services."),
            ("Combine", "/documentation/combine", .framework, "Customize handling of asynchronous events by combining event-processing operators."),
            ("SwiftData", "/documentation/swiftdata", .framework, "Write your model code declaratively to add managed persistence and automatic iCloud sync."),
            ("CoreData", "/documentation/coredata", .framework, "Persist or cache data on a single device, or sync across multiple devices with CloudKit."),
            ("CoreML", "/documentation/coreml", .framework, "Integrate machine learning models into your app."),
            ("MapKit", "/documentation/mapkit", .framework, "Display map or satellite imagery within your app, call out points of interest."),
            ("StoreKit", "/documentation/storekit", .framework, "Support in-app purchases and interactions with the App Store."),
            ("WidgetKit", "/documentation/widgetkit", .framework, "Show relevant, glanceable content from your app on the iOS Home Screen or macOS desktop.")
        ]

        let lowered = query.lowercased()
        return commonAPIs
            .filter { $0.0.lowercased().contains(lowered) || $0.3.lowercased().contains(lowered) }
            .map { name, path, type, summary in
                AppleDocResult(
                    title: name, path: path, type: type,
                    summary: summary,
                    url: "https://developer.apple.com\(path)"
                )
            }
    }

    nonisolated private static func mapDocType(_ type: String) -> AppleDocResult.DocType {
        let lower = type.lowercased()
        if lower.contains("class") { return .classDoc }
        if lower.contains("struct") { return .structDoc }
        if lower.contains("protocol") { return .protocolDoc }
        if lower.contains("enum") { return .enumDoc }
        if lower.contains("func") || lower.contains("method") { return .function }
        if lower.contains("property") || lower.contains("var") { return .property }
        if lower.contains("framework") || lower.contains("module") { return .framework }
        if lower.contains("article") || lower.contains("tutorial") { return .article }
        if lower.contains("sample") { return .sampleCode }
        return .unknown
    }
}

// MARK: - Apple Doc Search inline in Chat (tool-accessible)

extension AppleDocSearchService {
    /// Format search results as tool-friendly text output
    func formattedResults() -> String {
        guard !results.isEmpty else { return "No documentation results found." }

        var output = "Apple Developer Documentation Results for \"\(lastQuery)\":\n\n"
        for (i, result) in results.prefix(10).enumerated() {
            output += "\(i + 1). [\(result.type.rawValue)] \(result.title)\n"
            output += "   \(result.summary)\n"
            output += "   \(result.url)\n\n"
        }
        return output
    }
}
