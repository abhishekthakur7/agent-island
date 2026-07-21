import SwiftUI

/// IslandTheme — AB-151, the theme-foundation ticket for the 6-ticket Overlay
/// Visual Redesign epic.
///
/// Single source of truth for every colour, font, radius, and quota-threshold
/// value the Agent Island overlay renders with. Nothing here is invented: every
/// value is traceable either to the AB-151 ticket's token tables or to the
/// shipped agent-notch reference (`/Users/abhishekthakur/Developer/agent-notch/main.swift`).
///
/// Hard rule: overlay views must NEVER reach for a semantic system colour
/// (`.primary`, `.secondary`, `Color.accentColor`) or `.regularMaterial`. Those
/// adapt to — and in the case of `.primary`/`.secondary`, invert with — the
/// system's Light/Dark appearance. The Island overlay must render dark in
/// every appearance, so every colour below is an explicit, fixed value.
enum IslandTheme {

    // MARK: - Overlay surface

    /// Panel + pill background. The ticket doc specifies opaque `#0A0A0C`;
    /// agent-notch itself uses plain `NSColor.black`. We standardize on the
    /// doc's `#0A0A0C` (a hair off pure black) and use it everywhere a panel
    /// or pill needs an opaque fill — never `NSColor.windowBackgroundColor`,
    /// which is a system gray that would break the always-dark requirement.
    static let surface = Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0C / 255)

    /// One step up from `surface`: code blocks and inset/elevated cards
    /// (e.g. the Horizon monitor's own container sitting inside the panel).
    static let surfaceElevated = Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255)

    /// 1px borders and dividers. Doc range is white @ 8-12%; 10% is the
    /// picked midpoint and the single value every hairline in the overlay
    /// should reference.
    static let hairline = Color.white.opacity(0.10)

    // MARK: - Overlay text

    /// Counts, titles, command text.
    static let textPrimary = Color(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF6 / 255)
    /// Status labels, stats, empty-state sublines.
    static let textSecondary = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA2 / 255)
    /// "esc", timestamps, disabled/unavailable metadata.
    static let textDim = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x73 / 255)

    // MARK: - Status / semantic

    /// PERMISSION REQUESTED, attention-needed indicators. Amber.
    static let accentAttention = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
    /// Allow button fill; Notifications toggle ON.
    static let allowGreen = Color(red: 0x34 / 255, green: 0xC7 / 255, blue: 0x59 / 255)
    /// Deny button fill. Muted maroon, deliberately not a loud pure red.
    static let denyRed = Color(red: 0xB2 / 255, green: 0x3A / 255, blue: 0x34 / 255)

    /// "Awaiting permission" glyph tint, and (in this ticket's refactor) the
    /// general-purpose selection/focus accent that replaces bare
    /// `Color.accentColor` call sites. The ticket doc leaves the exact value
    /// an open steel-blue range (~#3E7BE6/#4E8CE0); this is the "sample from
    /// #16" placeholder — pick one sensible value now, revisit when the real
    /// permission glyph ships.
    static let statusBlocked = Color(red: 0x4E / 255, green: 0x8C / 255, blue: 0xE0 / 255)

    // MARK: - Brand marks

    /// agent-notch's tuned salmon (main.swift:461 — `NSColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)`).
    static let claudeBrand = Color(red: 0xD9 / 255, green: 0x78 / 255, blue: 0x57 / 255)
    /// NOT agent-notch's teal (`#0FA380`, main.swift:462) — retinted per ticket
    /// to a blue-violet so Codex reads distinctly from both Claude and the
    /// system-blue `statusBlocked` accent.
    static let codexBrand = Color(red: 0x6E / 255, green: 0x63 / 255, blue: 0xE6 / 255)

    /// Cursor and OpenCode ship as monochrome geometric marks (cube / square
    /// respectively); the glyph shapes themselves are a later ticket. These
    /// are tint-only placeholders so call sites have a token to reach for
    /// now instead of a literal.
    static let cursorBrand = Color.white.opacity(0.92)
    static let openCodeBrand = Color.white.opacity(0.72)

    // MARK: - Radius

    enum Radius {
        /// Dropdown bottom corners. Fixed at 18 to match the AppKit hit-test
        /// path (`IslandOverlayPanel.swift:74`,
        /// `NSBezierPath(roundedRect:xRadius:18,yRadius:18)`). This constant
        /// only mirrors that value for SwiftUI call sites — it does NOT
        /// change, and must never drift from, the hit-test geometry.
        static let dropdown: CGFloat = 18
        /// Cards / inset panels (e.g. Horizon rows, selected-detail panel).
        static let card: CGFloat = 12
        /// Buttons.
        static let button: CGFloat = 10
        // Pills use `Capsule()` directly — a capsule has no radius constant
        // to centralize; its roundedness is a function of its own height.
    }

    // MARK: - Quota-threshold rule

    /// 0–60% → green, 60–80% → amber, 80%+ → red. One rule, reused everywhere
    /// a consumption percentage renders. The ticket table names only one red
    /// token (`denyRed`), so that is what "80%+ → red" resolves to here.
    static func quotaColor(percentConsumed: Double) -> Color {
        switch percentConsumed {
        case ..<60: return allowGreen
        case ..<80: return accentAttention
        default: return denyRed
        }
    }
}

// MARK: - Font

/// Monospaced type ramp. `.system(size:weight:design:.monospaced)` is
/// SwiftUI's SF Mono-backed equivalent of AppKit's
/// `NSFont.monospacedSystemFont(ofSize:weight:)`.
enum IslandFont {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// ≈17pt / 600 (semibold) — counts (e.g. "N Agent Sessions").
    static let count = mono(size: 17, weight: .semibold)
    /// 13pt / 500 (medium) — stats & status.
    static let stat = mono(size: 13, weight: .medium)
    /// 12pt / 400 (regular) — sublines.
    static let subline = mono(size: 12, weight: .regular)
}

// MARK: - Mono label helper (AppKit → SwiftUI translation)

/// SwiftUI translation of agent-notch's AppKit `label(_:size:color:bold:)`
/// helper (`main.swift:433-441`) — the single chokepoint that made every
/// text field in that app monospaced, truncating, and non-window-widening.
///
/// AppKit → SwiftUI mapping, faithfully preserved:
///   - `NSTextField(labelWithString:)`                                → `Text(_:)`
///   - `.font = NSFont.monospacedSystemFont(ofSize:weight:)`          → `.font(.system(size:weight:design:.monospaced))`
///   - `.textColor`                                                   → `.foregroundStyle(color)`
///   - `.lineBreakMode = .byTruncatingTail`                           → `.lineLimit(1)` + `.truncationMode(.tail)`
///   - `.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)`
///     → `.layoutPriority(-1)`. SwiftUI has no direct analogue of AppKit's
///       per-axis compression-resistance priority; a negative
///       `layoutPriority` is the closest available lever — it makes this
///       Text the first candidate an enclosing stack shrinks/truncates
///       before it grants extra width to a sibling, which is the same
///       "truncate me, don't widen the window for me" intent as the
///       original `.defaultLow` compression resistance.
struct IslandMonoLabel: View {
    let text: String
    var size: CGFloat = 13
    var weight: Font.Weight = .regular
    var color: Color = IslandTheme.textPrimary

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(-1)
    }
}

/// Free-function factory mirroring the original AppKit call shape
/// (`label(_ text:, size:, color:, bold:)`) 1:1, so existing call sites
/// translate over without reshuffling argument order.
func islandMonoLabel(_ text: String, size: CGFloat, color: Color, bold: Bool = false) -> IslandMonoLabel {
    IslandMonoLabel(text: text, size: size, weight: bold ? .semibold : .regular, color: color)
}

// MARK: - Onboarding tokens (Phase 1B — unused after this ticket, that's expected)

/// Onboarding is a separate visual language from the overlay: sans-serif
/// (not mono), warm charcoal (not near-black neutral), a glossy light
/// primary button. Defined now so a later Phase 1B ticket has tokens ready;
/// nothing in this ticket's scope (overlay views) consumes these yet.
enum IslandOnboardingTheme {
    /// Radial background: warm charcoal center fading to near-black, with a
    /// faint blue glow in the top-right. The doc gives the charcoal stops
    /// exactly; the glow's exact hue/opacity is not specified, so this is a
    /// judgment-call placeholder — a low-opacity cool blue, biased toward
    /// the corner via the view's own gradient placement, not this token.
    static let backgroundInner = Color(red: 0x1E / 255, green: 0x16 / 255, blue: 0x13 / 255)
    static let backgroundOuter = Color(red: 0x0C / 255, green: 0x09 / 255, blue: 0x08 / 255)
    static let backgroundGlow = Color(red: 0x3E / 255, green: 0x64 / 255, blue: 0x9E / 255).opacity(0.16)

    /// Card fill, border, and radius.
    static let cardFill = Color(red: 0x1A / 255, green: 0x12 / 255, blue: 0x10 / 255)
    static let cardBorder = Color.white.opacity(0.06)
    static let cardRadius: CGFloat = 14

    /// Glossy white primary button: pill shape (defined by the button view
    /// via `Capsule()`, not a radius token here), dark text, subtle top
    /// highlight for the "glossy" read.
    static let primaryButtonFill = Color.white
    static let primaryButtonText = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    static let primaryButtonTopHighlight = Color.white.opacity(0.35)

    /// Title / subtitle. Onboarding type is sans — do NOT use `IslandFont`
    /// (monospaced) here.
    static let title = Color.white
    /// Doc range is 44-56pt bold; 48pt picked as the mid-range default.
    static let titleFont = Font.system(size: 48, weight: .bold, design: .default)
    static let subtitle = Color(red: 0xB8 / 255, green: 0xB0 / 255, blue: 0xAC / 255)

    /// Toggle ON reuses the overlay's `allowGreen` so "on/allowed" reads the
    /// same green everywhere in the app; OFF is a neutral gray.
    static let toggleOn = IslandTheme.allowGreen
    static let toggleOff = Color(white: 0.35)
}
