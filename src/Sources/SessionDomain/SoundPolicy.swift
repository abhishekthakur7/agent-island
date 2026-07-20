import Foundation

public struct LocalSoundID: Codable, Hashable, Sendable, Equatable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.init(value) }
}

/// Only local metadata crosses the policy boundary.  The bytes/path remain
/// in the AppKit adapter and are released after playback.
public struct LocalSoundAsset: Codable, Hashable, Sendable, Equatable {
    public let id: LocalSoundID
    public let displayName: String
    public let byteCount: Int

    public init(id: LocalSoundID, displayName: String, byteCount: Int) {
        self.id = id
        self.displayName = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
        self.byteCount = max(0, byteCount)
    }
}

public enum SoundSelection: Codable, Hashable, Sendable, Equatable {
    case off
    case local(LocalSoundID)
}

public struct QuietHours: Codable, Hashable, Sendable, Equatable {
    public let startMinute: Int
    public let endMinute: Int

    public init(startMinute: Int = 22 * 60, endMinute: Int = 7 * 60) {
        self.startMinute = min(max(0, startMinute), 23 * 60 + 59)
        self.endMinute = min(max(0, endMinute), 23 * 60 + 59)
    }

    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        if startMinute == endMinute { return false }
        if startMinute < endMinute { return minute >= startMinute && minute < endMinute }
        return minute >= startMinute || minute < endMinute
    }
}

public struct SoundPolicy: Codable, Hashable, Sendable, Equatable {
    public var masterEnabled: Bool
    public var volume: Double
    public var immediateMute: Bool
    public var quietHoursEnabled: Bool
    public var quietHours: QuietHours
    public var selectionByClass: [AlertCandidateClass: SoundSelection]
    public var assets: [LocalSoundAsset]

    public init(
        masterEnabled: Bool = true,
        volume: Double = 0.7,
        immediateMute: Bool = false,
        quietHoursEnabled: Bool = false,
        quietHours: QuietHours = QuietHours(),
        selectionByClass: [AlertCandidateClass: SoundSelection] = [:],
        assets: [LocalSoundAsset] = []
    ) {
        self.masterEnabled = masterEnabled
        self.volume = min(max(0, volume), 1)
        self.immediateMute = immediateMute
        self.quietHoursEnabled = quietHoursEnabled
        self.quietHours = quietHours
        self.selectionByClass = selectionByClass
        self.assets = assets
    }

    public static let `default` = SoundPolicy()

    public func selection(for semanticClass: AlertCandidateClass) -> SoundSelection {
        selectionByClass[semanticClass] ?? .off
    }

    public func sound(for candidate: AlertCandidate, at date: Date, calendar: Calendar = .current) -> SoundDecision {
        guard masterEnabled else { return .suppressed(candidateID: candidate.id, reason: .masterDisabled) }
        guard !immediateMute else { return .suppressed(candidateID: candidate.id, reason: .muted) }
        guard !quietHoursEnabled || !quietHours.contains(date, calendar: calendar) else { return .suppressed(candidateID: candidate.id, reason: .quietHours) }
        guard case .local(let soundID) = selection(for: candidate.semanticClass), assets.contains(where: { $0.id == soundID }) else {
            return .suppressed(candidateID: candidate.id, reason: .classDisabled)
        }
        return .play(candidateID: candidate.id, assetID: soundID, volume: volume)
    }

    public func preview(_ soundID: LocalSoundID) -> SoundPreview {
        guard masterEnabled, !immediateMute, assets.contains(where: { $0.id == soundID }) else { return .rejected }
        return .play(assetID: soundID, volume: volume)
    }

    public mutating func register(_ asset: LocalSoundAsset) {
        assets.removeAll { $0.id == asset.id }
        assets.append(asset)
    }

    public mutating func remove(_ id: LocalSoundID) {
        assets.removeAll { $0.id == id }
        for key in selectionByClass.keys {
            if selectionByClass[key] == .local(id) { selectionByClass[key] = .off }
        }
    }
}

public enum SoundSuppressionReason: String, Codable, Hashable, Sendable, Equatable {
    case masterDisabled
    case muted
    case quietHours
    case classDisabled
}

public enum SoundDecision: Codable, Hashable, Sendable, Equatable {
    case play(candidateID: AlertCandidateID, assetID: LocalSoundID, volume: Double)
    case suppressed(candidateID: AlertCandidateID, reason: SoundSuppressionReason)

    public var candidateID: AlertCandidateID {
        switch self {
        case .play(let id, _, _), .suppressed(let id, _): id
        }
    }

    public var isPlaying: Bool {
        if case .play = self { return true }
        return false
    }
}

public enum SoundPreview: Codable, Hashable, Sendable, Equatable {
    case play(assetID: LocalSoundID, volume: Double)
    case rejected
}

/// A short-lived token makes release semantics explicit to adapters.  It has
/// no Product action and cannot create an Alert Candidate.
public struct SoundPlaybackLease: Codable, Hashable, Sendable, Equatable {
    public let assetID: LocalSoundID
    public let preview: Bool
    public let issuedAt: Date

    public init(assetID: LocalSoundID, preview: Bool, issuedAt: Date) {
        self.assetID = assetID
        self.preview = preview
        self.issuedAt = issuedAt
    }
}

