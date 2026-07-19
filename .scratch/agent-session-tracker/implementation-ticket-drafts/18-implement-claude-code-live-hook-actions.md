# 18 — Implement Claude Code live hook actions

## What to build

Enable only the documented live synchronous Claude Code hook decisions that the person can safely complete in the Guided Attention workflow: exact permission allow/deny, an exact Product-offered persistent permission suggestion, documented structured AskUserQuestion answers, and the documented ExitPlanMode approval path. Every other requested interaction—free-text revision, arbitrary prompt, cancellation, mode cycling, or subagent steering—remains native to the Host with an honest Jump Back fallback.

## Context and constraints

Observation is not action authority. A Claude Action Lease exists only while one exact synchronous PermissionRequest or applicable PreToolUse callback is live; its request identity includes the native session, prompt ID where present, hook event, supplied tool-use ID where present, callback input fingerprint, and fresh nonce. PermissionRequest lacks a tool-use ID and must never be matched by text or a later request.

The live helper validates before returning one typed response and fails closed to the native terminal when expired, disconnected, duplicate, mismatched, invalid, or unavailable. Durable Attention Request, drafts, local acknowledgement, and redacted Action Attempt evidence survive; callback authority, nonce, and lease do not survive restart, wake, reconnection, source update, deadline, or helper loss.

## Acceptance criteria

- [ ] A valid live Claude callback creates one durable Attention Request with exact immutable owner/provenance tuple, semantic variant, allowed response schema, native constraints, deadline, and protected minimal source context.
- [ ] The Guided workflow exposes only source-proven actions: permission allow/deny; one offered persistent permission suggestion; complete documented structured/multi-select answer map; and valid plan approval input. It exposes no generic reply, command, terminal injection, arbitrary plan feedback, cancellation, or mode control.
- [ ] Permission updates can only echo an exact Product-provided suggestion and always require a second explicit confirmation that repeats its persistence scope. Existing deny/ask/managed policy wins; Agent Island never enables bypass or broadens a rule/mode.
- [ ] AskUserQuestion and ExitPlanMode responses require valid complete updated input as documented; allow alone is insufficient. Recommended options begin unselected, mappings are disabled during text composition, and no invalid/incomplete answer enables submission.
- [ ] Before dispatch, core and helper independently validate exact owner tuple, open/current request, callback fingerprint, mode/snapshot/capability, semantic constraints, deadline, live single-use lease, and deliberate confirmed gesture. Any failed check persists a redacted rejected attempt and sends nothing.
- [ ] Lease reservation atomically disables equivalent controls and creates one durable Action Attempt. The helper returns exactly one validated native callback response; double click, shortcut repeat, duplicate callback, timeout, disconnection, or crash cannot duplicate it.
- [ ] The acknowledgement distinguishes rejected-before-dispatch, Product accepted, Product applied, resolved elsewhere/superseded, and indeterminate. Local sheet acknowledgement/dismissal never claims native resolution.
- [ ] Timeout, helper loss, malformed callback, source resolution elsewhere, restart/wake, reconnect, capability change, or stale/mismatched request retires routing and leaves the durable request/unsent draft visible with a Host fallback; no stale retry or callback recreation occurs.
- [ ] A live action that cannot be completed before the hook deadline fails closed to native Claude Code; it does not block, alter, or relaunch the terminal session and does not simulate input.
- [ ] VoiceOver, keyboard, reduced-motion, high-contrast, and native-Host fallback views expose owner, consequence, confirmation, disabled reason, and exact known outcome without bypassing any action gate.

## Required evidence

- Faithful/live callback fixtures for allow/deny, offered persistent suggestion, single/multi-choice answer, and plan approval, including typed native response capture.
- Cross-session/callback collision, stale/deadline/reconnect/restart/helper-loss, double-submit/shortcut-repeat, invalid-answer, managed-policy, and resolved-elsewhere zero-dispatch traces.
- Acknowledgement evidence differentiating rejected, accepted-by-Product, applied, superseded, and indeterminate without false lifecycle completion.
- Accessibility and confirmation recordings for consequential actions and unsupported semantic Host fallbacks.
- Parity-matrix evidence for applicable C-mode A1–A7 and P3, including the approved capability-scoped fallback.

## Blocked by

- 09 — Handle Attention Requests through the Guided workflow
- 17 — Implement Claude Code hook observation
