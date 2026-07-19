# 25 — Jump Back to Warp Host contexts

**Status:** ready-for-agent

## What to build

Provide the deliberately limited Warp Jump Back experience: activate/launch Warp as the supported baseline, with an optional Accessibility-gated `windowBestEffort` route only when one current matching window is uniquely found. The person always sees that the original Warp pane or tab was not verified.

## Context and constraints

Warp exposes no supported local API or durable identifier for selecting a window, tab, pane, or block. Its URL scheme, titles, block text, terminal content, paths, and Accessibility labels cannot create an exact Host Context or navigation claim. Accessibility is opt-in, requested only at the moment a person elects the best-effort route, and must never be used for automated input.

The baseline outcome is `appOnly`; `windowBestEffort` is a limited foreground result, not a match guarantee. No generic custom destination grammar is in scope for Warp.

## Acceptance criteria

- [ ] A Warp-associated Agent Session can offer Jump Back only with supported app activation, an explicit optional Accessibility best-effort window route, or `unavailable` as current capability/permission permits.
- [ ] Baseline app activation returns `appOnly` with text, VoiceOver, and diagnostic feedback that the original context could not be located.
- [ ] The optional Accessibility route is unavailable until the person deliberately enables it after contextual explanation of its Host, limitation, and fallback.
- [ ] A current Accessibility query may return `windowBestEffort` only for exactly one matching window; zero or multiple candidates never select by score and fall back safely.
- [ ] Warp title, tab/pane/block text, URL scheme, terminal output, path, frame, Space, or Accessibility label cannot be retained as an exact locator or used to invent a match.
- [ ] Permission denial/revocation, host absence, query failure, full-screen/Space conditions, and duplicate candidates produce the named lower result or `unavailable` without simulated input, clicks, or keystrokes.
- [ ] The achieved navigation level is persisted as redacted operational metadata and remains wholly separate from Agent Session lifecycle and Action Lease authority.

## Required evidence

- [ ] A Warp fixture demonstrates `appOnly`, explicitly opted-in unique-window `windowBestEffort`, and unavailable outcomes with correct person-visible and VoiceOver wording.
- [ ] Negative captures cover denied/revoked Accessibility, zero/multiple matching windows, same-title windows, URL scheme availability, and full-screen/Space changes without a false exact claim.
- [ ] A diagnostic capture proves no interaction content, raw title, path, or locator is exported.

## Blocked by

- #06 — Deliver resumable onboarding and the Atlas Settings shell
- #10 — Navigate through the capability-honest Jump Back ladder
