import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

// MARK: - Memory Graph Edge

/// A directional relationship between two entities in the memory graph.
struct MemoryGraphEdge: Identifiable, Codable, Equatable {
    let id: UUID
    let fromEntity: String
    let toEntity: String
    let relationship: String
    let weight: Float
    let timestamp: Date

    init(
        id: UUID = UUID(),
        fromEntity: String,
        toEntity: String,
        relationship: String,
        weight: Float = 1.0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.fromEntity = fromEntity
        self.toEntity = toEntity
        self.relationship = relationship
        self.weight = weight
        self.timestamp = timestamp
    }
}

// MARK: - Entity Node (for display)

struct MemoryGraphNode: Identifiable, Equatable {
    let id: String
    let label: String
    let entityType: EntityType
    var connectionCount: Int

    enum EntityType: String, CaseIterable {
        case file
        case function
        case package
        case pattern
        case preference
        case error
        case unknown

        var icon: String {
            switch self {
            case .file: return "doc.text"
            case .function: return "function"
            case .package: return "shippingbox"
            case .pattern: return "rectangle.3.group"
            case .preference: return "slider.horizontal.3"
            case .error: return "exclamationmark.triangle"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

// MARK: - Memory Graph

/// Entity relationship graph stored as an adjacency list in SQLite.
/// Stores connections like "FileA depends on FileB", "User prefers tabs", "Project uses SwiftData".
/// Enables traversal for "related memories" — querying FileA also surfaces connected FileB memories.
actor MemoryGraph {

    private var db: OpaquePointer?
    private let path: String

    init(projectDirectory: String) {
        let grumpDir = (projectDirectory as NSString).appendingPathComponent(".grump")
        self.path = (grumpDir as NSString).appendingPathComponent("memory.sqlite")
    }

    /// Open and create the edges table in the existing memory SQLite DB.
    func open() {
        if sqlite3_open(path, &db) != SQLITE_OK {
            GRumpLogger.persistence.error("MemoryGraph failed to open DB at \(self.path)")
            db = nil
            return
        }
        createTablesIfNeeded()
    }

    private func createTablesIfNeeded() {
        execute("""
            CREATE TABLE IF NOT EXISTS memory_edges (
                id TEXT PRIMARY KEY,
                from_entity TEXT NOT NULL,
                to_entity TEXT NOT NULL,
                relationship TEXT NOT NULL,
                weight REAL NOT NULL DEFAULT 1.0,
                timestamp REAL NOT NULL
            )
        """)
        execute("CREATE INDEX IF NOT EXISTS idx_edges_from ON memory_edges(from_entity)")
        execute("CREATE INDEX IF NOT EXISTS idx_edges_to ON memory_edges(to_entity)")
        execute("CREATE INDEX IF NOT EXISTS idx_edges_relationship ON memory_edges(relationship)")
    }

    // MARK: - Add / Remove Edges

    func addEdge(from: String, to: String, relationship: String, weight: Float = 1.0) {
        guard let db else { return }

        // Check for existing edge and strengthen it instead of duplicating
        if let existing = findEdge(from: from, to: to, relationship: relationship) {
            let newWeight = min(existing.weight + 0.5, 10.0)
            execute("UPDATE memory_edges SET weight = \(newWeight), timestamp = \(Date().timeIntervalSince1970) WHERE id = '\(existing.id.uuidString)'")
            return
        }

        let edge = MemoryGraphEdge(fromEntity: from, toEntity: to, relationship: relationship, weight: weight)
        let sql = "INSERT INTO memory_edges (id, from_entity, to_entity, relationship, weight, timestamp) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (edge.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (from as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (to as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (relationship as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 5, Double(weight))
        sqlite3_bind_double(stmt, 6, edge.timestamp.timeIntervalSince1970)

        sqlite3_step(stmt)
    }

    func removeEdge(id: UUID) {
        execute("DELETE FROM memory_edges WHERE id = '\(id.uuidString)'")
    }

    // MARK: - Query

    /// Find all entities connected to a given entity (one hop).
    func neighbors(of entity: String) -> [MemoryGraphEdge] {
        guard let db else { return [] }
        let sql = "SELECT id, from_entity, to_entity, relationship, weight, timestamp FROM memory_edges WHERE from_entity = ? OR to_entity = ? ORDER BY weight DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (entity as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (entity as NSString).utf8String, -1, nil)

        var edges: [MemoryGraphEdge] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let edge = readEdge(from: stmt) {
                edges.append(edge)
            }
        }
        return edges
    }

    /// Find related entities up to N hops away (BFS traversal).
    func relatedEntities(to entity: String, maxHops: Int = 2) -> [String] {
        var visited = Set<String>()
        var queue: [(String, Int)] = [(entity, 0)]
        visited.insert(entity)

        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if depth >= maxHops { continue }

            let edges = neighbors(of: current)
            for edge in edges {
                let neighbor = edge.fromEntity == current ? edge.toEntity : edge.fromEntity
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append((neighbor, depth + 1))
                }
            }
        }

        visited.remove(entity)
        return Array(visited)
    }

    /// Get all unique entities as graph nodes with connection counts.
    func allNodes() -> [MemoryGraphNode] {
        guard let db else { return [] }

        var entityCounts: [String: Int] = [:]
        let sql = "SELECT from_entity, to_entity FROM memory_edges"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let from = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) {
                entityCounts[from, default: 0] += 1
            }
            if let to = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }) {
                entityCounts[to, default: 0] += 1
            }
        }

        return entityCounts.map { entity, count in
            MemoryGraphNode(
                id: entity,
                label: entity,
                entityType: inferEntityType(entity),
                connectionCount: count
            )
        }.sorted { $0.connectionCount > $1.connectionCount }
    }

    func edgeCount() -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM memory_edges", -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
    }

    // MARK: - Entity Extraction from Content

    /// Extract entities and relationships from memory content and add them to the graph.
    func extractAndStore(from content: String) {
        let entities = extractEntities(from: content)
        guard entities.count >= 2 else { return }

        // Create co-occurrence edges between entities found in the same content
        for i in 0..<entities.count {
            for j in (i + 1)..<entities.count {
                addEdge(
                    from: entities[i],
                    to: entities[j],
                    relationship: "co_occurs"
                )
            }
        }
    }

    // MARK: - Private

    private func extractEntities(from content: String) -> [String] {
        var entities: [String] = []
        let nsContent = content as NSString

        // File paths
        if let regex = try? NSRegularExpression(pattern: #"(?:^|[\s(])([/~][^\s,)]+\.\w{1,10})"#) {
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches.prefix(5) {
                if match.numberOfRanges > 1 {
                    entities.append(nsContent.substring(with: match.range(at: 1)))
                }
            }
        }

        // Function/type names (PascalCase or camelCase identifiers)
        if let regex = try? NSRegularExpression(pattern: #"\b([A-Z][a-zA-Z0-9]+(?:\.[a-zA-Z]+)?)\b"#) {
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches.prefix(5) {
                let name = nsContent.substring(with: match.range(at: 1))
                if name.count >= 3, name.count <= 60 {
                    entities.append(name)
                }
            }
        }

        // Package names (from import/require/use statements)
        if let regex = try? NSRegularExpression(pattern: #"(?:import|require|use)\s+([A-Za-z][A-Za-z0-9_./]+)"#) {
            let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
            for match in matches.prefix(3) {
                if match.numberOfRanges > 1 {
                    entities.append("pkg:" + nsContent.substring(with: match.range(at: 1)))
                }
            }
        }

        return Array(Set(entities)) // deduplicate
    }

    private func inferEntityType(_ entity: String) -> MemoryGraphNode.EntityType {
        if entity.contains("/") || entity.contains(".swift") || entity.contains(".ts") || entity.contains(".py") {
            return .file
        }
        if entity.hasPrefix("pkg:") {
            return .package
        }
        if entity.first?.isUppercase == true && entity.contains(".") {
            return .function
        }
        if entity.lowercased().contains("error") || entity.lowercased().contains("fail") {
            return .error
        }
        if entity.first?.isUppercase == true {
            return .pattern
        }
        return .unknown
    }

    private func findEdge(from: String, to: String, relationship: String) -> MemoryGraphEdge? {
        guard let db else { return nil }
        let sql = "SELECT id, from_entity, to_entity, relationship, weight, timestamp FROM memory_edges WHERE from_entity = ? AND to_entity = ? AND relationship = ? LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (from as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (to as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (relationship as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return readEdge(from: stmt)
        }
        return nil
    }

    private func readEdge(from stmt: OpaquePointer?) -> MemoryGraphEdge? {
        guard let stmt,
              let idStr = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idStr),
              let fromEntity = sqlite3_column_text(stmt, 1).map({ String(cString: $0) }),
              let toEntity = sqlite3_column_text(stmt, 2).map({ String(cString: $0) }),
              let relationship = sqlite3_column_text(stmt, 3).map({ String(cString: $0) }) else { return nil }

        return MemoryGraphEdge(
            id: id,
            fromEntity: fromEntity,
            toEntity: toEntity,
            relationship: relationship,
            weight: Float(sqlite3_column_double(stmt, 4)),
            timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
        )
    }

    private func execute(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }
}
