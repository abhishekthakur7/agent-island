# 22 — Start and control Cursor ACP sessions

**Status:** ready-for-agent

## What to build

Let a person deliberately start a Cursor CLI Agent Session through Agent Island’s ACP client and monitor or respond to only that controlled session through its live, typed ACP contract. The session’s lifecycle, requests, plans, todos, and source-proven child completion appear in Agent Island; direct interaction is available only while the matching ACP callback and Action Lease are live.

## Context and constraints

ACP must never attach to an arbitrary existing Cursor IDE or interactive CLI conversation. Persist only Cursor source IDs returned for an Agent Island-started session; `session/load` may resume only IDs recorded by this adapter. EOF, child-process exit, JSON-RPC failure, auth failure, disconnect, or an unknown method is degradation—not a completion fact.

Use the negotiated, version-pinned ACP protocol and retain its Product-specific semantics. Support documented structured choices, not manufactured free-text questions; no Cursor ACP usage estimate is permitted. Every consequential response follows the Guided workflow, is backed by a fresh single-use Action Lease, persists exactly one Action Attempt before at most one handoff, and never retries indeterminate dispatch.

## Acceptance criteria

- [ ] A person can explicitly start a controlled Cursor ACP Agent Session and see it as a distinct Cursor Agent Session with only source-returned native identity.
- [ ] The adapter negotiates and records the ACP contract/version, authenticated connection, capability scope, and health; incompatible or changed protocol evidence narrows capability and triggers read-only reprobe rather than optimistic operation.
- [ ] Source `session/update` and prompt stop evidence produce validated facts and conservative current state; transport loss or child-process exit cannot complete, merge, or silently resume a session.
- [ ] A live documented permission request renders only allow-once, allow-always, or reject-once as offered by the source and routes the chosen typed response once only when owner tuple, request state, capability, and Action Lease all match.
- [ ] A documented multiple-choice question renders its supplied choices and allowed multi-select behavior with no implicit default; draft changes remain reversible and validation prevents incomplete submission.
- [ ] A documented plan request renders its source plan and todos and permits only accept, reject-with-reason, or cancel as negotiated; it does not alter Cursor permission mode or create a generic reply channel.
- [ ] Source todo and child-completion information is presentation-only and remains nested below the owning Agent Session only when the envelope proves lineage.
- [ ] Stale, reused, mismatched, resolved, disconnected, unsupported, or indeterminate routes dispatch zero or one action as appropriate, show the exact unavailable reason, and offer Jump Back without claiming Cursor applied an action.
- [ ] Existing interactive Cursor CLI/IDE sessions, SDK-created work, headless work, deep links, and native IDE threads cannot enter this control path merely because they look related.

## Required evidence

- [ ] A controllable ACP fixture captures session creation, update, permission, structured question, plan, todo, child completion, and graceful terminal outcome.
- [ ] Negative contract fixtures cover protocol/version change, auth/stdio loss, stale or double lease use, owner mismatch, source-side resolution, and indeterminate dispatch; each includes the Action Attempt and zero/one handoff evidence.
- [ ] A comparison capture proves an independently launched Cursor conversation is observation-only/uncontrolled and cannot be loaded or actioned by ACP.
- [ ] Accessibility and keyboard evidence demonstrates visible choice mappings, no default selection, draft retention, disabled invalid submission, and the same confirmation/lease gate as pointer controls.

## Blocked by

- #04 — Deliver the Horizon session-monitoring experience
- #07 — Negotiate Adapter capabilities and expose honest integration health
- #08 — Manage Integration Installations without owning external configuration
- #09 — Handle Attention Requests through the Guided workflow
