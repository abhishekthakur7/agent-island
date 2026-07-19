# 09 — Handle Attention Requests through the Guided workflow

## What to build

Deliver the compact Guided sheet for durable Attention Requests: Arrived → Review → Respond → Acknowledged, one focused item at a time, with a stable priority queue, preserved drafts, clear source ownership, and exact acknowledgement language. The sheet may route only a live, typed, request-scoped action; when capability is absent or stale, it must show the relevant context and an explicit Continue in Host/Jump Back fallback without dispatch.

This is a full visible workflow from validated native request evidence through durable local presentation and a single protected typed Action Attempt. It does not add generic text entry, terminal injection, or an action capability to observation-only modes.

## Context and constraints

- An Attention Request is created only from validated native request evidence and is identified by Product namespace plus native request identity, with immutable Agent Session/Turn/item/integration/semantic provenance. Textual similarity never merges requests.
- Source truth, routing availability, local presentation, draft state, and Action Attempt outcome are orthogonal. Collapse/local acknowledgement never resolves Product work.
- A live Action Lease is volatile, request/action scoped, bound to exact owner/capability/constraints/current native state/deadline, single-use, and revoked on source change, expiry, capability/gate change, reconnect, restart, and wake.
- Valid typed actions remain semantic-specific: source-provided allow/deny/persistent suggestion, structured response, plan accept/reject-with-reason, documented Turn input/interruption, or Product-namespaced extension. There is no generic execute/terminal input/reply-by-text fallback.
- Codex Hooks and Cursor Hooks observe/queue but cannot answer externally. Unsupported Claude/direct-Codex/ACP semantics likewise remain native-Host work and use the honest navigation fallback.

## Acceptance criteria

- [ ] Valid native attention evidence creates a durable, source-attributed request with exact owner tuple, constraints, classification, and local queue/presentation state; duplicate/text-identical/cross-session/missing-owner evidence cannot create or merge an actionable request.
- [ ] The Guided sheet renders the four stated stages, owning Agent Session/Turn/Product/Host context, compact queue, preserved selection/drafts, and a clear distinction between source result, local acknowledgement, Product accepted, Product applied, resolved elsewhere, rejected, and indeterminate.
- [ ] Queue ordering is stable by priority and source-observed time. A higher-priority arrival updates the indicator without stealing keyboard/VoiceOver focus, replacing an active item, or discarding a draft; collapse/Escape/quiet-scene presentation suppression does not resolve or remove the request.
- [ ] Review renders only source-supported response shape and minimum source context. Structured single/multi-choice starts with no default—including a recommended option—supports reversible selection, exposes number-key mappings only outside text entry, and keeps Next disabled until valid; multi-question/free-text drafts persist across queue/presentation changes when supported.
- [ ] Before each dispatch, core and Adapter validate exact ownership/current source state, compatible negotiation/capability, semantic constraints, native fingerprint/deadline, live unused lease, and required confirmation. Validation failure creates a rejected Action Attempt, sends zero Product actions, and never redirects input to another request.
- [ ] Reservation persists one Action Attempt before at most one typed dispatch, disables duplicate controls, and reports rejected, acceptedByProduct, applied, superseded, or indeterminate precisely. Indeterminate/stale/disconnected/resolved-elsewhere routes never auto-retry and retire to Host fallback.
- [ ] Unsupported/observation-only/stale routes remain visible with an explicit unavailable reason and Continue in Host/Jump Back. They cannot masquerade as action controls or claim an answer was sent/applied.
- [ ] Keyboard, VoiceOver, reduced-motion, high-contrast, and increased-text use preserves stage/owner/consequence/confirmation/fallback semantics; no new request makes the surface accessibility-modal or blocks Host input outside visible bounds.

## Required evidence

- Faithful/native request fixtures for supported action, observation-only request, stale/expired lease, owner/Turn mismatch, double activation/shortcut repeat, disconnect, source-resolved elsewhere, and indeterminate dispatch; include attempted-dispatch counts and visible acknowledgement.
- Guided-sheet UI/AX walkthrough covering approval/denial, structured question, draft preservation, plan review, queue priority, collapse/resume, Host fallback, keyboard-only, and VoiceOver paths.
- Durable-record/restart trace proving request/draft history persists while every live route/lease expires and no post-restart dispatch occurs.
- Redacted diagnostic correlation proving no raw lease/callback token, credential, or Interaction Content escapes protected presentation.

## Blocked by

- 02 — Persist and reopen one protected Agent Session
- 04 — Deliver the Horizon session-monitoring experience
- 07 — Negotiate Adapter capabilities and expose honest integration health
