#if os(macOS)
import Foundation
import Security

/// Keeps the pairing code in the macOS keychain (never in settings.json).
/// For automated tests, the environment variable TWINKEYS_PAIRING_CODE overrides it.
enum PairingStore {
    private static let service = "io.github.kajisho5.twinkeys"
    private static let account = "pairing-code"

    static var environmentCode: String? { ProcessInfo.processInfo.environment["TWINKEYS_PAIRING_CODE"] }

    static func load() -> String? {
        if let env = environmentCode { return env }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ code: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(code.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecAttrLabel as String] = "TwinKeys pairing code"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
#endif
