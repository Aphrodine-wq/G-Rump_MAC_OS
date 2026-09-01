import XCTest
@testable import GRumpKit

final class GRumpKitSmokeTests: XCTestCase {
    func testCatalogPreservesAllToolNames() {
        XCTAssertEqual(BuiltinToolCatalog.definitions.count, 161)
        XCTAssertEqual(Set(BuiltinToolCatalog.definitions.map(\.name)).count, 161)
        for definition in BuiltinToolCatalog.definitions {
            XCTAssertFalse(definition.description.isEmpty, definition.name)
            XCTAssertEqual(definition.inputSchema["type"]?.stringValue, "object", definition.name)
            XCTAssertFalse(definition.pack.isEmpty, definition.name)
        }
    }

    func testGoldenCatalogDigest() throws {
        let fields: [JSONValue] = BuiltinToolCatalog.definitions.sorted { $0.name < $1.name }.map {
            ["name": .string($0.name), "description": .string($0.description), "schema": $0.inputSchema,
             "risk": .string($0.annotations.riskLevel.rawValue), "pack": .string($0.pack)]
        }
        let data = try JSONValue.array(fields).encoded()
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        XCTAssertEqual(String(hash, radix: 16), "243413fdc275d4db")
    }

    func testWorkspaceTraversalAndSymlinkEscapeAreDenied() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let context = ExecutionContext(workspaceRoots: [root], processRunner: FoundationProcessRunner(), credentialStore: NullCredentialStore(), logger: StderrLogger(), approvalProvider: DenyApprovalProvider())
        XCTAssertThrowsError(try context.resolveWorkspacePath("../escape"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try context.resolveWorkspacePath("link/secret"))
    }

    func testWriteNeedsApprovalButReadDoesNot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("a.txt"))
        let runtime = try await HarnessRuntime.create(workspace: root)
        let read = await runtime.executor.execute(.init(name: "read_file", arguments: ["path": "a.txt"]), context: runtime.context, requireActive: false)
        XCTAssertFalse(read.isError)
        let write = await runtime.executor.execute(.init(name: "write_file", arguments: ["path": "b.txt", "content": "no"]), context: runtime.context, requireActive: false)
        XCTAssertTrue(write.isError)
        XCTAssertEqual(write.structuredContent?["code"]?.stringValue, "approval_required")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path))
    }

    func testMCPNegotiatesBothProtocolEras() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try await HarnessRuntime.create(workspace: root)
        let server = GRumpMCPServer(registry: runtime.registry, executor: runtime.executor, context: runtime.context)
        for version in MCPProtocolVersion.allCases {
            let request: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": .string(version.rawValue)]]
            let response = await server.handle(request)
            XCTAssertEqual(response?["result"]?["protocolVersion"]?.stringValue, version.rawValue)
        }
    }

    func testInactiveToolsRemainReachableThroughGateway() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = try await HarnessRuntime.create(workspace: root)
        let active = await runtime.registry.definitions()
        XCTAssertFalse(active.contains { $0.name == "git_status" })
        let result = await runtime.executor.execute(.init(name: "grump_tools_call", arguments: ["name": "git_status", "arguments": .object([:])]), context: runtime.context)
        XCTAssertFalse(result.content.isEmpty)
        XCTAssertNotEqual(result.structuredContent?["code"]?.stringValue, "unknown_tool")
    }
}
