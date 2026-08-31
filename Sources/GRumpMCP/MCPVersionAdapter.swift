import Foundation
import MCP
import GRumpCore

public enum MCPProtocolVersion: String, Codable, Sendable, CaseIterable {
    case november2025 = "2025-11-25"
    case july2026 = "2026-07-28"
}

/// Compatibility boundary around the official SDK. GRumpKit owns only the
/// stateless wire normalization needed to serve both supported protocol eras.
public enum MCPVersionAdapter {
    public static func negotiate(_ requested: String?) -> MCPProtocolVersion {
        if requested == MCPProtocolVersion.july2026.rawValue { return .july2026 }
        return .november2025
    }
}
