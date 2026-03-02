import XCTest
@testable import GRump

final class MCPServerConfigTests: XCTestCase {

    // MARK: - Transport Codable

    func testStdioTransportEncodeDecode() throws {
        let transport = MCPServerConfig.Transport.stdio(command: "npx", args: ["-y", "@mcp/server-memory"])
        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: data)
        XCTAssertEqual(transport, decoded)
    }

    func testHTTPTransportEncodeDecode() throws {
        let transport = MCPServerConfig.Transport.http(url: "http://localhost:8765")
        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: data)
        XCTAssertEqual(transport, decoded)
    }

    func testStdioTransportDecodeFromJSON() throws {
        let json = """
        {"type": "stdio", "command": "npx", "args": ["-y", "test"]}
        """.data(using: .utf8)!
        let transport = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: json)
        if case .stdio(let command, let args) = transport {
            XCTAssertEqual(command, "npx")
            XCTAssertEqual(args, ["-y", "test"])
        } else {
            XCTFail("Expected stdio transport")
        }
    }

    func testHTTPTransportDecodeFromJSON() throws {
        let json = """
        {"type": "http", "url": "http://localhost:3000"}
        """.data(using: .utf8)!
        let transport = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: json)
        if case .http(let url) = transport {
            XCTAssertEqual(url, "http://localhost:3000")
        } else {
            XCTFail("Expected http transport")
        }
    }

    func testStdioTransportDecodeEmptyArgs() throws {
        let json = """
        {"type": "stdio", "command": "myserver"}
        """.data(using: .utf8)!
        let transport = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: json)
        if case .stdio(let command, let args) = transport {
            XCTAssertEqual(command, "myserver")
            XCTAssertEqual(args, [])
        } else {
            XCTFail("Expected stdio transport")
        }
    }

    func testWebSocketTransportDecodeFromJSON() throws {
        let json = """
        {"type": "websocket", "url": "ws://localhost:18789"}
        """.data(using: .utf8)!
        let transport = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: json)
        if case .websocket(let url) = transport {
            XCTAssertEqual(url, "ws://localhost:18789")
        } else {
            XCTFail("Expected websocket transport")
        }
    }

    func testWebSocketTransportEncodeDecode() throws {
        let transport = MCPServerConfig.Transport.websocket(url: "ws://localhost:18789")
        let data = try JSONEncoder().encode(transport)
        let decoded = try JSONDecoder().decode(MCPServerConfig.Transport.self, from: data)
        XCTAssertEqual(transport, decoded)
    }

    func testUnknownTransportThrows() {
        let json = """
        {"type": "grpc", "url": "grpc://localhost"}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(MCPServerConfig.Transport.self, from: json))
    }

    // MARK: - MCPServerConfig Codable

    func testConfigEncodeDecode() throws {
        let config = MCPServerConfig(
            id: "test",
            name: "Test Server",
            enabled: true,
            transport: .stdio(command: "npx", args: ["-y", "test"])
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }

    func testConfigDisabled() throws {
        let config = MCPServerConfig(
            id: "disabled-server",
            name: "Disabled",
            enabled: false,
            transport: .http(url: "http://example.com")
        )
        XCTAssertFalse(config.enabled)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(MCPServerConfig.self, from: data)
        XCTAssertFalse(decoded.enabled)
    }

    // MARK: - MCPServersFile

    func testServersFileEncodeDecode() throws {
        let file = MCPServersFile(servers: [
            MCPServerConfig(id: "a", name: "A", enabled: true,
                          transport: .stdio(command: "cmd", args: [])),
            MCPServerConfig(id: "b", name: "B", enabled: false,
                          transport: .http(url: "http://localhost")),
        ])
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(MCPServersFile.self, from: data)
        XCTAssertEqual(decoded.servers.count, 2)
        XCTAssertEqual(decoded.servers[0].id, "a")
        XCTAssertEqual(decoded.servers[1].id, "b")
    }

    // MARK: - Presets

    func testPresetsAllHaveUniqueIDs() {
        let ids = MCPServerPreset.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All preset IDs should be unique")
    }

    func testPresetsAllHaveNames() {
        for preset in MCPServerPreset.all {
            XCTAssertFalse(preset.name.isEmpty, "Preset \(preset.id) should have a name")
        }
    }

    func testPresetsAllHaveDescriptions() {
        for preset in MCPServerPreset.all {
            XCTAssertFalse(preset.description.isEmpty, "Preset \(preset.id) should have a description")
        }
    }

    func testPresetsAllHaveIcons() {
        for preset in MCPServerPreset.all {
            XCTAssertFalse(preset.icon.isEmpty, "Preset \(preset.id) should have an icon")
        }
    }

    func testPresetToConfigProducesValidConfig() {
        for preset in MCPServerPreset.all {
            let config = preset.toConfig()
            XCTAssertEqual(config.id, preset.id, "Config id should match preset id for \(preset.id)")
            XCTAssertEqual(config.name, preset.name, "Config name should match preset name for \(preset.id)")
            XCTAssertTrue(config.enabled, "Config should be enabled by default for \(preset.id)")
        }
    }

    func testMemoryPresetUsesStdio() {
        let preset = MCPServerPreset.all.first { $0.id == "memory" }!
        let config = preset.toConfig()
        if case .stdio(let command, _) = config.transport {
            XCTAssertEqual(command, "npx")
        } else {
            XCTFail("Memory preset should use stdio transport")
        }
    }

    func testManusPresetUsesHTTP() {
        let preset = MCPServerPreset.all.first { $0.id == "manus" }!
        let config = preset.toConfig()
        if case .http(let url) = config.transport {
            XCTAssertTrue(url.contains("localhost"), "Manus should connect to localhost")
        } else {
            XCTFail("Manus preset should use http transport")
        }
    }

    func testN8NPresetUsesHTTP() {
        let preset = MCPServerPreset.all.first { $0.id == "n8n" }!
        let config = preset.toConfig()
        if case .http(let url) = config.transport {
            XCTAssertTrue(url.contains("5678"), "n8n should use port 5678")
        } else {
            XCTFail("n8n preset should use http transport")
        }
    }

    // MARK: - Equatable

    func testTransportEquatable() {
        let a = MCPServerConfig.Transport.stdio(command: "npx", args: ["a"])
        let b = MCPServerConfig.Transport.stdio(command: "npx", args: ["a"])
        let c = MCPServerConfig.Transport.stdio(command: "npx", args: ["b"])
        let d = MCPServerConfig.Transport.http(url: "http://localhost")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }
}
