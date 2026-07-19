# Product direction defaults for downstream decisions

**Confirmed:** 2026-07-18  
**Status:** Product input for unresolved Wayfinder issues; these defaults do not
replace the evidence, edge-case analysis, or acceptance criteria each issue
must still produce.

The recommended positions below are approved unless downstream research finds
a safety, platform, or Agent Product constraint that requires an explicit
exception.

## Agent Session working set and lifecycle

- The main active/inactive Agent Session working set targets a maximum of 30
  sessions, ordered by Product-sourced creation time when available and local
  first-observed time only as an explicit fallback.
- The 30-session limit is a presentation working-set limit, not permission to
  lose canonical state or stop monitoring active work.
- When the working set exceeds 30, move the oldest inactive Agent Session to
  history first. Never evict an active or attention-requiring Agent Session to
  enforce the cap. If all retained sessions are active or require attention,
  the working set may temporarily exceed 30 until safe compaction is possible.
- Preserve sessions across Agent Island restart. Previously active sessions
  reappear as unresolved until fresh Product evidence establishes their current
  state.
- A disconnected integration leaves affected sessions visible with an explicit
  unknown/degraded state rather than marking them complete.
- Keep a parent Agent Session active while documented background work or
  Subagent Runs remain active.
- Preserve superseded/rewound Turns as history without crowding the compact
  island presentation.
- Use Product-originated interruption terminology where available; otherwise
  use a neutral incomplete/stopped presentation rather than completion.

## Attention Requests and Product actions

- Dismissing an Attention Request changes Agent Island presentation only; it
  never sends approval, denial, cancellation, or another Product action.
- Prioritize expiring and consequential requests ahead of ordinary questions,
  with stable age ordering inside the same priority.
- Persistent Product-provided permission changes require separate confirmation.
- Stale or mismatched requests are rejected, never rerouted or replayed.
- Indeterminate delivery is shown as unconfirmed with a Jump Back path; it is
  never presented as applied.
- Consequential shortcuts require confirmation where an accidental invocation
  could persist permission, deny work, cancel work, or cause a destructive
  action.
- Requests resolved in the native Product surface briefly show `Resolved
  elsewhere` before leaving the active queue.

## Jump Back

- Use the fallback ladder: exact Host Context, owning window/workspace, owning
  application, then an explanatory no-navigation result.
- Crossing macOS Spaces or leaving fullscreen is allowed only in response to
  an explicit Jump Back action.
- Never guess between ambiguous windows or panes; report the reduced capability
  or ask the person to choose when a safe chooser is available.
- Keep card selection/inspection separate from the explicit Jump Back action.
- Request Accessibility access contextually when a first relevant action needs
  it, while also exposing setup in onboarding and Settings.
- Historical Host Context evidence may remain visible but is never treated as
  a live navigation target without revalidation.

## Integration setup and removal

- Enable each Agent Product explicitly; do not silently configure newly
  discovered Products.
- Default to user-level personal configuration and avoid repository/worktree
  configuration unless the person explicitly chooses it.
- Do not automatically repair or migrate an externally changed or ambiguous
  configuration entry. Present a reviewable, non-destructive plan.
- Put custom executable paths and alternate installations in advanced setup.
- Runtime disablement is reversible and does not imply configuration removal.
- Complete removal separately offers removal of owned integration entries,
  local history, preferences, and diagnostics.
- Use direct, Developer ID/notarized distribution as the planning default
  unless later platform research establishes a compelling Mac App Store path.

## Health, onboarding, Settings, and diagnostics

- Use the summary states `Disabled`, `Setup required`, `Healthy`, `Degraded`,
  `Unavailable`, and `Incompatible`, backed by inspectable health dimensions.
- Show concise integration status first and place evidence/recovery detail
  behind disclosure.
- Report partial capability loss as degraded even when observation remains
  operational.
- Show actionable setup failures in Settings and, when they affect current
  work, in a dismissible island notice.
- Diagnostic Bundle output includes redacted human-readable Markdown and
  machine-readable JSON.
- Explain material capability differences during setup without forcing all
  protocol detail into the first-run flow.
- Keep reset, owned-configuration removal, history deletion, and complete
  cleanup as distinct consequential actions.

## Runtime and extension posture

- Plan for a native Swift/AppKit/SwiftUI macOS application distributed outside
  the Mac App Store with Developer ID signing and notarization.
- Permit constrained application-owned local helpers and a login/background
  item where required for reliable local event reception.
- Isolate failure-prone or security-sensitive Adapter work from the UI/core
  where platform research shows a separate process or service is appropriate.
- Public third-party Agent Adapter loading is not a v1 requirement. Preserve a
  future extension seam without accepting arbitrary third-party code now.
- Treat schemas as internal versioned contracts in v1. Persist migratable
  canonical facts rather than a general raw Product-event archive.
- Keep future hosted-service interfaces internal and outbound-only; a redacted
  Diagnostic Bundle is not a general state-export API.

## Initial quality targets

- Design and test the normal working set for up to 30 active/inactive Agent
  Sessions, with safe temporary overflow for active or attention-requiring
  work.
- Target Product-event-to-presentation latency below 250 ms locally and local
  action dispatch below 150 ms before Product processing.
- Target launch-to-usable below one second warm and below two seconds cold on
  supported Apple Silicon hardware.
- Require negligible idle CPU use and bounded memory/energy behavior; exact
  numeric budgets follow implementation-stack research and measurement.
- Trip safety controls immediately on identity, authentication, or
  cross-session routing violations; tolerate and diagnose ordinary transient
  transport failures before escalating to a capability-local circuit breaker.
- Require complete keyboard operation, VoiceOver semantics, reduced-motion
  behavior, increased-contrast support, and usable text scaling.
- Do not promise that a synchronously leased Product request survives Agent
  Island restart. Instead preserve its durable Attention Request record, mark
  routing unavailable/stale, and retain the native Product fallback.

