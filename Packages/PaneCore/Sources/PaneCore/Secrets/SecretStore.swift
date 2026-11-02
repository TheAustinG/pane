import Foundation

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

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func string(for key: SecretKey) throws -> String? {
        nil
    }

    public func setString(_ value: String?, for key: SecretKey) throws {}
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
