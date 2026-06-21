import Foundation
import Security

public protocol SecretStore: AnyObject {
    func setAPIKey(_ key: String)
    func apiKey() -> String?
}

public final class InMemorySecretStore: SecretStore {
    private var value: String?
    public init() {}
    public func setAPIKey(_ key: String) { value = key }
    public func apiKey() -> String? { value }
}

// Sendable: a final class whose only stored property is an immutable String,
// and whose methods call the thread-safe Keychain API. Lets the app capture it
// in the @Sendable key-provider closure passed to LiveGeminiService.
public final class KeychainSecretStore: SecretStore, Sendable {
    private let account: String
    public init(account: String = "gemini-api-key") { self.account = account }

    private func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "MemeFinder",
         kSecAttrAccount as String: account]
    }

    public func setAPIKey(_ key: String) {
        SecItemDelete(baseQuery() as CFDictionary)
        var q = baseQuery()
        q[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    public func apiKey() -> String? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
