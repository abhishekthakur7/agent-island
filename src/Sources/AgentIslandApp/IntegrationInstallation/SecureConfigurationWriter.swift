import CryptoKit
import Darwin
import Foundation

/// The facts that must remain true from review through the last possible
/// moment before replacement.  It deliberately contains no configuration
/// body, only the SHA-256 of that body.
struct SecureConfigurationPrecondition: Equatable, Sendable {
    let path: URL
    let identity: DurableFileIdentity
}

/// Replaces a single user-owned regular configuration file without following
/// links.  Files with extended attributes or extended ACL entries are refused:
/// silently dropping either during an atomic replacement would be unsafe.
final class SecureConfigurationWriter {
    func precondition(for target: URL) throws -> SecureConfigurationPrecondition {
        let identity = try inspect(target)
        return SecureConfigurationPrecondition(path: target, identity: identity)
    }

    func replace(_ data: Data, at target: URL, expecting precondition: SecureConfigurationPrecondition) throws {
        guard target.standardizedFileURL == precondition.path.standardizedFileURL else {
            throw DurableInstallationError.configurationChanged(target.path)
        }
        try POSIXFileSafety.requireSafeAncestors(of: target)
        try POSIXFileSafety.requireOwnedDirectory(target.deletingLastPathComponent())
        let initial = try inspect(target)
        guard initial == precondition.identity else { throw DurableInstallationError.configurationChanged(target.path) }

        let parent = target.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".agent-island-\(UUID().uuidString).tmp")
        let openedDescriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(precondition.identity.mode))
        }
        guard openedDescriptor >= 0 else { throw DurableInstallationError.io(operation: "create temporary configuration", code: errno) }
        var descriptor: Int32? = openedDescriptor
        do {
            try POSIXFileSafety.writeAll(data, to: openedDescriptor)
            guard Darwin.fchown(openedDescriptor, precondition.identity.owner, precondition.identity.group) == 0 else {
                throw DurableInstallationError.io(operation: "preserve configuration ownership", code: errno)
            }
            guard Darwin.fchmod(openedDescriptor, mode_t(precondition.identity.mode)) == 0 else {
                throw DurableInstallationError.io(operation: "preserve configuration mode", code: errno)
            }
            guard Darwin.fsync(openedDescriptor) == 0 else {
                throw DurableInstallationError.io(operation: "fsync temporary configuration", code: errno)
            }
            guard Darwin.close(openedDescriptor) == 0 else {
                throw DurableInstallationError.io(operation: "close temporary configuration", code: errno)
            }
            descriptor = nil

            // This repeat inspection is intentionally adjacent to rename.
            // It detects replacement, ownership, permission, content, ACL,
            // or xattr drift that occurred while the replacement was staged.
            let immediate = try inspect(target)
            guard immediate == precondition.identity else {
                throw DurableInstallationError.configurationChanged(target.path)
            }
            try rename(temporary, to: target)
            try POSIXFileSafety.fsyncDirectory(parent)
            let written = try inspect(target)
            guard written.digest == digest(data), written.mode == precondition.identity.mode,
                  written.owner == precondition.identity.owner, written.group == precondition.identity.group else {
                throw DurableInstallationError.configurationChanged(target.path)
            }
        } catch {
            if let descriptor { _ = Darwin.close(descriptor) }
            _ = temporary.path.withCString { Darwin.unlink($0) }
            throw error
        }
    }

    private func inspect(_ target: URL) throws -> DurableFileIdentity {
        try POSIXFileSafety.requireSafeAncestors(of: target)
        guard POSIXFileSafety.exists(target) else { throw DurableInstallationError.configurationMissing(target.path) }
        let linkStatus = try POSIXFileSafety.lstat(target)
        guard POSIXFileSafety.isRegularFile(linkStatus), !POSIXFileSafety.isSymlink(linkStatus) else {
            throw DurableInstallationError.invalidFileType(target.path)
        }
        guard linkStatus.st_uid == POSIXFileSafety.currentUserID else {
            throw DurableInstallationError.foreignOwner(path: target.path, owner: linkStatus.st_uid)
        }
        try requireNoUnpreservedMetadata(target)

        let descriptor = target.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw DurableInstallationError.io(operation: "open configuration", code: errno) }
        defer { _ = Darwin.close(descriptor) }
        var openedStatus = Darwin.stat()
        guard Darwin.fstat(descriptor, &openedStatus) == 0 else {
            throw DurableInstallationError.io(operation: "fstat configuration", code: errno)
        }
        guard POSIXFileSafety.isRegularFile(openedStatus), sameObject(linkStatus, openedStatus) else {
            throw DurableInstallationError.configurationChanged(target.path)
        }
        let contents: Data
        do {
            contents = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
        } catch {
            throw DurableInstallationError.io(operation: "read configuration", code: errno)
        }
        var finalStatus = Darwin.stat()
        guard Darwin.fstat(descriptor, &finalStatus) == 0, sameObject(openedStatus, finalStatus) else {
            throw DurableInstallationError.configurationChanged(target.path)
        }
        return DurableFileIdentity(stat: finalStatus, digest: digest(contents))
    }

    private func requireNoUnpreservedMetadata(_ target: URL) throws {
        let xattrSize = target.path.withCString { Darwin.listxattr($0, nil, 0, 0) }
        guard xattrSize >= 0 else { throw DurableInstallationError.io(operation: "listxattr \(target.path)", code: errno) }
        guard xattrSize == 0 else { throw DurableInstallationError.unsupportedMetadata(target.path) }

        let acl = target.path.withCString { Darwin.acl_get_file($0, ACL_TYPE_EXTENDED) }
        guard let acl else {
            // A file system that cannot report its ACLs cannot safely promise
            // to preserve them through replacement.
            throw DurableInstallationError.unsupportedMetadata(target.path)
        }
        defer { _ = Darwin.acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        let result = Darwin.acl_get_entry(acl, ACL_FIRST_ENTRY.rawValue, &entry)
        guard result >= 0 else { throw DurableInstallationError.io(operation: "inspect ACL \(target.path)", code: errno) }
        if result == 1 { throw DurableInstallationError.unsupportedMetadata(target.path) }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sameObject(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private func rename(_ source: URL, to destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else { throw DurableInstallationError.io(operation: "replace configuration", code: errno) }
    }
}
