import ClaudeCodeAdapter
import CodexCLIAdapter
import CursorHooksAdapter
import SwiftUI

// MARK: - OnboardingAgent — AB-165 §2.2 "Which agents do you use?"
//
// The fixed roster the 3-column agent grid renders, in the AC's own literal
// order (AC-2.2-b): "Claude, Codex, Cursor / Grok, Kimi, Hermes / OpenCode,
// GitHub Co…, Kilo Code / Droid, Antigravity, Pi" — the "/" marks row breaks
// of a 3-column, 4-row grid, read row-major.
//
// `CaseIterable`'s synthesized `allCases` walks cases in declaration order,
// so declaration order below IS grid order. `OnboardingAgentsView` iterates
// `OnboardingAgent.allCases` directly rather than re-deriving or re-sorting
// an order elsewhere — this file is the single place that order is spelled
// out.
enum OnboardingAgent: CaseIterable, Hashable {
    // Row 1
    case claude
    case codex
    case cursor
    // Row 2
    case grok
    case kimi
    case hermes
    // Row 3
    case openCode
    case githubCopilot
    case kiloCode
    // Row 4
    case droid
    case antigravity
    case pi

    /// The full name. AC-2.2-b's "GitHub Co…" is `githubCopilot`'s full
    /// "GitHub Copilot" truncating naturally inside the grid card's fixed
    /// column width (`OnboardingAgentCard`'s `.lineLimit(1)`) — this property
    /// deliberately returns the untruncated name; nothing here hand-clips a
    /// string to match the AC's literal ellipsis.
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        case .kimi: return "Kimi"
        case .hermes: return "Hermes"
        case .openCode: return "OpenCode"
        case .githubCopilot: return "GitHub Copilot"
        case .kiloCode: return "Kilo Code"
        case .droid: return "Droid"
        case .antigravity: return "Antigravity"
        case .pi: return "Pi"
        }
    }

    /// AB-166 (Connect screen) wiring: only Claude/Codex/Cursor map to a real,
    /// installable `AtlasIntegrationKind` (`AtlasIntegrationModels.swift`)
    /// today. The other nine are onboarding-only "which agents do you use"
    /// preference bits with nothing in this codebase to install yet — Connect
    /// is expected to treat a `nil` here as "acknowledged, nothing to install
    /// now" rather than a card with a broken install action.
    var integrationKind: AtlasIntegrationKind? {
        switch self {
        case .claude: return .claudeCode
        case .codex: return .codexCLI
        case .cursor: return .cursor
        default: return nil
        }
    }

    /// AB-166 Connect screen (AC-2.3-b: "Installing X hooks…") reads this for
    /// the real per-agent hook count, taken directly from each adapter's own
    /// hook-name enum rather than a hand-maintained constant, so the copy
    /// never drifts from what `LaunchIntegrationAutoInstaller` actually
    /// installs:
    /// - Claude: `ClaudeHookName.installableEvents` (12) — the curated
    ///   *install* subset, not the full ingest `allCases` (18; see that
    ///   property's own doc comment for why those differ).
    /// - Codex: `CodexHookName.allCases` (10) — `LaunchIntegrationAutoInstaller
    ///   .codexEntries` installs every case, there is no curated subset.
    /// - Cursor: `CursorHookName.allCases` (18) — same: every case is
    ///   installed (`CursorHooksAdapter.swift`'s `plannedEntries`-equivalent).
    /// `nil` agents have no `integrationKind` and so nothing installable.
    var installableHookCount: Int? {
        switch integrationKind {
        case .claudeCode: return ClaudeHookName.installableEvents.count
        case .codexCLI: return CodexHookName.allCases.count
        case .cursor: return CursorHookName.allCases.count
        case nil: return nil
        }
    }

    /// Brand icon mark this card renders. See `OnboardingAgentIconTile`
    /// (`OnboardingAgentsView.swift`) for the single shared tile every case
    /// draws through, so all 12 read as one uniform system.
    var iconMark: OnboardingAgentIconMark {
        switch self {
        // Claude/Codex reuse the exact marks + tokens already established
        // elsewhere in the app (`QuotaProvider.brandMarkGlyph`,
        // `UsagePresentation.swift`) — same "✳"/"◆" characters, same
        // `IslandTheme.claudeBrand`/`codexBrand` tints — so the brand read is
        // consistent across the overlay's usage cluster and onboarding.
        case .claude: return .character("✳")
        case .codex: return .character("◆")
        // "Cursor mono cube" per the spec doc's token table; `◨` is the same
        // glyph `UsagePresentation.swift` already uses for Cursor.
        case .cursor: return .character("◨")
        // OpenCode already has a real token + mark in this codebase too
        // (`IslandTheme.openCodeBrand`, doc: "OpenCode mono square", `▪` in
        // `UsagePresentation.swift`) even though it has no
        // `AtlasIntegrationKind` — reused for the same reason as Claude/Codex.
        case .openCode: return .character("▪")

        // The remaining eight have no brand asset anywhere in this repo.
        // Placeholders pending real brand assets: a plain SF Symbol or a
        // single-letter/glyph monogram, all drawn through the same
        // `OnboardingAgentIconTile` shape so the grid still reads as one
        // system rather than a mix of "real" and "fake" icon styles.
        case .grok: return .character("G")
        case .kimi: return .character("K")
        case .hermes: return .character("H")
        case .githubCopilot: return .symbol("chevron.left.forwardslash.chevron.right")
        case .kiloCode: return .symbol("terminal")
        case .droid: return .symbol("cpu")
        case .antigravity: return .symbol("arrow.up")
        case .pi: return .character("π")
        }
    }

    /// Per-card accent tint. Claude/Codex/Cursor/OpenCode reuse their real
    /// `IslandTheme` brand tokens; the other eight are placeholder accents
    /// (see `iconMark`'s doc comment) picked only to keep all 12 tiles
    /// visually distinct from each other and from the overlay's own semantic
    /// colors (`allowGreen`/`denyRed`/`accentAttention`/`statusBlocked`).
    var iconTint: Color {
        switch self {
        case .claude: return IslandTheme.claudeBrand
        case .codex: return IslandTheme.codexBrand
        case .cursor: return IslandTheme.cursorBrand
        case .openCode: return IslandTheme.openCodeBrand
        case .grok: return Color(red: 0x9A / 255, green: 0x9E / 255, blue: 0xA6 / 255)
        case .kimi: return Color(red: 0x74 / 255, green: 0x8C / 255, blue: 0xE0 / 255)
        case .hermes: return Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x46 / 255)
        case .githubCopilot: return Color(red: 0x8D / 255, green: 0x6C / 255, blue: 0xE8 / 255)
        case .kiloCode: return Color(red: 0x34 / 255, green: 0xB3 / 255, blue: 0xA6 / 255)
        case .droid: return Color(red: 0x8E / 255, green: 0x93 / 255, blue: 0x9C / 255)
        case .antigravity: return Color(red: 0x6C / 255, green: 0x74 / 255, blue: 0xE8 / 255)
        case .pi: return Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x8E / 255)
        }
    }
}

/// A brand icon mark: either a short literal character (an existing brand
/// glyph, or a monogram placeholder) or an SF Symbol name. Kept generic
/// (not `OnboardingAgent`-specific) so `OnboardingAgentIconTile` — and
/// anything AB-166's Connect screen reuses it for — can render a brand mark
/// for any future identity, not only this fixed roster.
enum OnboardingAgentIconMark: Hashable {
    case character(String)
    case symbol(String)
}
