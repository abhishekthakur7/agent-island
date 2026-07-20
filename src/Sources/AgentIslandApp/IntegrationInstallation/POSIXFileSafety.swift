import Darwin
import Foundation

enum POSIXFileSafety {
    static var currentUserID: uid_t { getuid() }

    static func lstat(_ url: URL) throws -> stat {
        var value = Darwin.stat()
        let result = url.path.withCString { Darwin.lstat($0, &value) }
        guard result == 0 else { throw DurableInstallationError.io(operation: "lstat \(url.path)", code: errno) }
        return value
    }

    static func fileStatus(_ url: URL) throws -> stat {
        var value = Darwin.stat()
        let result = url.path.withCString { stat($0, &value) }
        guard result == 0 else { throw DurableInstallationError.io(operation: "stat \(url.path)", code: errno) }
        return value
    }

    static func exists(_ url: URL) -> Bool {
        var value = Darwin.stat()
        return url.path.withCString { Darwin.lstat($0, &value) == 0 }
    }

    static func isDirectory(_ value: stat) -> Bool { (value.st_mode & S_IFMT) == S_IFDIR }
    static func isRegularFile(_ value: stat) -> Bool { (value.st_mode & S_IFMT) == S_IFREG }
    static func isSymlink(_ value: stat) -> Bool { (value.st_mode & S_IFMT) == S_IFLNK }
    static func mode(_ value: stat) -> UInt16 { UInt16(value.st_mode & 0o7777) }

    static func requireOwnedDirectory(_ url: URL, privateToOwner: Bool = false) throws {
        let value = try lstat(url)
        guard isDirectory(value), !isSymlink(value) else { throw DurableInstallationError.invalidFileType(url.path) }
        guard value.st_uid == currentUserID else { throw DurableInstallationError.foreignOwner(path: url.path, owner: value.st_uid) }
        if privateToOwner, mode(value) & 0o077 != 0 {
            throw DurableInstallationError.permissionDenied(path: url.path, mode: mode(value))
        }
    }

    /// Validates every existing path component without resolving symlinks.
    /// System-owned ancestors (for example `/` and `/Users`) are allowed; the
    /// caller separately requires ownership for its actual private directory.
    static func requireSafeAncestors(of target: URL, includingTarget: Bool = false) throws {
        var cursor = includingTarget ? target : target.deletingLastPathComponent()
        while true {
            if exists(cursor) {
                let value = try lstat(cursor)
                guard !isSymlink(value), isDirectory(value) else { throw DurableInstallationError.unsafePath(cursor.path) }
            }
            // Terminate at the filesystem root. `deletingLastPathComponent()`
            // no longer reports a fixpoint at "/" (it yields "/.." and would
            // walk an unbounded "/../.." chain forever), so root must be the
            // explicit stop after it has been validated above.
            if cursor.path == "/" { break }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path || parent.path.hasSuffix("/..") { break }
            cursor = parent
        }
    }

    /// Used for user-scope product configuration.  Every existing component
    /// below the known user home must be a user-owned directory, preventing a
    /// writable foreign-owned `.claude`, `.codex`, or `.cursor` ancestor.
    static func requireOwnedAncestors(of target: URL, within boundary: URL) throws {
        let root = boundary.standardizedFileURL
        let candidate = target.standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(prefix) else {
            throw DurableInstallationError.unsafePath(candidate.path)
        }
        var cursor = candidate.deletingLastPathComponent()
        while true {
            if exists(cursor) { try requireOwnedDirectory(cursor) }
            if cursor.path == root.path { break }
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { throw DurableInstallationError.unsafePath(candidate.path) }
            cursor = parent
        }
    }

    static func fsyncDirectory(_ directory: URL) throws {
        let descriptor = directory.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw DurableInstallationError.io(operation: "open directory \(directory.path)", code: errno) }
        defer { Darwin.close(descriptor) }
        guard Darwin.fsync(descriptor) == 0 else { throw DurableInstallationError.io(operation: "fsync directory \(directory.path)", code: errno) }
    }

    static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(descriptor, rawBuffer.baseAddress!.advanced(by: offset), rawBuffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw DurableInstallationError.io(operation: "write", code: errno)
                }
                offset += written
            }
        }
    }

    static func readOwnedRegularFile(_ url: URL) throws -> Data {
        let before = try lstat(url)
        guard isRegularFile(before), !isSymlink(before) else { throw DurableInstallationError.unsafePath(url.path) }
        guard before.st_uid == currentUserID else {
            throw DurableInstallationError.foreignOwner(path: url.path, owner: before.st_uid)
        }
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW) }
        guard descriptor >= 0 else { throw DurableInstallationError.io(operation: "open \(url.path)", code: errno) }
        defer { _ = Darwin.close(descriptor) }
        var opened = Darwin.stat()
        guard Darwin.fstat(descriptor, &opened) == 0 else { throw DurableInstallationError.io(operation: "fstat \(url.path)", code: errno) }
        guard isRegularFile(opened), opened.st_dev == before.st_dev, opened.st_ino == before.st_ino else {
            throw DurableInstallationError.configurationChanged(url.path)
        }
        let data: Data
        do {
            data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readToEnd() ?? Data()
        } catch {
            throw DurableInstallationError.io(operation: "read \(url.path)", code: errno)
        }
        var after = Darwin.stat()
        guard Darwin.fstat(descriptor, &after) == 0, after.st_dev == opened.st_dev, after.st_ino == opened.st_ino else {
            throw DurableInstallationError.configurationChanged(url.path)
        }
        return data
    }
}

struct DurableFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let owner: UInt32
    let group: UInt32
    let mode: UInt16
    let digest: String

    init(stat: stat, digest: String) {
        device = UInt64(stat.st_dev)
        inode = UInt64(stat.st_ino)
        owner = stat.st_uid
        group = stat.st_gid
        mode = POSIXFileSafety.mode(stat)
        self.digest = digest
    }
}
