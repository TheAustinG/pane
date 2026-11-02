import Foundation
import Security
import Testing
@testable import PaneCore

@Suite("InMemorySecretStore")
struct InMemorySecretStoreTests {
    @Test func roundTrip() throws {
        let store = InMemorySecretStore()
        #expect(try store.string(for: .githubToken) == nil)
        try store.setString("abc", for: .githubToken)
        #expect(try store.string(for: .githubToken) == "abc")
        try store.setString("def", for: .githubToken)
        #expect(try store.string(for: .githubToken) == "def")
    }

    @Test func keysAreIndependent() throws {
        let store = InMemorySecretStore()
        try store.setString("a", for: .githubToken)
        try store.setString("b", for: .portainerToken)
        #expect(try store.string(for: .githubToken) == "a")
        #expect(try store.string(for: .portainerToken) == "b")
        #expect(try store.string(for: .homeAssistantToken) == nil)
    }

    @Test func nilDeletes() throws {
        let store = InMemorySecretStore()
        try store.setString("abc", for: .githubToken)
        try store.setString(nil, for: .githubToken)
        #expect(try store.string(for: .githubToken) == nil)
        try store.setString(nil, for: .githubToken)
    }
}

private enum KeychainProbe {
    /// An unsigned macOS test bundle has no keychain entitlement and fails with errSecMissingEntitlement.
    static let isAvailable: Bool = {
        let store = KeychainSecretStore(service: "dev.pane.tests.probe.\(UUID().uuidString)")
        do {
            try store.setString("probe", for: .githubToken)
            try store.setString(nil, for: .githubToken)
            return true
        } catch {
            return false
        }
    }()
}

@Suite("KeychainSecretStore")
struct KeychainSecretStoreTests {
    @Test(.enabled(if: KeychainProbe.isAvailable, "Keychain needs a signed host (errSecMissingEntitlement -34018 when unsigned)"))
    func roundTrip() throws {
        let store = KeychainSecretStore(service: "dev.pane.tests.\(UUID().uuidString)")
        defer { try? store.setString(nil, for: .githubToken) }
        #expect(try store.string(for: .githubToken) == nil)
        try store.setString("abc", for: .githubToken)
        #expect(try store.string(for: .githubToken) == "abc")
        try store.setString("def", for: .githubToken)
        #expect(try store.string(for: .githubToken) == "def")
        try store.setString(nil, for: .githubToken)
        #expect(try store.string(for: .githubToken) == nil)
        try store.setString(nil, for: .githubToken)
    }

    @Test func missingEntitlementCarriesTheStatus() {
        let error = KeychainError(status: errSecMissingEntitlement)
        #expect(error.status == -34018)
        #expect("\(error)" == "Keychain error -34018")
    }
}
