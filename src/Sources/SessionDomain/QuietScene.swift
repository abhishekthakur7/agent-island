import Foundation

/// Privacy/interruption scenes are observations, not Product state.  Any
/// active reason suppresses every automatic alert facet and never queues a
/// replay when the scene ends.
public enum QuietSceneReason: String, Codable, Hashable, Sendable, CaseIterable {
    case focusMode
    case lockedDisplay
    case asleep
    case screenRecordingOrSharing
}

public struct QuietScene: Codable, Hashable, Sendable, Equatable {
    public var focusMode: Bool
    public var lockedDisplay: Bool
    public var asleep: Bool
    public var screenRecordingOrSharing: Bool

    public init(focusMode: Bool = false, lockedDisplay: Bool = false, asleep: Bool = false, screenRecordingOrSharing: Bool = false) {
        self.focusMode = focusMode
        self.lockedDisplay = lockedDisplay
        self.asleep = asleep
        self.screenRecordingOrSharing = screenRecordingOrSharing
    }

    public init(focusModeActive: Bool, lockedDisplay: Bool = false, asleep: Bool = false, screenSharing: Bool = false) {
        self.init(focusMode: focusModeActive, lockedDisplay: lockedDisplay, asleep: asleep, screenRecordingOrSharing: screenSharing)
    }

    public var isActive: Bool { focusMode || lockedDisplay || asleep || screenRecordingOrSharing }

    public var reasons: [QuietSceneReason] {
        var result: [QuietSceneReason] = []
        if focusMode { result.append(.focusMode) }
        if lockedDisplay { result.append(.lockedDisplay) }
        if asleep { result.append(.asleep) }
        if screenRecordingOrSharing { result.append(.screenRecordingOrSharing) }
        return result
    }

    public static let inactive = Self(focusMode: false, lockedDisplay: false, asleep: false, screenRecordingOrSharing: false)

    public static func screenSharing(_ active: Bool) -> Self { Self(focusMode: false, lockedDisplay: false, asleep: false, screenRecordingOrSharing: active) }
    public static func locked(_ active: Bool) -> Self { Self(focusMode: false, lockedDisplay: active, asleep: false, screenRecordingOrSharing: false) }
}

public typealias QuietSceneState = QuietScene
