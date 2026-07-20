import Foundation

enum InstallationConfigurationTarget: Equatable, Sendable {
    case existing(URL)
    case missing(URL)
}

/// Resolves only documented user-scope locations.  It never scans a product
/// data root, guesses a project scope, or creates a configuration file.
struct UserInstallationConfigurationResolver {
    let homeDirectory: URL

    init(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    func resolve(for product: DurableInstallationProduct) throws -> InstallationConfigurationTarget {
        try POSIXFileSafety.requireOwnedDirectory(homeDirectory)
        switch product {
        case .claude:
            return try resolveClaude()
        case .codex:
            return try inspect(homeDirectory.appendingPathComponent(".codex/hooks.json"))
        case .cursor:
            return try inspect(homeDirectory.appendingPathComponent(".cursor/hooks.json"))
        }
    }

    private func resolveClaude() throws -> InstallationConfigurationTarget {
        let json = try inspect(homeDirectory.appendingPathComponent(".claude/settings.json"))
        let jsonc = try inspect(homeDirectory.appendingPathComponent(".claude/settings.jsonc"))
        if case .existing = json, case .existing = jsonc {
            throw DurableInstallationError.configurationAmbiguous([
                homeDirectory.appendingPathComponent(".claude/settings.json").path,
                homeDirectory.appendingPathComponent(".claude/settings.jsonc").path,
            ])
        }
        if case .existing = json { return json }
        if case .existing = jsonc { return jsonc }
        return json
    }

    private func inspect(_ target: URL) throws -> InstallationConfigurationTarget {
        try POSIXFileSafety.requireSafeAncestors(of: target)
        try POSIXFileSafety.requireOwnedAncestors(of: target, within: homeDirectory)
        guard POSIXFileSafety.exists(target) else { return .missing(target) }
        let value = try POSIXFileSafety.lstat(target)
        guard POSIXFileSafety.isRegularFile(value), !POSIXFileSafety.isSymlink(value) else {
            throw DurableInstallationError.invalidFileType(target.path)
        }
        guard value.st_uid == POSIXFileSafety.currentUserID else {
            throw DurableInstallationError.foreignOwner(path: target.path, owner: value.st_uid)
        }
        return .existing(target)
    }
}
