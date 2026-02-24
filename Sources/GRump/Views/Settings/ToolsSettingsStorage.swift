import Foundation

/// User-level tool enable/disable preferences. Stored in UserDefaults as a denylist:
/// tools in this list are disabled. All tools are enabled by default when denylist is empty.
enum ToolsSettingsStorage {
    private static let denylistKey = "UserToolDenylist"

    /// Load the set of tool names the user has disabled.
    static func loadDenylist() -> Set<String> {
        guard let arr = UserDefaults.standard.array(forKey: denylistKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    /// Save the denylist. Pass the set of disabled tool names.
    static func saveDenylist(_ denylist: Set<String>) {
        UserDefaults.standard.set(Array(denylist), forKey: denylistKey)
    }

    /// Returns true if the tool is enabled (not in denylist).
    static func isEnabled(_ toolName: String) -> Bool {
        !loadDenylist().contains(toolName)
    }

    /// Toggle a tool: if currently enabled, add to denylist; if disabled, remove from denylist.
    /// Returns the new enabled state.
    @discardableResult
    static func toggle(_ toolName: String) -> Bool {
        var set = loadDenylist()
        if set.contains(toolName) {
            set.remove(toolName)
        } else {
            set.insert(toolName)
        }
        saveDenylist(set)
        return !set.contains(toolName)
    }

    /// Set enabled state for a tool.
    static func setEnabled(_ toolName: String, enabled: Bool) {
        var set = loadDenylist()
        if enabled {
            set.remove(toolName)
        } else {
            set.insert(toolName)
        }
        saveDenylist(set)
    }

    /// Clear the denylist (enable all tools).
    static func clearDenylist() {
        saveDenylist([])
    }
}
