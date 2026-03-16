import Foundation
import NaturalLanguage
import OSLog
#if canImport(SQLite3)
import SQLite3
#endif

// MARK: - Memory Tier

/// Three-tier memory architecture: session (ephemeral), project (per-workspace), global (cross-project).
enum MemoryTier: String, Codable, CaseIterable {
    case session
    case project
    case global
}

// MARK: - Memory Importance

enum MemoryImportance: Int, Codable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case pinned = 3

    static func < (lhs: MemoryImportance, rhs: MemoryImportance) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Advanced Memory Entry

struct AdvancedMemoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let tier: MemoryTier
    let timestamp: Date
    var content: String
    var tags: [String]
    var importance: MemoryImportance
    var accessCount: Int
    var lastAccessed: Date
    var conversationId: String?
    var vector: [Float]?

    init(
        id: UUID = UUID(),
        tier: MemoryTier,
        timestamp: Date = Date(),
        content: String,
        tags: [String] = [],
        importance: MemoryImportance = .normal,
        accessCount: Int = 0,
        lastAccessed: Date = Date(),
        conversationId: String? = nil,
        vector: [Float]? = nil
    ) {
        self.id = id
        self.tier = tier
        self.timestamp = timestamp
        self.content = content
        self.tags = tags
        self.importance = importance
        self.accessCount = accessCount
        self.lastAccessed = lastAccessed
        self.conversationId = conversationId
        self.vector = vector
    }

    static func == (lhs: AdvancedMemoryEntry, rhs: AdvancedMemoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hybrid Search Result

struct MemorySearchResult {
    let entry: AdvancedMemoryEntry
    let score: Float
    let source: String
}

// MARK: - Advanced Memory Store

/// Actor-based, SQLite-backed memory store with 3 tiers, hybrid retrieval, and entity extraction.
/// Thread-safe via Swift actor isolation. Replaces the JSON-based MemoryStore and SemanticMemoryStore.
actor AdvancedMemoryStore {

    // MARK: - Configuration

    struct Config {
        var maxSessionEntries: Int = 100
        var maxProjectEntries: Int = 1000
        var maxGlobalEntries: Int = 500
        var consolidationThreshold: Int = 800
        var vectorWeight: Float = 0.6
        var keywordWeight: Float = 0.25
        var recencyWeight: Float = 0.15
        var defaultTopK: Int = 5
        var minRelevanceScore: Float = 0.1
    }

    private let projectPath: String
    private let globalPath: String
    private let config: Config
    private let logger = GRumpLogger.persistence

    // In-memory caches
    private var sessionEntries: [AdvancedMemoryEntry] = []
    private var projectDB: SQLiteMemoryDB?
    private var globalDB: SQLiteMemoryDB?

    // Embedding cache: content hash → vector
    private var embeddingCache: [Int: [Float]] = [:]
    private let maxEmbeddingCacheSize = 500

    // MARK: - Init

    init(projectDirectory: String, config: Config = Config()) {
        self.projectPath = (projectDirectory as NSString).appendingPathComponent(".grump/memory.sqlite")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.globalPath = (home as NSString).appendingPathComponent(".grump/memory.sqlite")
        self.config = config
    }

    /// Open or create the SQLite databases.
    func open() {
        let fm = FileManager.default

        // Project DB
        let projectDir = (projectPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: projectDir) {
            try? fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        }
        projectDB = SQLiteMemoryDB(path: projectPath)
        projectDB?.createTablesIfNeeded()

        // Global DB
        let globalDir = (globalPath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: globalDir) {
            try? fm.createDirectory(atPath: globalDir, withIntermediateDirectories: true)
        }
        globalDB = SQLiteMemoryDB(path: globalPath)
        globalDB?.createTablesIfNeeded()

        logger.info("AdvancedMemoryStore opened: project=\(self.projectPath), global=\(self.globalPath)")
    }

    // MARK: - Add Entry

    func addEntry(
        tier: MemoryTier,
        content: String,
        tags: [String] = [],
        importance: MemoryImportance = .normal,
        conversationId: String? = nil
    ) {
        let vector = embed(content)
        let entry = AdvancedMemoryEntry(
            tier: tier,
            content: content,
            tags: tags,
            importance: importance,
            conversationId: conversationId,
            vector: vector
        )

        switch tier {
        case .session:
            sessionEntries.append(entry)
            if sessionEntries.count > config.maxSessionEntries {
                sessionEntries = Array(sessionEntries.suffix(config.maxSessionEntries))
            }
        case .project:
            projectDB?.insert(entry)
            pruneIfNeeded(db: projectDB, max: config.maxProjectEntries)
        case .global:
            globalDB?.insert(entry)
            pruneIfNeeded(db: globalDB, max: config.maxGlobalEntries)
        }
    }

    /// Convenience: add a memory from a conversation turn (mirrors old API).
    func addFromConversation(
        conversationId: String,
        userMessage: String,
        assistantContent: String,
        toolCallSummary: String = ""
    ) {
        let actionPart: String
        if !toolCallSummary.isEmpty {
            actionPart = "Actions: \(String(toolCallSummary.prefix(600)))"
        } else {
            actionPart = "Assistant: \(String(assistantContent.prefix(600)))"
        }
        let content = "User: \(String(userMessage.prefix(200)))\n\(actionPart)"

        // Extract tags from content
        let tags = extractTags(from: content)

        addEntry(
            tier: .project,
            content: content,
            tags: tags,
            conversationId: conversationId
        )
    }

    // MARK: - Hybrid Search

    /// Retrieve the most relevant memories using hybrid search: vector similarity + keyword matching + recency decay.
    func search(query: String, tier: MemoryTier? = nil, topK: Int? = nil) -> [MemorySearchResult] {
        let k = topK ?? config.defaultTopK
        let queryVector = embed(query)
        let queryTokens = tokenize(query)

        var candidates: [AdvancedMemoryEntry] = []

        // Gather candidates from requested tiers
        let tiers: [MemoryTier] = tier.map { [$0] } ?? MemoryTier.allCases
        for t in tiers {
            switch t {
            case .session:
                candidates.append(contentsOf: sessionEntries)
            case .project:
                if let entries = projectDB?.fetchAll() {
                    candidates.append(contentsOf: entries)
                }
            case .global:
                if let entries = globalDB?.fetchAll() {
                    candidates.append(contentsOf: entries)
                }
            }
        }

        guard !candidates.isEmpty else { return [] }

        // Score each candidate
        let now = Date()
        var scored: [(AdvancedMemoryEntry, Float)] = candidates.map { entry in
            var score: Float = 0

            // 1. Vector similarity
            if let qv = queryVector, let ev = entry.vector {
                let vecScore = cosineSimilarity(qv, ev)
                score += config.vectorWeight * vecScore
            }

            // 2. Keyword (BM25-style) scoring
            let kwScore = keywordScore(queryTokens: queryTokens, content: entry.content)
            score += config.keywordWeight * kwScore

            // 3. Recency decay
            let ageSeconds = Float(now.timeIntervalSince(entry.timestamp))
            let decayHours = ageSeconds / 3600.0
            let recency = 1.0 / (1.0 + decayHours / 24.0) // half-life of ~24 hours
            score += config.recencyWeight * recency

            // 4. Importance bonus
            let importanceBonus: Float
            switch entry.importance {
            case .pinned: importanceBonus = 0.3
            case .high: importanceBonus = 0.15
            case .normal: importanceBonus = 0
            case .low: importanceBonus = -0.05
            }
            score += importanceBonus

            // 5. Access frequency bonus (logarithmic)
            if entry.accessCount > 0 {
                score += 0.05 * log2(Float(entry.accessCount + 1))
            }

            return (entry, max(0, score))
        }

        // Sort by score descending
        scored.sort { $0.1 > $1.1 }

        // Apply MMR (Maximal Marginal Relevance) for diversity
        let results = applyMMR(candidates: scored, topK: k, lambda: 0.7)

        // Update access counts
        for result in results {
            markAccessed(result.entry)
        }

        return results
    }

    /// Build a formatted memory block for system prompt injection.
    func memoryBlock(for query: String, topK: Int = 5) -> String? {
        let results = search(query: query, topK: topK)
        guard !results.isEmpty else { return nil }

        var block = "\n\n## Memory Context\nRetrieved from persistent memory (hybrid vector + keyword search):\n"
        for r in results {
            let tierLabel = r.entry.tier.rawValue.capitalized
            block += "\n---\n[\(tierLabel)] [score: \(String(format: "%.2f", r.score))]\n\(r.entry.content)"
        }
        return block
    }

    // MARK: - Session Management

    func clearSession() {
        sessionEntries.removeAll()
    }

    // MARK: - Stats

    func sessionCount() -> Int { sessionEntries.count }
    func projectCount() -> Int { projectDB?.count() ?? 0 }
    func globalCount() -> Int { globalDB?.count() ?? 0 }

    func allEntries(tier: MemoryTier) -> [AdvancedMemoryEntry] {
        switch tier {
        case .session: return sessionEntries
        case .project: return projectDB?.fetchAll() ?? []
        case .global: return globalDB?.fetchAll() ?? []
        }
    }

    func deleteEntry(id: UUID, tier: MemoryTier) {
        switch tier {
        case .session:
            sessionEntries.removeAll { $0.id == id }
        case .project:
            projectDB?.delete(id: id)
        case .global:
            globalDB?.delete(id: id)
        }
    }

    func updateImportance(id: UUID, tier: MemoryTier, importance: MemoryImportance) {
        switch tier {
        case .session:
            if let idx = sessionEntries.firstIndex(where: { $0.id == id }) {
                sessionEntries[idx].importance = importance
            }
        case .project:
            projectDB?.updateImportance(id: id, importance: importance)
        case .global:
            globalDB?.updateImportance(id: id, importance: importance)
        }
    }

    // MARK: - Consolidation

    /// Merge older, related memories into summary entries to prevent unbounded growth.
    func consolidateIfNeeded(tier: MemoryTier) {
        let threshold = tier == .project ? config.consolidationThreshold : config.maxGlobalEntries
        let db = tier == .project ? projectDB : globalDB
        guard let db, db.count() > threshold else { return }

        // Get oldest non-pinned entries
        let all = db.fetchAll()
        let unpinned = all.filter { $0.importance != .pinned }
            .sorted { $0.timestamp < $1.timestamp }

        // Group by tags (simple clustering)
        var groups: [String: [AdvancedMemoryEntry]] = [:]
        for entry in unpinned.prefix(threshold / 2) {
            let key = entry.tags.sorted().joined(separator: ",")
            groups[key, default: []].append(entry)
        }

        // Merge groups with >3 entries
        for (_, entries) in groups where entries.count >= 3 {
            let merged = entries.map(\.content).joined(separator: "\n---\n")
            let summary = "Consolidated (\(entries.count) entries):\n\(String(merged.prefix(1200)))"
            let tags = Array(Set(entries.flatMap(\.tags)))

            // Delete originals
            for e in entries { db.delete(id: e.id) }

            // Insert summary
            let vector = embed(summary)
            let consolidated = AdvancedMemoryEntry(
                tier: tier,
                content: summary,
                tags: tags,
                importance: .normal,
                vector: vector
            )
            db.insert(consolidated)
        }

        logger.info("Memory consolidation complete for \(tier.rawValue): \(db.count()) entries remaining")
    }

    // MARK: - Embedding

    private func embed(_ text: String) -> [Float]? {
        let hash = text.hashValue
        if let cached = embeddingCache[hash] { return cached }

        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vec = embedding.vector(for: word) {
                vectors.append(vec)
            }
            return true
        }
        guard !vectors.isEmpty else { return nil }
        let dim = vectors[0].count
        var avg = [Float](repeating: 0, count: dim)
        for vec in vectors {
            for i in 0..<dim { avg[i] += Float(vec[i]) }
        }
        let cnt = Float(vectors.count)
        for i in 0..<dim { avg[i] /= cnt }

        // Cache with eviction
        if embeddingCache.count >= maxEmbeddingCacheSize {
            // Remove ~25% of entries
            let toRemove = maxEmbeddingCacheSize / 4
            let keys = Array(embeddingCache.keys.prefix(toRemove))
            for k in keys { embeddingCache.removeValue(forKey: k) }
        }
        embeddingCache[hash] = avg

        return avg
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - Keyword Scoring (BM25-style)

    private func tokenize(_ text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            tokens.insert(String(text[range]).lowercased())
            return true
        }
        return tokens
    }

    private func keywordScore(queryTokens: Set<String>, content: String) -> Float {
        guard !queryTokens.isEmpty else { return 0 }
        let contentTokens = tokenize(content)
        guard !contentTokens.isEmpty else { return 0 }
        let intersection = queryTokens.intersection(contentTokens)
        // Normalized overlap: |intersection| / sqrt(|query| * |content|)
        let rawScore = Float(intersection.count) / sqrt(Float(queryTokens.count) * Float(contentTokens.count))
        return min(rawScore, 1.0)
    }

    // MARK: - MMR (Maximal Marginal Relevance)

    private func applyMMR(candidates: [(AdvancedMemoryEntry, Float)], topK: Int, lambda: Float) -> [MemorySearchResult] {
        guard !candidates.isEmpty else { return [] }
        var selected: [MemorySearchResult] = []
        var remaining = candidates

        // Always pick the best first
        if let first = remaining.first {
            selected.append(MemorySearchResult(entry: first.0, score: first.1, source: first.0.tier.rawValue))
            remaining.removeFirst()
        }

        while selected.count < topK && !remaining.isEmpty {
            var bestIdx = 0
            var bestMMRScore: Float = -.greatestFiniteMagnitude

            for i in 0..<remaining.count {
                let (candidate, relevance) = remaining[i]
                // Max similarity to already-selected entries
                var maxSim: Float = 0
                for s in selected {
                    if let cv = candidate.vector, let sv = s.entry.vector {
                        maxSim = max(maxSim, cosineSimilarity(cv, sv))
                    }
                }
                let mmrScore = lambda * relevance - (1.0 - lambda) * maxSim
                if mmrScore > bestMMRScore {
                    bestMMRScore = mmrScore
                    bestIdx = i
                }
            }

            let (entry, score) = remaining.remove(at: bestIdx)
            if score >= config.minRelevanceScore {
                selected.append(MemorySearchResult(entry: entry, score: score, source: entry.tier.rawValue))
            } else {
                break
            }
        }

        return selected
    }

    // MARK: - Tag Extraction

    private func extractTags(from content: String) -> [String] {
        var tags: [String] = []

        // File paths
        let pathRegex = try? NSRegularExpression(pattern: #"(?:^|[\s(])((?:[/~]|\.\.?/)[^\s,)]+\.\w{1,10})"#)
        let nsContent = content as NSString
        let pathMatches = pathRegex?.matches(in: content, range: NSRange(location: 0, length: nsContent.length)) ?? []
        for match in pathMatches.prefix(5) {
            if match.numberOfRanges > 1 {
                let path = nsContent.substring(with: match.range(at: 1))
                tags.append("file:\(path)")
            }
        }

        // Error patterns
        let lowered = content.lowercased()
        if lowered.contains("error") || lowered.contains("failed") || lowered.contains("exception") {
            tags.append("has_error")
        }

        // Tool names
        let toolNames = ["write_file", "edit_file", "create_file", "run_command", "run_build", "run_tests", "git_commit", "grep_search"]
        for tool in toolNames where lowered.contains(tool) {
            tags.append("tool:\(tool)")
        }

        return tags
    }

    // MARK: - Access Tracking

    private func markAccessed(_ entry: AdvancedMemoryEntry) {
        switch entry.tier {
        case .session:
            if let idx = sessionEntries.firstIndex(where: { $0.id == entry.id }) {
                sessionEntries[idx].accessCount += 1
                sessionEntries[idx].lastAccessed = Date()
            }
        case .project:
            projectDB?.markAccessed(id: entry.id)
        case .global:
            globalDB?.markAccessed(id: entry.id)
        }
    }

    // MARK: - Pruning

    private func pruneIfNeeded(db: SQLiteMemoryDB?, max: Int) {
        guard let db, db.count() > max else { return }
        db.pruneOldest(keep: max, preservePinned: true)
    }
}

// MARK: - SQLite Memory DB

/// Lightweight SQLite wrapper for persistent memory storage.
/// Uses Foundation's sqlite3 C API directly — no external dependencies.
final class SQLiteMemoryDB {
    private var db: OpaquePointer?
    private let path: String

    init(path: String) {
        self.path = path
        if sqlite3_open(path, &db) != SQLITE_OK {
            GRumpLogger.persistence.error("Failed to open memory DB at \(path)")
            db = nil
        }
        // Enable WAL mode for better concurrent read performance
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA synchronous=NORMAL")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func createTablesIfNeeded() {
        execute("""
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY,
                tier TEXT NOT NULL,
                timestamp REAL NOT NULL,
                content TEXT NOT NULL,
                tags TEXT NOT NULL DEFAULT '[]',
                importance INTEGER NOT NULL DEFAULT 1,
                access_count INTEGER NOT NULL DEFAULT 0,
                last_accessed REAL NOT NULL,
                conversation_id TEXT,
                vector BLOB
            )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_memories_tier ON memories(tier)")
        execute("CREATE INDEX IF NOT EXISTS idx_memories_timestamp ON memories(timestamp)")
        execute("CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance)")
    }

    func insert(_ entry: AdvancedMemoryEntry) {
        guard let db else { return }
        let sql = """
            INSERT OR REPLACE INTO memories
            (id, tier, timestamp, content, tags, importance, access_count, last_accessed, conversation_id, vector)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let idStr = entry.id.uuidString
        let tagsJSON = (try? JSONEncoder().encode(entry.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let vectorData = entry.vector.flatMap { try? JSONEncoder().encode($0) }

        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (entry.tier.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 4, (entry.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (tagsJSON as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 6, Int32(entry.importance.rawValue))
        sqlite3_bind_int(stmt, 7, Int32(entry.accessCount))
        sqlite3_bind_double(stmt, 8, entry.lastAccessed.timeIntervalSince1970)

        if let convId = entry.conversationId {
            sqlite3_bind_text(stmt, 9, (convId as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 9)
        }

        if let vd = vectorData {
            vd.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 10, ptr.baseAddress, Int32(vd.count), nil)
            }
        } else {
            sqlite3_bind_null(stmt, 10)
        }

        sqlite3_step(stmt)
    }

    func fetchAll() -> [AdvancedMemoryEntry] {
        guard let db else { return [] }
        let sql = "SELECT id, tier, timestamp, content, tags, importance, access_count, last_accessed, conversation_id, vector FROM memories ORDER BY timestamp DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var entries: [AdvancedMemoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let entry = readEntry(from: stmt) {
                entries.append(entry)
            }
        }
        return entries
    }

    func count() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM memories", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    func delete(id: UUID) {
        execute("DELETE FROM memories WHERE id = '\(id.uuidString)'")
    }

    func markAccessed(id: UUID) {
        let now = Date().timeIntervalSince1970
        execute("UPDATE memories SET access_count = access_count + 1, last_accessed = \(now) WHERE id = '\(id.uuidString)'")
    }

    func updateImportance(id: UUID, importance: MemoryImportance) {
        execute("UPDATE memories SET importance = \(importance.rawValue) WHERE id = '\(id.uuidString)'")
    }

    func pruneOldest(keep: Int, preservePinned: Bool) {
        let pinClause = preservePinned ? "AND importance < \(MemoryImportance.pinned.rawValue)" : ""
        execute("""
            DELETE FROM memories WHERE id IN (
                SELECT id FROM memories WHERE 1=1 \(pinClause) ORDER BY timestamp ASC
                LIMIT (SELECT MAX(0, COUNT(*) - \(keep)) FROM memories)
            )
        """)
    }

    // MARK: - Private

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func readEntry(from stmt: OpaquePointer?) -> AdvancedMemoryEntry? {
        guard let stmt else { return nil }

        guard let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr),
              let tierStr = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
              let tier = MemoryTier(rawValue: tierStr) else { return nil }

        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2))
        let content = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
        let tagsStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "[]"
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsStr.utf8))) ?? []
        let importance = MemoryImportance(rawValue: Int(sqlite3_column_int(stmt, 5))) ?? .normal
        let accessCount = Int(sqlite3_column_int(stmt, 6))
        let lastAccessed = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))
        let conversationId = sqlite3_column_text(stmt, 8).map { String(cString: $0) }

        var vector: [Float]?
        if sqlite3_column_type(stmt, 9) != SQLITE_NULL {
            let blobPtr = sqlite3_column_blob(stmt, 9)
            let blobSize = sqlite3_column_bytes(stmt, 9)
            if let blobPtr, blobSize > 0 {
                let data = Data(bytes: blobPtr, count: Int(blobSize))
                vector = try? JSONDecoder().decode([Float].self, from: data)
            }
        }

        return AdvancedMemoryEntry(
            id: id,
            tier: tier,
            timestamp: timestamp,
            content: content,
            tags: tags,
            importance: importance,
            accessCount: accessCount,
            lastAccessed: lastAccessed,
            conversationId: conversationId,
            vector: vector
        )
    }
}
