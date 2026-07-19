# 28 — Recover safely across restart, wake, disconnect, and termination

**Status:** ready-for-agent

## What to build

Make restart, sleep/wake, adapter/Host disconnect, display recovery, and explicit Quit safe cold-resume boundaries. Agent Island restores verified protected evidence and local drafts, rebuilds derived state conservatively, and makes formerly live work unresolved until documented reconciliation supplies fresh proof; no volatile authority, locator, input, reveal, or action is revived.

## Context and constraints

This is recovery integration, not a new persistence engine or feature bundle. The canonical store remains local, encrypted, immutable, and single-writer; projections are replaceable. A Host closure, helper exit, missing non-exhaustive list item, transport loss, or local action outcome must not create Product completion or resolve an Attention Request. Reconciliation uses only documented read/list/replay/status/probe capabilities—never private Product state, transcript, terminal scrollback, title/path similarity, or an automatic Host launch.

On restart/wake all Action Leases expire and all Host locators become unvalidated. Quit first removes presentation/input regions and cancels local activity, then persists durable state and stops application-owned helpers; it must never dispatch pending Product work.

## Acceptance criteria

- [ ] Launch and wake integrity-check protected state, load a verified projection or deterministically rebuild it from accepted Normalized Event Facts, and expose a visible fail-closed recovery state when key/schema/ciphertext integrity is not usable.
- [ ] Formerly active or waiting Agent Sessions remain retained but become unresolved with degraded/unavailable observation until fresh authoritative evidence proves only the repaired state or field.
- [ ] Durable Attention Requests and unsent drafts survive recovery, while every Action Lease/callback route expires; stale routes cannot dispatch and offer their honest native-Host fallback.
- [ ] Every persisted Host locator becomes unvalidated at restart/wake. Exact Jump Back requires a fresh read-only documented Host probe; otherwise only an independently proven lower level is available.
- [ ] Adapter, Host, display, and integration disconnect/reconnect changes only the affected capability/health and never completes, merges, dismisses, or resurrects Agent Sessions, requests, or action authority.
- [ ] Recovery appends/retains boundary and reconciliation evidence, deduplicates documented replay safely, preserves gaps/ambiguity, and never uses private Product data or presentation similarity to restore continuity.
- [ ] Sleep/wake cancels hover/reveal timers and keyboard engagement and recreates a usable Overlay only from current display placement and durable projection; it replays no input, focus, reveal, sound, notification, or Action Attempt.
- [ ] Explicit Quit removes global monitors and Overlay hit/accessibility regions, cancels timers/animations, invalidates volatile authority, persists durable records, stops only application-owned helpers, and leaves no ghost UI/shortcut/process or pending Product dispatch.
- [ ] Repeated restart, wake, reconnect, display-loss, and termination cycles complete without crash, duplicate current fact, ghost card, false completion, stale exact navigation, or focus theft.

## Required evidence

- [ ] Deterministic crash/restart and sleep/wake fixtures show verified rebuild, unresolved former-live work, retained drafts/requests, expired leases, invalidated locators, and no replayed action or presentation.
- [ ] Adapter/Host/displays disconnect/reconnect and non-exhaustive reconciliation fixtures prove capability-local degradation and conservative recovery.
- [ ] Missing Keychain key, ciphertext/schema/projection failure, and interrupted migration evidence demonstrates fail-closed recovery, protected-byte preservation, and redacted diagnostic/recovery paths.
- [ ] Quit captures from collapsed, expanded, keyboard-engaged, and pending-attention states prove monitor/hit-region/helper cleanup and zero Product dispatch.

## Blocked by

- #13 — Export redacted diagnostics and perform scoped maintenance
- #16 — Support safe shortcuts, keyboard operation, and adaptive accessibility
- #17 — Observe Claude Code sessions through a managed Integration Installation
- #18 — Route supported Claude Code attention actions
- #19 — Observe independently launched Codex CLI sessions
- #20 — Monitor and control direct Codex app-server sessions
- #21 — Observe Cursor IDE Agent Sessions through Hooks
- #22 — Start and control Cursor ACP sessions
- #23 — Jump Back to live iTerm2 contexts
- #24 — Jump Back to Cursor Host contexts
- #25 — Jump Back to Warp Host contexts
- #26 — Jump Back to Orca Host contexts
