import Foundation
import AppKit
import SessionDomain

/// Local-only NSSound adapter.  A preview is deliberately a separate method
/// and has no candidate context, so it cannot emit a banner or Product action.
@MainActor
public final class LocalSoundAdapter {
    private var urls: [LocalSoundID: URL] = [:]
    private var sounds: [LocalSoundID: NSSound] = [:]

    public init() {}

    public func register(asset: LocalSoundAsset, fileURL: URL) {
        urls[asset.id] = fileURL
        sounds.removeValue(forKey: asset.id)
    }

    @discardableResult
    public func play(_ decision: SoundDecision, now: Date = Date()) -> SoundPlaybackLease? {
        guard case .play(_, let assetID, let volume) = decision else { return nil }
        guard let sound = sound(for: assetID) else { return nil }
        sound.volume = Float(min(max(0, volume), 1))
        sound.play()
        return SoundPlaybackLease(assetID: assetID, preview: false, issuedAt: now)
    }

    @discardableResult
    public func preview(_ preview: SoundPreview, now: Date = Date()) -> SoundPlaybackLease? {
        guard case .play(let assetID, let volume) = preview, let sound = sound(for: assetID) else { return nil }
        sound.volume = Float(min(max(0, volume), 1))
        sound.play()
        return SoundPlaybackLease(assetID: assetID, preview: true, issuedAt: now)
    }

    public func release(_ lease: SoundPlaybackLease) {
        sounds[lease.assetID]?.stop()
        sounds.removeValue(forKey: lease.assetID)
    }

    public func remove(_ assetID: LocalSoundID) {
        sounds[assetID]?.stop()
        sounds.removeValue(forKey: assetID)
        urls.removeValue(forKey: assetID)
    }

    private func sound(for id: LocalSoundID) -> NSSound? {
        if let sound = sounds[id] { return sound }
        guard let url = urls[id], let sound = NSSound(contentsOf: url, byReference: true) else { return nil }
        sounds[id] = sound
        return sound
    }
}

public typealias NSSoundAdapter = LocalSoundAdapter

