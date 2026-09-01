import Foundation
import GRumpCore
import GRumpTools

public enum StdioMCPTransport {
    public static func serve(_ server: GRumpMCPServer) async throws {
        let writer = StdioWriter()
        let notifications = Task {
            for await change in await server.registry.changes() {
                guard case .packsChanged(let revision, _) = change else { continue }
                await writer.write(["jsonrpc": "2.0", "method": "notifications/tools/list_changed", "params": ["catalogRevision": .integer(Int64(revision))]])
            }
        }
        defer { notifications.cancel() }
        var requests: [Task<Void, Never>] = []
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            requests.append(Task {
                do {
                    let message = try JSONValue.decode(data: Data(line.utf8))
                    let progress = message["params"]?["_meta"]?["progressToken"]
                    if let progress { await writer.write(progressNotification(progress, progress: 0, total: 1, message: "Tool started")) }
                    if let response = await server.handle(message) { await writer.write(response) }
                    if let progress { await writer.write(progressNotification(progress, progress: 1, total: 1, message: "Tool completed")) }
                } catch {
                    await writer.write(["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": .string("Parse error: \(error)")]])
                }
            })
        }
        for request in requests { await request.value }
    }

    private static func progressNotification(_ token: JSONValue, progress: Int64, total: Int64, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "method": "notifications/progress", "params": [
            "progressToken": token, "progress": .integer(progress), "total": .integer(total), "message": .string(message)
        ]]
    }
}

private actor StdioWriter {
    func write(_ value: JSONValue) {
        guard let data = try? value.encoded(), var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}
