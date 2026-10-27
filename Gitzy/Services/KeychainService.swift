import Foundation
import Security
import os

/// Keeps the GitHub token in the Keychain. It is never written anywhere else and never logged.
///
/// The preferred home is the data protection keychain with "this device only, when unlocked".
/// That keychain needs an entitlement an app signed without an Apple Developer account does not have,
/// so when it refuses, the token goes into the regular login keychain instead.
/// `currentStorage()` tells the Settings screen which of the two is really in use.
nonisolated enum KeychainService {
    private static let service = Bundle.main.bundleIdentifier ?? "Gitzy"
    private static let account = "github-token"
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Gitzy", category: "keychain")

    nonisolated enum Storage: Equatable, Sendable {
        case dataProtection
        case login

        var label: String {
            switch self {
            case .dataProtection: return "data protection keychain (this device only)"
            case .login: return "login keychain"
            }
        }
    }

    nonisolated struct Failure: Error, Equatable {
        let status: OSStatus

        /// Apple's description of the error code. Contains no secrets.
        var message: String {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)"
        }
    }

    /// Saves the token, replacing any earlier one, and reports where it ended up.
    static func save(token: String) throws -> Storage {
        delete()
        let data = Data(token.utf8)

        var preferred = baseQuery(dataProtection: true)
        preferred[kSecValueData as String] = data
        preferred[kSecAttrLabel as String] = "Gitzy GitHub token"
        preferred[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let preferredStatus = SecItemAdd(preferred as CFDictionary, nil)
        if preferredStatus == errSecSuccess { return .dataProtection }
        logger.notice("Data protection keychain refused the token (status \(preferredStatus, privacy: .private)); using the login keychain")

        var fallback = baseQuery(dataProtection: false)
        fallback[kSecValueData as String] = data
        fallback[kSecAttrLabel as String] = "Gitzy GitHub token"
        let fallbackStatus = SecItemAdd(fallback as CFDictionary, nil)
        guard fallbackStatus == errSecSuccess else {
            logger.error("Login keychain refused the token (status \(fallbackStatus, privacy: .private))")
            throw Failure(status: fallbackStatus)
        }
        return .login
    }

    static func load() -> String? {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    /// Where a saved token lives, or nil when there is none. Reads attributes only, never the token itself.
    static func currentStorage() -> Storage? {
        let options: [(dataProtection: Bool, storage: Storage)] = [(true, .dataProtection), (false, .login)]
        for option in options {
            var query = baseQuery(dataProtection: option.dataProtection)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess { return option.storage }
        }
        return nil
    }

    static func delete() {
        for dataProtection in [true, false] {
            _ = SecItemDelete(baseQuery(dataProtection: dataProtection) as CFDictionary)
        }
    }

    private static func baseQuery(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}
