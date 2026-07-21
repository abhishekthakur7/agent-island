import Foundation

/// Display-only evidence supplied by a live, negotiated Agent Adapter. This
/// is deliberately not billing, an estimate, session identity, ordering, or
/// input to monitoring, filtering, notification, queue, Action Attempt, or
/// Jump Back behavior.
///
/// ## Relationship to `ProviderQuotaState.swift` (AB-157)
///
/// This type remains exactly what it always was: one provider, one
/// `usedPercent`/`remainingPercent`, one `resetsAt` — the shape
/// `UsagePresentationModel`/`UsageSnapshotHeader`/`AppDelegate` already
/// depend on and continue to render today. AB-157 added a genuinely richer,
/// **additive sibling model** (`ProviderQuotaSnapshot` / `ProviderQuotaBoard`
/// in `ProviderQuotaState.swift`) for the multi-provider, multi-window,
/// token-metered, and Metrics-tab-depth data the overlay redesign's §1.4/
/// §1.12/§1.12.1 need — a shape this type cannot express (it has no concept
/// of multiple named windows or multiple providers rendered together). This
/// type is not deprecated or extended in place by that work; it is simply a
/// narrower, older concept that happens to predate it. Do not add
/// window/provider-array fields here — add them to the sibling type instead.
public struct UsageSnapshot: Codable, Equatable, Hashable, Sendable {
    public let sourceID: String
    public let provider: String
    public let observedAt: Date
    public let resetsAt: Date?
    /// Source-reported percentage values. Either value may be absent; no
    /// complement is calculated because that would fabricate Product truth.
    public let usedPercent: Double?
    public let remainingPercent: Double?

    public init(sourceID: String, provider: String, observedAt: Date, resetsAt: Date? = nil, usedPercent: Double? = nil, remainingPercent: Double? = nil) {
        self.sourceID = sourceID
        self.provider = provider
        self.observedAt = observedAt
        self.resetsAt = resetsAt
        self.usedPercent = Self.validPercentage(usedPercent)
        self.remainingPercent = Self.validPercentage(remainingPercent)
    }

    public var hasSourcedValue: Bool { usedPercent != nil || remainingPercent != nil }

    private static func validPercentage(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0 ... 100).contains(value) else { return nil }
        return value
    }
}

public enum UsageSnapshotState: String, Codable, Equatable, Hashable, Sendable {
    case fresh
    case stale
    case missing
    case disabled
    case unavailable
}

public enum UsageValueKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case used
    case remaining

    public var title: String { self == .used ? "Used" : "Remaining" }

    public func value(in snapshot: UsageSnapshot) -> Double? {
        self == .used ? snapshot.usedPercent : snapshot.remainingPercent
    }
}

public enum UsageProviderSelection: Codable, Equatable, Hashable, Sendable {
    case preferred(String)
    case followSelectedActiveSession

    public var preferredProvider: String? {
        guard case let .preferred(provider) = self else { return nil }
        return provider
    }
}

public struct UsageDisplayPreferences: Codable, Equatable, Hashable, Sendable {
    public var isVisible: Bool
    public var valueKind: UsageValueKind
    public var providerSelection: UsageProviderSelection

    public init(isVisible: Bool = true, valueKind: UsageValueKind = .remaining, providerSelection: UsageProviderSelection = .followSelectedActiveSession) {
        self.isVisible = isVisible
        self.valueKind = valueKind
        self.providerSelection = providerSelection
    }

    public static let `default` = Self()
}
