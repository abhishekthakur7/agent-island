import Foundation
import SessionDomain

/// A redacted, in-memory operational diagnostic record. Never carries
/// Interaction Content, credentials, raw external identifiers, paths, or
/// payloads — only stable reason codes and counts, matching the AB-118
/// privacy acceptance criterion.
public struct DiagnosticRecord: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case envelopeRejected
        case duplicateDeliverySuppressed
        case factCommitted
    }

    public let kind: Kind
    public let reason: EnvelopeValidationError?
    public let ledgerRevision: Int64?
    public let at: Date

    public init(kind: Kind, reason: EnvelopeValidationError?, ledgerRevision: Int64?, at: Date) {
        self.kind = kind
        self.reason = reason
        self.ledgerRevision = ledgerRevision
        self.at = at
    }
}
