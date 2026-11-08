import Foundation
import Security

/// Kite credentials in the macOS Keychain: this device only, readable only while the Mac is unlocked.
/// Never written to UserDefaults, files or logs.
public struct Keychain: Sendable {
    public enum Item: String, CaseIterable, Sendable { case apiKey, apiSecret, accessToken }

    public enum KeychainError: Error, LocalizedError {
        case status(OSStatus)
        public var errorDescription: String? {
            "Keychain error \((SecCopyErrorMessageString(statusCode, nil) as String?) ?? "\(statusCode)")"
        }
        var statusCode: OSStatus { if case .status(let s) = self { s } else { 0 } }
    }

    let service: String

    public init(service: String = "com.vikasghodke.FundScope.kite") {
        self.service = service
    }

    private func query(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: item.rawValue]
    }

    /// Nil when the item is missing or can't be read (e.g. after an ad-hoc-signed update); callers treat that as "not connected".
    public func get(_ item: Item) -> String? {
        var q = query(item)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String, for item: Item) throws {
        try delete(item)
        var q = query(item)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func delete(_ item: Item) throws {
        let status = SecItemDelete(query(item) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
