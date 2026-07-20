import Darwin
import Foundation

/// A process-wide advisory lock.  The descriptor, rather than a pathname, is
/// locked so independently launched copies of the app serialize state changes.
final class DurableInstallationLock {
    private let descriptor: Int32

    init(url: URL) throws {
        try POSIXFileSafety.requireSafeAncestors(of: url)
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { throw DurableInstallationError.lockFailed(url.path) }

        var info = Darwin.stat()
        guard Darwin.fstat(descriptor, &info) == 0 else {
            let error = DurableInstallationError.io(operation: "fstat \(url.path)", code: errno)
            Darwin.close(descriptor)
            throw error
        }
        guard POSIXFileSafety.isRegularFile(info), info.st_uid == POSIXFileSafety.currentUserID else {
            Darwin.close(descriptor)
            throw DurableInstallationError.unsafePath(url.path)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw DurableInstallationError.lockFailed(url.path)
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}

/// Local durable state for person-approved operations and ADR 0009's bounded
/// pristine launch-time installation exception.
final class DurableInstallationStore {
    private let fileManager: FileManager
    let directory: URL

    init(applicationSupportDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let base: URL
        if let applicationSupportDirectory {
            base = applicationSupportDirectory
        } else if let discovered = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            base = discovered
        } else {
            throw DurableInstallationError.invalidApplicationSupportDirectory("Application Support")
        }
        directory = base
            .appendingPathComponent("AgentIsland", isDirectory: true)
            .appendingPathComponent("IntegrationInstallations", isDirectory: true)
        try createPrivateDirectory()
    }

    func withExclusiveLock<Result>(_ body: () throws -> Result) throws -> Result {
        let lock = try DurableInstallationLock(url: directory.appendingPathComponent(".installation.lock"))
        _ = lock
        return try body()
    }

    func saveManifest(_ manifest: DurableInstallationManifest) throws {
        guard manifest.schemaVersion == DurableInstallationManifest.currentSchemaVersion else {
            throw DurableInstallationError.unsupportedSchema(found: manifest.schemaVersion, supported: DurableInstallationManifest.currentSchemaVersion)
        }
        try save(manifest, named: "manifest-\(try safeComponent(manifest.installationID)).json")
    }

    func manifest(installationID: String) throws -> DurableInstallationManifest? {
        let loaded = try load(DurableInstallationManifest.self, named: "manifest-\(try safeComponent(installationID)).json")
        if let loaded, loaded.schemaVersion != DurableInstallationManifest.currentSchemaVersion {
            throw DurableInstallationError.unsupportedSchema(found: loaded.schemaVersion, supported: DurableInstallationManifest.currentSchemaVersion)
        }
        return loaded
    }

    func saveJournal(_ journal: DurableInstallationJournal) throws {
        guard journal.schemaVersion == DurableInstallationJournal.currentSchemaVersion else {
            throw DurableInstallationError.unsupportedSchema(found: journal.schemaVersion, supported: DurableInstallationJournal.currentSchemaVersion)
        }
        try save(journal, named: "journal-\(try safeComponent(journal.transactionID)).json")
    }

    func journal(transactionID: String) throws -> DurableInstallationJournal? {
        let loaded = try load(DurableInstallationJournal.self, named: "journal-\(try safeComponent(transactionID)).json")
        if let loaded, loaded.schemaVersion != DurableInstallationJournal.currentSchemaVersion {
            throw DurableInstallationError.unsupportedSchema(found: loaded.schemaVersion, supported: DurableInstallationJournal.currentSchemaVersion)
        }
        return loaded
    }

    func journals() throws -> [DurableInstallationJournal] {
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("journal-") && $0.hasSuffix(".json") }
            .sorted()
        return try names.compactMap { try load(DurableInstallationJournal.self, named: $0) }
    }

    func removeJournal(transactionID: String) throws {
        let url = directory.appendingPathComponent("journal-\(try safeComponent(transactionID)).json")
        guard POSIXFileSafety.exists(url) else { return }
        let status = try POSIXFileSafety.lstat(url)
        guard POSIXFileSafety.isRegularFile(status), !POSIXFileSafety.isSymlink(status),
              status.st_uid == POSIXFileSafety.currentUserID else {
            throw DurableInstallationError.unsafePath(url.path)
        }
        guard url.path.withCString({ Darwin.unlink($0) }) == 0 else {
            throw DurableInstallationError.io(operation: "remove durable installation journal", code: errno)
        }
        try POSIXFileSafety.fsyncDirectory(directory)
    }

    private func createPrivateDirectory() throws {
        try POSIXFileSafety.requireSafeAncestors(of: directory)
        if !POSIXFileSafety.exists(directory) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        try POSIXFileSafety.requireOwnedDirectory(directory, privateToOwner: true)
    }

    private func safeComponent(_ value: String) throws -> String {
        guard !value.isEmpty, !value.contains("/"), !value.contains("\\"), value != ".", value != ".." else {
            throw DurableInstallationError.unsafePath(value)
        }
        return value
    }

    private func save<T: Encodable>(_ value: T, named name: String) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(value)
        } catch {
            throw DurableInstallationError.encodingFailed
        }
        try atomicWrite(data, to: directory.appendingPathComponent(name))
    }

    private func load<T: Decodable>(_ type: T.Type, named name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard POSIXFileSafety.exists(url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: POSIXFileSafety.readOwnedRegularFile(url))
        } catch let error as DurableInstallationError {
            throw error
        } catch {
            throw DurableInstallationError.decodingFailed
        }
    }

    private func atomicWrite(_ data: Data, to destination: URL) throws {
        try POSIXFileSafety.requireOwnedDirectory(directory, privateToOwner: true)
        let expectedDestination: stat?
        if POSIXFileSafety.exists(destination) {
            let current = try POSIXFileSafety.lstat(destination)
            guard POSIXFileSafety.isRegularFile(current), !POSIXFileSafety.isSymlink(current) else {
                throw DurableInstallationError.unsafePath(destination.path)
            }
            guard current.st_uid == POSIXFileSafety.currentUserID else {
                throw DurableInstallationError.foreignOwner(path: destination.path, owner: current.st_uid)
            }
            expectedDestination = current
        } else {
            expectedDestination = nil
        }

        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let openedDescriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard openedDescriptor >= 0 else { throw DurableInstallationError.io(operation: "create temporary state", code: errno) }
        var descriptor: Int32? = openedDescriptor
        do {
            try POSIXFileSafety.writeAll(data, to: openedDescriptor)
            guard Darwin.fsync(openedDescriptor) == 0 else { throw DurableInstallationError.io(operation: "fsync temporary state", code: errno) }
            guard Darwin.close(openedDescriptor) == 0 else { throw DurableInstallationError.io(operation: "close temporary state", code: errno) }
            descriptor = nil
            if let expectedDestination {
                let immediate = try POSIXFileSafety.lstat(destination)
                guard immediate.st_dev == expectedDestination.st_dev, immediate.st_ino == expectedDestination.st_ino,
                      POSIXFileSafety.isRegularFile(immediate), !POSIXFileSafety.isSymlink(immediate),
                      immediate.st_uid == POSIXFileSafety.currentUserID else {
                    throw DurableInstallationError.configurationChanged(destination.path)
                }
            } else if POSIXFileSafety.exists(destination) {
                throw DurableInstallationError.configurationChanged(destination.path)
            }
            try rename(temporary, to: destination)
            try POSIXFileSafety.fsyncDirectory(directory)
        } catch {
            if let descriptor { _ = Darwin.close(descriptor) }
            _ = temporary.path.withCString { Darwin.unlink($0) }
            throw error
        }
    }

    private func rename(_ source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else { throw DurableInstallationError.io(operation: "rename durable installation state", code: errno) }
    }
}
