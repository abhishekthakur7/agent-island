# 19 — Implement Codex CLI Hooks observation

## What to build

Deliver an opt-in Codex CLI Hooks Agent Adapter mode for independently launched terminal work. The person can explicitly install it and then monitor source-proven Codex sessions, turns, lifecycle/activity, permission cues, compaction, and child work in Agent Island. This mode queues/notifies and supports honest Host fallback, but never takes over a terminal-owned prompt, approval, or response.

## Context and constraints

Codex Hooks is an observation-only mode, distinct from direct app-server control. Its documented hook events may arrive concurrently and not in causal order. The native Codex session ID, namespaced by the Adapter, is the only Agent Session identity; turn IDs, working directory, model, transcript path, labels, and local timing are context/provenance rather than merge keys.

The stable hook interface is documented events/configuration, not private CODEX_HOME session files, observed JSONL rollout format, SQLite state, terminal scrollback, key injection, or generic process output. PermissionRequest only observes a terminal prompt; answering, denying, free text, and other terminal interaction remain in Codex. Configuration ownership is exact-entry and reversible.

## Acceptance criteria

- [ ] Explicit setup performs read-only discovery, presents a fresh exact-entry plan, installs only the manifest-proven selected hook entry, verifies it, and leaves unrelated configuration, comments, fields, profiles, hooks, session files, credentials, and CODEX_HOME untouched.
- [ ] Authenticated local hook intake accepts only supported, classified, version/capability-validated documented event shapes with native session/turn identity, provenance, and ordering evidence. Unknown/malformed/oversized/untrusted/cross-owner input is quarantined without creating lifecycle or routing state.
- [ ] SessionStart, UserPromptSubmit, Pre/PostToolUse, Pre/PostCompact, Stop, SubagentStart/Stop, and source-proven permission/activity cues reduce conservatively despite concurrent delivery; a missing, reordered, duplicated, or gap event remains unresolved rather than being guessed from receipt order.
- [ ] Source-proven Subagent work is nested under its native parent where parentage is supplied. It does not become a top-level session, fabricate child continuity, or complete its parent merely because an observed local file includes activity-like data.
- [ ] PermissionRequest creates an observation/attention cue only. The Guided view clearly labels in-Island response unavailable and offers revalidated Jump Back; no Action Lease, approval/deny callback, terminal prompt takeover, simulated terminal input, or generic text response exists in Hooks mode.
- [ ] Hook trust, disabled state, duplicate definitions/configuration layers, timeout, missing helper delivery, changed definition, profile/configuration drift, or unsupported version narrows observation health with redacted reasons and a non-destructive repair/manual remedy; it never marks a session complete or a request resolved.
- [ ] Any optional prompt/command content is sent only when the person explicitly enabled its protected local presentation; it remains Interaction Content and never enters notification payloads, diagnostics, or unconsented export/egress.
- [ ] Private Codex session files/rollouts and SQLite are never tailed as a live feed, mutated, or used for action routing. At most, a separately consented, version-gated, read-only diagnostic/reconciliation hint is represented as capability-limited evidence.
- [ ] Disable/remove deletes only the verified owned hook entry and application-owned receiver state after scope review; it does not delete Codex sessions, archives, compaction state, credentials, or unrelated hooks.

## Required evidence

- Hook fixtures for independent interactive sessions, concurrent/reordered events, turn/compaction activity, permission cue, and child start/stop hierarchy.
- Setup/verify/remove captures proving exact ownership and preservation of unrelated configuration and Codex local data.
- Negative evidence for permission response attempts, terminal injection, missing/untrusted/disabled/duplicate/timeout hook, changed config, and private-state feed prohibition.
- Content-classification/redaction tests for opted-in prompt/command context and Hook diagnostics.
- Parity-matrix evidence for applicable K-mode S1–S6, A6, and degraded/fallback cells.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
- 07 — Negotiate Adapter capabilities and expose honest integration health
- 08 — Manage Integration Installations without owning external configuration
