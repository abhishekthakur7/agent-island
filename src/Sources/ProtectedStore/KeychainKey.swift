import Foundation
import Security

/// Per-installation Keychain-held 32-byte SQLCipher key. Only `ProtectedStore`
/// ever loads this; no Adapter, UI, or Host code receives it (ADR 0008).
public final class PerInstallKeychainKey: @unchecked Sendable {
    private static let service = "com.agentisland.protected-store"
    private let account: String

    public init(account: String) { self.account = account }

    /// `errSecItemNotFound` means the key is genuinely gone — the only case
    /// that should ever offer a person a destructive discard/purge choice.
    /// Any other non-success status (locked keychain, daemon busy, an ACL/
    /// interaction failure) is a transient access problem, not evidence the
    /// key was lost, and must never be conflated with it.
    public func loadExisting() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw ProtectedStoreFailure.missingKeychainKey }
        guard status == errSecSuccess, let key = result as? Data, key.count == 32 else {
            throw ProtectedStoreFailure.keychainUnavailable
        }
        return key
    }

    /// Bootstrap only. A normal reopen must call `loadExisting` and never
    /// silently regenerate a missing key — that would make previously
    /// written protected bytes permanently unrecoverable without ever
    /// surfacing that loss to a person.
    public func createIfMissing() throws -> Data {
        do {
            return try loadExisting()
        } catch ProtectedStoreFailure.missingKeychainKey {
            // Genuinely absent — fall through and create one. Any other
            // thrown reason (a transient access problem) must propagate,
            // not be silently treated as "create a new key".
        }
        var key = Data(repeating: 0, count: 32)
        let randomStatus = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        guard randomStatus == errSecSuccess else { throw ProtectedStoreFailure.keychainUnavailable }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem { return try loadExisting() }
        guard status == errSecSuccess else { throw ProtectedStoreFailure.keychainUnavailable }
        return key
    }

    /// Deletes the Keychain item. Called by the real, person-confirmed
    /// purge path (`ProtectedStore.discardAllLocalDataAfterPersonConfirmedPurge`)
    /// and by fault-injection tests exercising the missing-key fail-closed
    /// path — the operation is identical either way.
    public func delete() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
