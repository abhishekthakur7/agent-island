import Foundation
import LocalProductDiscovery

/// Transient, current-run evidence that an Agent Product CLI is present.
/// This is deliberately separate from persisted integration intent, hook
/// configuration, negotiated health, and live Agent Sessions.
enum AtlasProductInstallationState: Equatable, Sendable {
    case unknown
    case checking(previous: ProductInstallationResult?)
    case result(ProductInstallationResult)

    var result: ProductInstallationResult? {
        switch self {
        case .unknown: nil
        case .checking(let previous): previous
        case .result(let result): result
        }
    }

    var title: String {
        switch self {
        case .unknown: "Not checked"
        case .checking: "Checking…"
        case .result(let result):
            switch result.status {
            case .verified: "Installed and verified"
            case .presentUnverified: "Executable found; verification failed"
            case .ambiguous: "Multiple installations found"
            case .notFound: "Not found"
            }
        }
    }

    var verifiedExecutablePath: String? {
        guard case .result(let result) = self, result.status == .verified else { return nil }
        return result.evidence?.path
    }
}

extension AtlasIntegrationKind {
    var productCLI: ProductCLI {
        switch self {
        case .claudeCode: .claudeCode
        case .codexCLI: .codexCLI
        case .cursor: .cursor
        }
    }
}

extension ProductInstallationSource {
    var atlasTitle: String {
        switch self {
        case .explicitPath: "Selected path"
        case .path: "Application PATH"
        case .userLocal: "User-local install"
        case .claudeLocal: "Claude installer"
        case .homebrew: "Homebrew"
        case .usrLocal: "/usr/local"
        case .usrBin: "/usr/bin"
        case .cursorApplications: "Cursor application"
        case .cursorUserApplications: "User Cursor application"
        }
    }
}

extension ProductInstallationReason {
    var atlasTitle: String {
        switch self {
        case .launchFailed: "The version probe could not start."
        case .nonZeroExit: "The version probe exited with an error."
        case .timedOut: "The version probe timed out."
        case .cancelled: "The version probe was cancelled."
        case .outputLimitExceeded: "The version probe produced too much output."
        case .identityMismatch: "The executable did not identify as this Agent Product."
        case .missingVersion: "The executable did not report a recognizable version."
        case .ambiguousCandidates: "Multiple distinct verified installations were found."
        case .unsafePath: "The executable path is not safe for automatic configuration."
        case .untrustedOrigin: "The executable origin is not approved for automatic configuration."
        case .identityUnavailable: "A stable executable identity could not be established."
        case .identityChanged: "The executable changed after it was detected."
        }
    }
}
