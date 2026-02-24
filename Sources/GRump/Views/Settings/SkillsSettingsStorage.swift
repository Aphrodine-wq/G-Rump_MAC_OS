import Foundation

/// Stores which skills are enabled (allowlist). Disabled by default; user enables skills.
enum SkillsSettingsStorage {
    private static let allowlistKey = "EnabledSkillsAllowlist"
    private static let hasSeededDefaultsKey = "SkillsAllowlistHasSeededDefaults"

    /// Default skills to enable on first run (Code Review, Documentation).
    static let defaultEnabledBaseIds: [String] = ["code-review", "documentation"]

    /// Load the set of enabled skill IDs. Seeds default allowlist on first run.
    static func loadAllowlist() -> Set<String> {
        if !UserDefaults.standard.bool(forKey: hasSeededDefaultsKey) {
            UserDefaults.standard.set(true, forKey: hasSeededDefaultsKey)
            let defaults = Set(defaultEnabledBaseIds.map { "global:\($0)" })
            saveAllowlist(defaults)
            return defaults
        }
        guard let arr = UserDefaults.standard.array(forKey: allowlistKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    /// Save the allowlist of enabled skill IDs.
    static func saveAllowlist(_ allowlist: Set<String>) {
        UserDefaults.standard.set(Array(allowlist), forKey: allowlistKey)
    }

    /// Returns true if the skill is enabled.
    static func isEnabled(_ skillId: String) -> Bool {
        loadAllowlist().contains(skillId)
    }

    /// Toggle a skill. Returns the new enabled state.
    @discardableResult
    static func toggle(_ skillId: String) -> Bool {
        var set = loadAllowlist()
        if set.contains(skillId) {
            set.remove(skillId)
        } else {
            set.insert(skillId)
        }
        saveAllowlist(set)
        return set.contains(skillId)
    }

    /// Set enabled state for a skill.
    static func setEnabled(_ skillId: String, enabled: Bool) {
        var set = loadAllowlist()
        if enabled {
            set.insert(skillId)
        } else {
            set.remove(skillId)
        }
        saveAllowlist(set)
    }
}
