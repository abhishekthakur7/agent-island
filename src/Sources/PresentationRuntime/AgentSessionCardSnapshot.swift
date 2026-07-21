import Foundation
import SessionDomain

/// The only shape SwiftUI/AppKit code ever sees. Identity
/// (`productNamespace`/`nativeSessionID`) is always present and never
/// invented; sourced display fields are optional and stay `nil` — never a
/// placeholder — when the Product hasn't supplied them.
public struct AgentSessionCardSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let productNamespace: String
    public let nativeSessionID: String
    public let execution: ExecutionState
    public let observation: ObservationState
    public let attention: AttentionState
    public let visibleLifecycle: VisibleLifecycleState
    public let lineage: LineageState
    public let displayTitle: String?
    public let hostLabel: String?
    public let sourceLastUpdated: Date?
    public let turns: [TurnProjection]
    public let subagentRuns: [SubagentRunProjection]
    public let ledgerRevision: Int64
    /// AB-160: the second, explicitly-separate evidence path (AB-156's
    /// `TranscriptEvidenceProjection`) carried through to the presentation
    /// boundary for the first time. `nil` means exactly what it means on
    /// `SessionProjection` — no transcript was read for this session (most
    /// runtime paths today, since `LocalTranscriptEvidenceReader` exists in
    /// `Sources/TranscriptEvidenceReader/` but is not yet wired into the
    /// projection pipeline that produces `SessionProjection` — see the
    /// AB-160 report). Never defaulted to a placeholder bag.
    public let transcriptEvidence: TranscriptEvidenceProjection?

    public init(projection: SessionProjection) {
        self.id = "\(projection.identity.productNamespace.rawValue)::\(projection.identity.nativeSessionID.rawValue)"
        self.productNamespace = projection.identity.productNamespace.rawValue
        self.nativeSessionID = projection.identity.nativeSessionID.rawValue
        self.execution = projection.execution
        self.observation = projection.observation
        self.attention = projection.attention
        self.visibleLifecycle = projection.visibleLifecycle
        self.lineage = projection.lineage
        self.displayTitle = projection.displayTitle
        self.hostLabel = projection.hostLabel
        self.sourceLastUpdated = projection.sourceLastUpdated
        self.turns = projection.turns
        self.subagentRuns = projection.subagentRuns
        self.ledgerRevision = projection.ledgerRevision
        self.transcriptEvidence = projection.transcriptEvidence
    }

    /// Convenience mirroring `SessionProjection.model` — the transcript-
    /// reported model string, real only, never the hook-parsed value and
    /// never a fabricated fallback like "Opus 4.8".
    public var model: String? { transcriptEvidence?.modelFromTranscript }
}
