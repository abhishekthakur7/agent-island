# 12 — Implement protected Session History

## What to build

Give a person a protected local Session History that keeps safely inactive Agent Sessions inspectable without crowding the compact Island working set. When more than 30 sessions are retained, the oldest safely inactive session moves to this Archive tier with its sourced recap and history intact. The person can inspect historical evidence and explicitly delete selected inactive local history, while active work remains visible and intact.

## Context and constraints

Session History is Agent Island’s protected local record, not an Agent Product transcript store. Archive is a presentation/storage tier, not a Product lifecycle state, completion claim, monitoring stop, or deletion. Canonical facts and protected Adapter-supplied Interaction Content remain locally encrypted; cards, queues, search/indexes, working-set placement, and snapshots are rebuildable projections.

Only a terminal-by-current-Product-evidence session with no open Attention Request and no known active/waiting Subagent Run is safely inactive. Unresolved is never safe. Product-native identity remains authoritative across a late event, rewind, compaction, and reconnection; a label, path, title, transcript resemblance, Host Context, or timestamp cannot revive or merge history.

## Acceptance criteria

- [ ] The compact working set retains up to 30 active and inactive top-level Agent Sessions, with all top-level and nested ownership relationships preserved.
- [ ] On a thirty-first session, the oldest safely inactive session moves to Session History losslessly; its facts, historical/rewound Turns, sourced recap, source-proven children, and authorized received content remain inspectable in the correct ownership context.
- [ ] An active, waiting, unresolved, attention-requiring, or known child-active/child-waiting session is never archived merely to satisfy the compact limit; if no safely inactive session exists, the visible working set exceeds 30.
- [ ] Archive ordering uses Product-sourced creation time when supplied and clearly identifies local first-observed time as its fallback.
- [ ] A later authoritative fact for the same native owner can return an archived session to the working set; a similar title, path, prompt, transcript, model, or recreated Host Context cannot.
- [ ] Archive transition and restoration do not change Product lifecycle, imply that Product monitoring stopped, consume a live Action Lease, invalidate unrelated history, or suppress an independent Attention Request.
- [ ] History remains protected across crash, restart, and sleep/wake. Reopened current cards are rebuilt from verified immutable facts; formerly live work is conservatively unresolved until fresh documented evidence arrives, and no live locator or Action Lease is restored.
- [ ] A Session History view provides bounded inspection and explicit local scope for delete, without presenting it as an Agent Product transcript, deletion, or terminal-state control.
- [ ] Delete selected Session History requires a scope preview and consequential confirmation, then removes only that selected inactive session’s local facts, received content, dependent request/draft/Action Attempt records, and local Host-association evidence.
- [ ] Historical deletion does not send a Product action, alter setup, delete Product data, remove another session, or expose a stale response route. It leaves only the minimum protected non-content owner/source-range boundary necessary to suppress documented old replay.
- [ ] A separately named active-local-history deletion flow first stops only the selected local observation scope and then requires its own confirmation; it never claims the Agent Product stopped and permits only fresh documented evidence to establish new local history.
- [ ] Crash, migration, decryption, and projection recovery paths preserve verified History or show an honest recovery/unavailable state rather than silently resetting, fabricating a card, or deleting evidence.

## Required evidence

- A 30-session workload capture covering inactive overflow, all-active/all-attention overflow, nested child work, selection, recap, and accessible History inspection.
- A late-event and rewind/compaction fixture proving identity-safe return from Archive and rejection of presentation-similarity revival.
- Redacted crash/restart/wake and failed-integrity traces proving deterministic rebuild, unresolved recovery, and invalidated action/navigation authority.
- Confirmed deletion evidence proving exact selected scope, replay-boundary behavior, no Product mutation, and no cross-session removal.
- Parity-matrix records for S2, S5, O3, and H, including the approved no-timer-cleanup deviation.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
- 03 — Derive conservative Agent Session lifecycle from immutable facts
- 04 — Deliver the Horizon session-monitoring experience
- 06 — Deliver resumable onboarding and the Atlas Settings shell
