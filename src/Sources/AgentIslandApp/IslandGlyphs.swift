import AppKit
import SwiftUI

// MARK: - IslandGlyphs — AB-152
//
// Pixel-drawing glyph vocabulary ported from agent-notch, the shipped
// reference notch-bar app
// (`/Users/abhishekthakur/Developer/agent-notch/main.swift`). agent-notch's
// glyphs are pure AppKit `NSView.draw(_:)` + CoreGraphics; Agent Island's
// overlay is SwiftUI. Each `draw(_:)` body below is copied UNCHANGED from
// agent-notch — the noise function, cell sizes, and alpha ramps are the
// tuned "look" and are not reinterpreted as SwiftUI shapes — and is only
// wrapped in an `NSViewRepresentable` and retinted for brand colour.
//
// Scope (AB-152): port the reusable glyph *components* only. This file does
// NOT wire them into the collapsed pill (§1.2) or session rows (§1.6) — those
// are later tickets that consume what's defined here. Also explicitly out of
// scope (per the ticket) and NOT ported: `SessionScanner`, `tailInfo`,
// `extractText`, `extractUserPrompt`, `codexMeta`, and agent-notch's geometry
// (`notchWidth` etc.) — only the presentation/drawing is taken.
//
// Source mapping — agent-notch/main.swift → this file (draw bodies verbatim):
//   IndicatorView (whole class)     456-638  → GlyphIndicatorView
//   mascotFrames + quadrants        466-488  → GlyphIndicatorView.mascotFrames / .quadrants
//   draw(_:)                       490-506  → GlyphIndicatorView.draw(_:)
//   drawGreenBlob                  508-525  → GlyphIndicatorView.drawGreenBlob
//   drawCrab                       528-556  → GlyphIndicatorView.drawCrab
//   codexSprite loader              558-586  → GlyphIndicatorView.codexSprite (Bundle.module swap)
//   refreshPetChoice                587-594  → hardcoded `currentPetID` (see note below)
//   drawCodexPet                    596-608  → GlyphIndicatorView.drawCodexPet
//   drawRing                        611-637  → GlyphIndicatorView.drawRing (kept as sprite-load fallback)
//   DitherIconView (whole class)    217-268  → GlyphDitherIconView
//   DitherSeparator (whole class)   271-288  → GlyphDitherSeparatorView
//
// Retinting: agent-notch's `claudeOrange` (`NSColor(red: 0.85, green: 0.47,
// blue: 0.34, alpha: 1)`, main.swift:461) and `codexTeal` (`NSColor(red: 0.06,
// green: 0.64, blue: 0.50, alpha: 1)` — OpenAI teal #0FA380, main.swift:462)
// are the only two colour literals touched. They're replaced with
// `NSColor(IslandTheme.claudeBrand)` (#D97857) and
// `NSColor(IslandTheme.codexBrand)` (#6E63E6 blue-violet) — the AB-151 brand
// tokens. Every other tuned value (alpha ramps, per-cell noise, cell sizes,
// aspect ratios) is preserved exactly as agent-notch has it.

// MARK: - Presentation-only support enums

/// Minimal "which agent" selector for the ported glyph draw bodies.
/// Deliberately NOT agent-notch's `AgentKind` (main.swift:6) — that enum's
/// `rawValue`s are session-row titles belonging to the out-of-scope
/// `SessionScanner` domain. Only the two cases the glyphs branch on live here.
enum IslandGlyphAgentKind {
    case claude
    case codex
}

/// Presentation-only glyph state selector, mirroring agent-notch's
/// `AgentGlyphState` (main.swift:454) 1:1.
enum IslandGlyphState {
    case inactive
    case running
    case done
}

// MARK: - Shared animation clock

/// Shared 0.12s cadence driving every animated glyph in this file.
/// agent-notch drives `IndicatorView.t` from `AppDelegate.tick()`/`render()`
/// (main.swift:918-927, its own `Timer.scheduledTimer(withTimeInterval: 0.12,
/// ...)`) and drives each `DitherIconView.t` from the session popover's
/// separate 0.12s timer (main.swift:350-355). Agent Island's glyphs are
/// reusable SwiftUI views that may appear in more than one place at once, so
/// a single shared clock instance — rather than one Timer per glyph — is what
/// keeps every glyph on screen ticking in lockstep with no relative drift.
@MainActor
final class IslandGlyphClock: ObservableObject {
    static let shared = IslandGlyphClock()

    @Published private(set) var t: CGFloat = 0

    private var timer: Timer?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            Task { @MainActor in
                IslandGlyphClock.shared.t += 0.12
            }
        }
    }
}

// MARK: - GlyphIndicatorView (ported from agent-notch's IndicatorView, main.swift:456-638)

/// Indicator content: branded pixel animations for whichever agents are
/// running. Ported verbatim from agent-notch's `IndicatorView`; see the
/// mapping table at the top of this file for the exact source line ranges of
/// each drawing routine.
final class GlyphIndicatorView: NSView {
    var claudeState: IslandGlyphState = .inactive { didSet { needsDisplay = true } }
    var codexState: IslandGlyphState = .inactive { didSet { needsDisplay = true } }
    var t: CGFloat = 0 { didSet { needsDisplay = true } }

    // Retinted per AB-152 (see file header): brand tint tokens from
    // IslandTheme (AB-151) replace agent-notch's own NSColor literals.
    static let claudeOrange = NSColor(IslandTheme.claudeBrand)
    static let codexTeal = NSColor(IslandTheme.codexBrand)

    // The Claude Code launch-banner mascot, drawn from its real block characters.
    // Two frames: the feet alternate so it walks.
    static let mascotFrames: [[String]] = [
        [" ▐▛███▜▌ ",
         "▝▜█████▛▘",
         "  ▘▘ ▝▝  "],
        [" ▐▛███▜▌ ",
         "▝▜█████▛▘",
         "  ▝▝ ▘▘  "],
    ]
    // quadrant bits: (upper-left, upper-right, lower-left, lower-right)
    static let quadrants: [Character: (Bool, Bool, Bool, Bool)] = [
        "█": (true, true, true, true),
        "▐": (false, true, false, true),
        "▌": (true, false, true, false),
        "▛": (true, true, true, false),
        "▜": (true, true, false, true),
        "▙": (true, false, true, true),
        "▟": (false, true, true, true),
        "▘": (true, false, false, false),
        "▝": (false, true, false, false),
        "▖": (false, false, true, false),
        "▗": (false, false, false, true),
        " ": (false, false, false, false),
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cy = bounds.midY
        var x = bounds.maxX - 6  // right-aligned toward the notch
        // each agent keeps its own slot: mascot while running, green blob when
        // freshly done (cleared once you revisit the terminal)
        switch claudeState {
        case .running: x = drawCrab(ctx, right: x, cy: cy) - 6
        case .done: drawGreenBlob(ctx, right: x, cy: cy); x -= 24
        case .inactive: break
        }
        switch codexState {
        case .running: _ = drawCodexPet(ctx, right: x, cy: cy)
        case .done: drawGreenBlob(ctx, right: x, cy: cy)
        case .inactive: break
        }
    }

    private func drawGreenBlob(_ ctx: CGContext, right: CGFloat, cy: CGFloat) {
        let cell: CGFloat = 2.5, grid = 7
        let c = CGFloat(grid) / 2
        let step = Int(t * 2)
        let x0 = right - CGFloat(grid) * cell
        for i in 0..<grid {
            for j in 0..<grid {
                let dx = CGFloat(i) + 0.5 - c, dy = CGFloat(j) + 0.5 - c
                let dist = sqrt(dx * dx + dy * dy)
                let n = sin(CGFloat(i * 374761 + j * 668265 + step * 982451) * 0.0001) * 43758.5453
                let r = n - n.rounded(.down)
                guard r > 0.1 + dist / c * 0.8 else { continue }
                ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.5 + 0.5 * r).cgColor)
                ctx.fill(CGRect(x: x0 + CGFloat(i) * cell, y: cy - CGFloat(grid) * cell / 2 + CGFloat(j) * cell,
                                width: cell - 0.5, height: cell - 0.5))
            }
        }
    }

    /// Returns the left edge of what was drawn.
    private func drawCrab(_ ctx: CGContext, right: CGFloat, cy: CGFloat) -> CGFloat {
        // terminal cells are ~2x taller than wide — keep that aspect or he squishes
        let subW: CGFloat = 1.6, subH: CGFloat = 3.2
        let walk = Int(t * 2.5)
        let frame = Self.mascotFrames[walk % 2]
        let cols = frame[0].count * 2, rows = frame.count * 2
        let x0 = right - CGFloat(cols) * subW
        let bob: CGFloat = (walk % 2 == 0) ? -0.5 : 0.5  // little bounce, symmetric around center
        let y0 = cy + CGFloat(rows) * subH / 2 + bob - 2  // feet row is sparse; nudge down so the body reads centered
        let step = Int(t * 3)
        for (j, line) in frame.enumerated() {
            for (i, ch) in line.enumerated() {
                guard let q = Self.quadrants[ch] else { continue }
                let cells = [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)]
                for (on, qx, qy) in cells where on {
                    let n = sin(CGFloat(i * 374761 + j * 668265 + (qx + qy * 2) * 97 + step * 982451) * 0.0001) * 43758.5453
                    let r = n - n.rounded(.down)
                    // feet stay solid; body shimmers gently
                    let isFeet = j == frame.count - 1
                    let alpha = isFeet ? 1.0 : 0.8 + 0.2 * r
                    ctx.setFillColor(Self.claudeOrange.withAlphaComponent(alpha).cgColor)
                    ctx.fill(CGRect(x: x0 + CGFloat(i * 2 + qx) * subW,
                                    y: y0 - CGFloat(j * 2 + qy + 1) * subH,
                                    width: subW - 0.3, height: subH - 0.4))
                }
            }
        }
        return x0
    }

    // Official Codex pet spritesheets (8 cols x 9 rows, 192x208 frames);
    // row 1 is the "running-right" animation, 8 frames @ 120 ms.
    //
    // AB-152 simplification: agent-notch picks the pet via
    // ~/.config/agent-notch/pet (`refreshPetChoice`, main.swift:587-594).
    // Agent Island has no equivalent settings surface yet for this ticket's
    // scope, so the pet is hardcoded to "codex" (an acceptable simplification
    // per the ticket — revisit with a real picker in a later ticket).
    static let currentPetID = "codex"
    private static var spriteCache: [String: NSImage] = [:]
    static var codexSprite: NSImage? {
        if let img = spriteCache[currentPetID] { return img }
        // AB-152: agent-notch resolves this against filesystem candidate
        // paths (installed app Resources/, bare-binary sibling dir, dev
        // checkout fallback). Agent Island bundles the sprites as SwiftPM
        // resources, so the only change here is resolving through
        // Bundle.module instead.
        guard let url = Bundle.module.url(forResource: "pet-\(currentPetID)", withExtension: "webp", subdirectory: "pets"),
              let img = NSImage(contentsOf: url) else { return nil }
        spriteCache[currentPetID] = img
        return img
    }

    private func drawCodexPet(_ ctx: CGContext, right: CGFloat, cy: CGFloat) -> CGFloat {
        guard let sprite = Self.codexSprite else {
            return drawRing(ctx, right: right, cy: cy, color: Self.codexTeal)
        }
        let fw: CGFloat = 192, fh: CGFloat = 208
        let idx = Int(t / 0.12) % 8
        let src = NSRect(x: CGFloat(idx) * fw, y: 1872 - 2 * fh, width: fw, height: fh)
        let h: CGFloat = 26, w = h * fw / fh
        let dest = NSRect(x: right - w, y: cy - h / 2, width: w, height: h)
        NSGraphicsContext.current?.imageInterpolation = .none  // keep the pixel art crisp
        sprite.draw(in: dest, from: src, operation: .sourceOver, fraction: 1)
        return dest.minX
    }

    /// Returns the left edge of what was drawn. Runtime fallback used by
    /// `drawCodexPet` whenever the sprite fails to load — kept exactly as
    /// agent-notch has it, only called with the retinted `codexTeal`.
    private func drawRing(_ ctx: CGContext, right: CGFloat, cy: CGFloat, color: NSColor) -> CGFloat {
        let cell: CGFloat = 2.5, grid = 9
        let x0 = right - CGFloat(grid) * cell
        let y0 = cy - CGFloat(grid) * cell / 2
        let c = CGFloat(grid) / 2
        let phase = t * 1.4
        let step = Int(t * 3)
        for i in 0..<grid {
            for j in 0..<grid {
                let dx = CGFloat(i) + 0.5 - c
                let dy = CGFloat(j) + 0.5 - c
                let dist = sqrt(dx * dx + dy * dy)
                guard dist > c - 2.4, dist < c else { continue }
                var angle = atan2(dy, dx) - phase
                angle = angle - (angle / (2 * .pi)).rounded(.down) * 2 * .pi
                let intensity = 1 - angle / (2 * .pi)
                let n = sin(CGFloat(i * 374761 + j * 668265 + step * 982451) * 0.0001) * 43758.5453
                let r = n - n.rounded(.down)
                let a = intensity * intensity * (0.55 + 0.45 * r)
                guard a > 0.08 else { continue }
                ctx.setFillColor(color.withAlphaComponent(a).cgColor)
                ctx.fill(CGRect(x: x0 + CGFloat(i) * cell, y: y0 + CGFloat(j) * cell,
                                width: cell - 0.5, height: cell - 0.5))
            }
        }
        return x0
    }
}

// MARK: - GlyphDitherIconView (ported from agent-notch's DitherIconView, main.swift:217-268)

/// Row icon: mini mascot / Codex pet while running, green pixel checkmark
/// when done. Ported verbatim from agent-notch's `DitherIconView`; only the
/// qualified references to `IndicatorView.*` statics are retargeted to this
/// file's renamed `GlyphIndicatorView.*` (the pixel math itself is untouched).
final class GlyphDitherIconView: NSView {
    var running = false
    var kind: IslandGlyphAgentKind = .claude
    var color: NSColor = .systemBlue  // kept for tint fallbacks (ported as-is; unused by draw(_:) below)
    var t: CGFloat = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 16) }

    static let checkmark: [(Int, Int)] = [
        (6, 1), (5, 2), (4, 3), (0, 3), (1, 4), (3, 4), (2, 5)
    ]

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if !running {
            // done: green pixel checkmark
            let cell: CGFloat = 2.2
            for (x, y) in Self.checkmark {
                ctx.setFillColor(NSColor.systemGreen.cgColor)
                ctx.fill(CGRect(x: 1 + CGFloat(x) * cell, y: 1 + CGFloat(7 - y) * cell,
                                width: cell - 0.4, height: cell - 0.4))
            }
            return
        }
        if kind == .codex, let sprite = GlyphIndicatorView.codexSprite {
            let fw: CGFloat = 192, fh: CGFloat = 208
            let idx = Int(t / 0.12) % 8
            let src = NSRect(x: CGFloat(idx) * fw, y: 1872 - 2 * fh, width: fw, height: fh)
            NSGraphicsContext.current?.imageInterpolation = .none
            sprite.draw(in: NSRect(x: 1, y: 0, width: 16 * fw / fh, height: 16),
                        from: src, operation: .sourceOver, fraction: 1)
            return
        }
        // mini Claude mascot walking, with a visible bob
        let subW: CGFloat = 1.0, subH: CGFloat = 2.0
        let walk = Int(t * 2.5)
        let frame = GlyphIndicatorView.mascotFrames[walk % 2]
        let rows = frame.count * 2
        let y0 = CGFloat(rows) * subH + 1 + (walk % 2 == 0 ? 0 : 1.5)
        for (j, line) in frame.enumerated() {
            for (i, ch) in line.enumerated() {
                guard let q = GlyphIndicatorView.quadrants[ch] else { continue }
                let cells = [(q.0, 0, 0), (q.1, 1, 0), (q.2, 0, 1), (q.3, 1, 1)]
                for (on, qx, qy) in cells where on {
                    ctx.setFillColor(GlyphIndicatorView.claudeOrange.cgColor)
                    ctx.fill(CGRect(x: CGFloat(i * 2 + qx) * subW,
                                    y: y0 - CGFloat(j * 2 + qy + 1) * subH,
                                    width: subW - 0.2, height: subH - 0.3))
                }
            }
        }
    }
}

// MARK: - GlyphDitherSeparatorView (ported from agent-notch's DitherSeparator, main.swift:271-288)

/// A sparse row of gray pixels — the dithered stand-in for a separator line.
/// Ported verbatim; no colour or value in this view is brand-tinted (it's
/// pure white-on-transparent dithering), so nothing changed on port.
final class GlyphDitherSeparatorView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 4) }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cell: CGFloat = 2
        var x: CGFloat = 0
        var seed: UInt64 = 0x9E3779B9
        while x < bounds.width {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = CGFloat(seed >> 33 & 0xFFFF) / 65535
            if r > 0.55 {
                ctx.setFillColor(NSColor.white.withAlphaComponent(0.06 + 0.10 * r).cgColor)
                ctx.fill(CGRect(x: x, y: 1, width: cell - 0.4, height: cell - 0.4))
            }
            x += cell
        }
    }
}

// MARK: - SwiftUI wrappers (NSViewRepresentable)

/// SwiftUI wrapper for `GlyphIndicatorView`. Drives `t` from the shared
/// `IslandGlyphClock` so it animates in lockstep with every other glyph.
/// Fixed 64×32 size (agent-notch's own indicator window is 66×30 —
/// `indicatorScreenRect`, main.swift:817-819 — this mirrors that footprint)
/// so animating never reflows surrounding SwiftUI layout.
struct IslandIndicatorGlyph: NSViewRepresentable {
    var claudeState: IslandGlyphState = .inactive
    var codexState: IslandGlyphState = .inactive

    @ObservedObject private var clock = IslandGlyphClock.shared

    static let size = CGSize(width: 64, height: 32)

    func makeNSView(context: Context) -> GlyphIndicatorView {
        let view = GlyphIndicatorView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: GlyphIndicatorView, context: Context) {
        apply(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphIndicatorView, context: Context) -> CGSize? {
        Self.size
    }

    private func apply(to view: GlyphIndicatorView) {
        view.claudeState = claudeState
        view.codexState = codexState
        view.t = clock.t
    }
}

/// SwiftUI wrapper for `GlyphDitherIconView`. Drives `t` from the shared
/// `IslandGlyphClock`. Fixed 18×16 size — unchanged from agent-notch's own
/// `intrinsicContentSize` (main.swift:222) — so it never reflows a session row.
struct IslandDitherIconGlyph: NSViewRepresentable {
    var running: Bool
    var kind: IslandGlyphAgentKind = .claude

    @ObservedObject private var clock = IslandGlyphClock.shared

    static let size = CGSize(width: 18, height: 16)

    func makeNSView(context: Context) -> GlyphDitherIconView {
        let view = GlyphDitherIconView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: GlyphDitherIconView, context: Context) {
        apply(to: nsView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphDitherIconView, context: Context) -> CGSize? {
        Self.size
    }

    private func apply(to view: GlyphDitherIconView) {
        view.running = running
        view.kind = kind
        view.t = clock.t
    }
}

/// SwiftUI wrapper for `GlyphDitherSeparatorView`. Unlike the two glyphs
/// above, agent-notch's `DitherSeparator.draw(_:)` has no time component
/// (it's a deterministic seed over `bounds.width`, redrawn once per layout),
/// so it does not subscribe to `IslandGlyphClock`. Height is fixed at 4pt —
/// matching agent-notch's own `intrinsicContentSize` — while width is
/// intentionally left to flow with the proposed width, exactly as the
/// original "spans the row" separator does.
struct IslandDitherSeparatorGlyph: NSViewRepresentable {
    func makeNSView(context: Context) -> GlyphDitherSeparatorView {
        GlyphDitherSeparatorView()
    }

    func updateNSView(_ nsView: GlyphDitherSeparatorView, context: Context) {
        nsView.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphDitherSeparatorView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 4)
    }
}

// MARK: - GlyphPixelGridView (AB-158 §1.2 AC-1.2-b — new, not ported)

/// The collapsed pill's leading icon: a small, static, gray square
/// pixel-grid — replacing the old cyan `sparkles` image and explicitly NOT a
/// colored circle (AC-1.2-b). There is no equivalent in agent-notch's
/// `IndicatorView` (its collapsed state is glyph-only, no separate leading
/// icon — see the ticket's "what agent-notch does *not* give you" note), so
/// this is new, drawn in the same hard-edged pixel aesthetic as
/// `GlyphIndicatorView`/`GlyphDitherSeparatorView` above: flat, unaliased
/// squares, no gradients. Deliberately NOT driven by `IslandGlyphClock` —
/// unlike the agent-activity glyphs, this is decorative chrome, not a status
/// indicator, so it never ticks and is `accessibilityHidden` at every call
/// site. A plain checkerboard alpha ramp keeps three cells individually
/// legible as a "grid" at this size rather than reading as one solid gray
/// square.
final class GlyphPixelGridView: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 15, height: 15) }

    /// AB-159 §1.6 AC-1.6-e: state tinting for the session-row leading glyph
    /// (salmon/green/blue-steel). Defaults to the original AB-158
    /// `textSecondary` gray so every pre-existing call site (the collapsed
    /// pill's leading glyph) is pixel-identical to before this ticket.
    var tint: NSColor = NSColor(IslandTheme.textSecondary) { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let grid = 3
        let cell = bounds.width / CGFloat(grid)
        for i in 0..<grid {
            for j in 0..<grid {
                let checker = (i + j) % 2 == 0
                ctx.setFillColor(tint.withAlphaComponent(checker ? 0.85 : 0.4).cgColor)
                ctx.fill(CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell - 1, height: cell - 1))
            }
        }
    }
}

/// SwiftUI wrapper for `GlyphPixelGridView`. Fixed 15×15 — small enough to
/// sit inline before a line of pill status text without dominating it.
///
/// AB-159 §1.6 AC-1.6-e: gained a `tint` parameter so the session-row leading
/// glyph can be colored by real session state (salmon/green/blue-steel)
/// instead of the fixed gray AB-158 shipped for the collapsed pill. Chosen
/// over extending `IslandDitherIconGlyph` (the mascot/checkmark glyph) because
/// this view is already the "square pixel-grid glyph" the AC describes, and
/// every pre-AB-159 call site keeps its exact appearance via the `tint`
/// default below.
struct IslandPixelGridGlyph: NSViewRepresentable {
    static let size = CGSize(width: 15, height: 15)

    var tint: Color = IslandTheme.textSecondary

    func makeNSView(context: Context) -> GlyphPixelGridView {
        let view = GlyphPixelGridView()
        view.tint = NSColor(tint)
        return view
    }

    func updateNSView(_ nsView: GlyphPixelGridView, context: Context) {
        nsView.tint = NSColor(tint)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphPixelGridView, context: Context) -> CGSize? {
        Self.size
    }
}

// MARK: - GlyphGreenActivityView (AB-158 §1.2 AC-1.2-e — verbatim pixel math, new hosting size)

/// AC-1.2-e's "green pixel-grid activity glyph" — the same dithered
/// green-blob pixel math as `GlyphIndicatorView.drawGreenBlob` above
/// (`main.swift:508-525` in agent-notch), copied verbatim so the visual
/// identity — the tuned 7×7 dithered green blob — is identical. Only the
/// hosting bounds differ: `GlyphIndicatorView` is a fixed 64×32
/// canvas that right-aligns its content toward a physical notch (correct for
/// its original per-agent indicator-window role, see its own doc comment),
/// which would leave a large empty gap before the visible pixels if dropped
/// inline after collapsed-pill status text. This wrapper hosts the identical
/// draw routine in bounds sized for that inline use instead, so the blob sits
/// immediately after the status text with no dead space, matching #11's
/// "status … green glyph" reading with no interstitial gap.
final class GlyphGreenActivityView: NSView {
    var t: CGFloat = 0 { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: 20, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let cell: CGFloat = 2.5, grid = 7
        let c = CGFloat(grid) / 2
        let step = Int(t * 2)
        let cy = bounds.midY
        let right = bounds.maxX - 1
        let x0 = right - CGFloat(grid) * cell
        for i in 0..<grid {
            for j in 0..<grid {
                let dx = CGFloat(i) + 0.5 - c, dy = CGFloat(j) + 0.5 - c
                let dist = sqrt(dx * dx + dy * dy)
                let n = sin(CGFloat(i * 374761 + j * 668265 + step * 982451) * 0.0001) * 43758.5453
                let r = n - n.rounded(.down)
                guard r > 0.1 + dist / c * 0.8 else { continue }
                ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.5 + 0.5 * r).cgColor)
                ctx.fill(CGRect(x: x0 + CGFloat(i) * cell, y: cy - CGFloat(grid) * cell / 2 + CGFloat(j) * cell,
                                width: cell - 0.5, height: cell - 0.5))
            }
        }
    }
}

/// SwiftUI wrapper for `GlyphGreenActivityView`. Ticks off the same shared
/// `IslandGlyphClock` as every other animated glyph in this file.
struct IslandGreenActivityGlyph: NSViewRepresentable {
    @ObservedObject private var clock = IslandGlyphClock.shared

    static let size = CGSize(width: 20, height: 18)

    func makeNSView(context: Context) -> GlyphGreenActivityView {
        let view = GlyphGreenActivityView()
        view.t = clock.t
        return view
    }

    func updateNSView(_ nsView: GlyphGreenActivityView, context: Context) {
        nsView.t = clock.t
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: GlyphGreenActivityView, context: Context) -> CGSize? {
        Self.size
    }
}

// MARK: - Preview

// NOTE (AB-152): a `#Preview` block was tried here so the glyphs could be
// eyeballed, but `swift build` on this machine's command-line toolchain has
// no `PreviewsMacros` plugin ("external macro implementation type
// 'PreviewsMacros.SwiftUIView' could not be found") — only Xcode itself
// supplies it. The ticket marks previews optional and explicitly "only if it
// doesn't complicate the build," so it's omitted; `IslandGlyphPreviewContent`
// below is a plain SwiftUI View with the same content, usable from Xcode's
// canvas (`#Preview { IslandGlyphPreviewContent() }`) or a future harness
// without depending on the preview macro to make `swift build` succeed.
struct IslandGlyphPreviewContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IslandIndicatorGlyph(claudeState: .running, codexState: .running)
            IslandIndicatorGlyph(claudeState: .done, codexState: .done)
            HStack(spacing: 10) {
                IslandDitherIconGlyph(running: true, kind: .claude)
                IslandDitherIconGlyph(running: true, kind: .codex)
                IslandDitherIconGlyph(running: false, kind: .claude)
            }
            IslandDitherSeparatorGlyph()
                .frame(width: 240)
            // AB-158 §1.2: the collapsed pill's new leading gray pixel-grid
            // glyph and inline green activity glyph.
            HStack(spacing: 10) {
                IslandPixelGridGlyph()
                IslandGreenActivityGlyph()
            }
        }
        .padding(20)
        .background(IslandTheme.surface)
    }
}
