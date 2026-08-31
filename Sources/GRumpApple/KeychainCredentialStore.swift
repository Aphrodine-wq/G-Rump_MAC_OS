import Foundation
import GRumpCore
#if canImport(Security)
import Security
#endif

public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    public init(service: String = "com.grump.harness") { self.service = service }

    public func value(for key: String) async throws -> String? {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return ProcessInfo.processInfo.environment[key] }
        guard status == errSecSuccess, let data = item as? Data else { throw ToolError(code: .executionFailed, message: "Keychain read failed (\(status))") }
        return String(data: data, encoding: .utf8)
        #else
        return ProcessInfo.processInfo.environment[key]
        #endif
    }

    public func setValue(_ value: String, for key: String) async throws {
        #if canImport(Security)
        let lookup: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(lookup as CFDictionary)
        var item = lookup; item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ToolError(code: .executionFailed, message: "Keychain write failed (\(status))") }
        #else
        throw ToolError(code: .unavailable, message: "No credential backend is configured")
        #endif
    }
}
