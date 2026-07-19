# 03 — Derive conservative Agent Session lifecycle from immutable facts

## What to build

Turn persisted normalized evidence into a deterministic, replay-safe Agent Session lifecycle projection. The app must distinguish execution, attention, observation, and lineage rather than collapsing them into one status, and it must prefer unresolved over a plausible completion whenever continuity or ownership is not proven.

This ticket makes the first session trustworthy through duplicate, reorder, gap, child-work, rewind, compaction, reconnect, and recovery cases. It delivers visible lifecycle states from facts only; it does not add action routing or Host navigation.

## Context and constraints

- Only a validated Product fact or scoped documented reconciliation may change Product lifecycle. Local receipt order, elapsed time, UI interaction, action outcome, Host closure, helper exit, and transport loss cannot.
- Stable source-event IDs are idempotent. A declared weak deduplication key may suppress only its documented replay; a collision remains ambiguity/gap evidence, never a merge.
- Product-native session/Turn/Subagent Run ownership is immutable. Rewind and compaction preserve historical Turns within the same Agent Session; a different native session ID stays distinct.
- The projection must independently represent execution (`working`, `waiting`, terminal outcomes, `unresolved`), attention, observation freshness/gap, and current/historical/ambiguous lineage. A known active/waiting child or pending Attention Request prevents confident parent terminal presentation.
- Source cursors/revisions govern comparable ordering; receipt ordinal is audit order, not invented Product truth. Conflicting incomparable terminal evidence and continuity gaps become unresolved.

## Acceptance criteria

- [ ] Given the same committed fact ledger and projection inputs, the reducer produces the same revisioned Agent Session/Turn/Subagent Run projection on initial intake, replay, restart rebuild, and migration verification.
- [ ] Valid named source activity produces only the lifecycle it proves: explicit work/wait/terminal/failure/stop facts map conservatively, while absence of evidence, Host loss, transport loss, helper exit, and local action results do not create completion.
- [ ] Stable duplicate delivery is idempotent; reorder, equal timestamps, cursor gaps, source resets, contradictory incomparable facts, and weak-key collisions retain evidence and yield the applicable unresolved/gap state rather than a guessed winner.
- [ ] Rewind, retry, fork, and compaction preserve historical Turns and facts. A late event for a replaced historical Turn cannot overwrite the current lineage; a new native Agent Session is not merged into the old one.
- [ ] A proven Subagent Run remains nested under its owning Agent Session. A parent cannot become terminal while a proven child is working/waiting or attention is pending; ambiguous child completion makes the affected parent unresolved.
- [ ] Documented reconciliation records scope and authority. A non-exhaustive list omission, reconnect without authoritative continuity, or unavailable read leaves current truth unresolved and never triggers relaunch/scraping/private-state inference.
- [ ] Lifecycle labels exposed to presentation distinguish working, needs attention, completed, stopped, failed, and unresolved with non-color semantics and retain source-proven detail only.

## Required evidence

- Deterministic fixture suite covering stable and weak duplicates, reorder/equal times, gaps/resets, conflict, rewind, compaction, parent/child activity, parent terminal evidence with child work, restart/wake, and documented versus non-exhaustive reconciliation.
- Positive/negative trace showing facts, authority/frontier evidence, derived tuple, visible state, and redacted diagnostics; include proof that transport/Host loss and local action acceptance do not manufacture Product completion.
- Replay-versus-rebuild comparison for the same ledger revision, showing identical projection output.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
