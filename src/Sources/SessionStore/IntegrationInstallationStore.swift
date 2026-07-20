import Foundation
import SessionDomain

/// Ticket-scoped manifest store. The canonical SessionStore remains the sole
/// writer for protected session facts; this actor provides the small manifest
/// boundary needed by the installation vertical slice without exposing a
/// database/key handle to UI or adapters.
public actor IntegrationInstallationStore {
    private var manifests: [String: OwnershipManifest]

    public init(manifests: [OwnershipManifest] = []) {
        self.manifests = manifests.reduce(into: [:]) { $0[$1.id] = $1 }
    }

    public func save(_ manifest: OwnershipManifest) {
        manifests[manifest.id] = manifest
    }

    public func manifest(id: String) -> OwnershipManifest? { manifests[id] }

    public func allManifests() -> [OwnershipManifest] {
        manifests.values.sorted { $0.id < $1.id }
    }

    public func remove(id: String) {
        manifests.removeValue(forKey: id)
    }

    /// Encodes only Ownership Manifest receipts and fingerprints. It cannot
    /// accidentally persist a full configuration document or credentials.
    public func protectedMinimalSnapshot() throws -> Data {
        try JSONEncoder().encode(allManifests())
    }

    public func replace(with data: Data) throws {
        let decoded = try JSONDecoder().decode([OwnershipManifest].self, from: data)
        manifests = decoded.reduce(into: [:]) { $0[$1.id] = $1 }
    }
}
