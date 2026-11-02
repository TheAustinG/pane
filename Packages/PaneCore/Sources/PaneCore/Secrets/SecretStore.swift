import Foundation
import Security

public struct SecretKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let homeAssistantToken = SecretKey(rawValue: "home-assistant.token")
    public static let githubToken = SecretKey(rawValue: "github.token")
    public static let portainerToken = SecretKey(rawValue: "portainer.token")
}

public protocol SecretStore: Sendable {
    func string(for key: SecretKey) throws -> String?
    /// Stores `value`, or deletes the entry when it is nil.
    func setString(_ value: String?, for key: SecretKey) throws
}

public struct KeychainError: Error, Hashable, Sendable, CustomStringConvertible {
    public let status: OSStatus

    public init(status: OSStatus) {
        self.status = status
    }

    public var description: String { "Keychain error \(status)" }
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func string(for key: SecretKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func setString(_ value: String?, for key: SecretKey) throws {
        guard let value else {
            let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
            return
        }
        let data = Data(value.utf8)
        let update = SecItemUpdate(
            baseQuery(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch update {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery(for: key)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        default:
            throw KeychainError(status: update)
        }
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SecretKey: String] = [:]

    public init() {}

    public func string(for key: SecretKey) throws -> String? {
        lock.withLock { values[key] }
    }

    public func setString(_ value: String?, for key: SecretKey) throws {
        lock.withLock { values[key] = value }
    }
}
