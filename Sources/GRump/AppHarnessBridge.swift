import Foundation
import GRumpKit

/// The GUI's compatibility seam into the extracted runtime. New providers run
/// here first; legacy handlers remain only for capabilities not migrated yet.
actor AppHarnessBridge {
    static let shared = AppHarnessBridge()
    static let routedNames = WorkspaceToolProvider.names.union(UtilityToolProvider.names)
    private var runtimes: [String: HarnessRuntime] = [:]

    func execute(name: String, arguments: String, workspace: String) async -> String? {
        guard Self.routedNames.contains(name), let data = arguments.data(using: .utf8),
              let value = try? JSONValue.decode(data: data) else { return nil }
        do {
            let root = URL(fileURLWithPath: workspace.isEmpty ? FileManager.default.currentDirectoryPath : workspace).standardizedFileURL
            let runtime: HarnessRuntime
            if let cached = runtimes[root.path] { runtime = cached }
            else {
                runtime = try await HarnessRuntime.create(workspace: root, approvalProvider: GUIHostApprovalProvider())
                runtimes[root.path] = runtime
            }
            let result = await runtime.executor.execute(.init(name: name, arguments: value), context: runtime.context, requireActive: false)
            return result.content.compactMap(\.text).joined(separator: "\n")
        } catch { return "Error: \(error)" }
    }
}

private struct GUIHostApprovalProvider: ApprovalProvider {
    /// ChatViewModel has already applied the GUI conscience/daemon gates before
    /// reaching the bridge. This provider acknowledges that host decision.
    func requestApproval(_ request: ApprovalRequest) async -> ApprovalDecision { .approved }
}
