# 21 — Observe Cursor IDE Agent Sessions through Hooks

**Status:** ready-for-agent

## What to build

Deliver an explicit, reversible Cursor Hooks Integration Installation that observes compatible local Cursor IDE Agent Sessions created after installation and presents their sourced lifecycle, activity, compaction, and source-proven child-work evidence in Agent Island. It is an observation-only path: when Cursor owns an approval, question, plan, or cancellation, Agent Island clearly directs the person back to Cursor rather than pretending it can respond.

## Context and constraints

Cursor Hook observation is forward-only and must not discover or recover work from transcripts, terminal scrollback, private Cursor state, or presentation metadata. The Product namespace plus Cursor `conversation_id` is the Agent Session identity; `generation_id` identifies the Turn. Model, workspace roots, title, paths, and terminal/window data are attributed context, never identity.

Classify unknown Hook fields as Interaction Content. Do not retain `user_email`, ingest `transcript_path`, or export sensitive payloads. Hook timeout, crash, malformed input, unsupported version, and delivery gaps degrade observation and preserve conservative unresolved state; they never invent completion. `subagentStop` without enough source identity must leave ambiguous child completion unresolved. Cursor Hook commands are non-blocking and fail open; person-owned security policy is outside this Integration Installation.

## Acceptance criteria

- [ ] The person can read-only discover Cursor Hook eligibility and explicitly enable, disable, repair, and remove the exact Agent Island-owned Hook entries through an Integration Installation; unrelated Cursor configuration remains untouched.
- [ ] A supported post-install Cursor IDE conversation produces one namespaced Agent Session keyed by the received `conversation_id`, with Turns keyed by received `generation_id`; similar titles, roots, models, or windows never merge sessions.
- [ ] Supported start, activity, compaction, terminal outcome, and session-end observations are validated, classified, committed as Normalized Event Facts, and shown only with adapter-supplied detail.
- [ ] A source-proven `subagentStart` appears nested beneath its owning Agent Session. An insufficiently identified `subagentStop` retains an unresolved completion summary and cannot close a guessed child or parent.
- [ ] The adapter records Cursor version and negotiated observation capability. Unknown/incompatible version, Hook load failure, crash, timeout, malformed/oversized event, or missing continuity yields inspectable Degraded/Unavailable health and conservative state.
- [ ] Cursor Hook observation exposes no external approval, question, plan, free-text, cancellation, or terminal-input action. Any such Attention Request is visibly unavailable in Agent Island with a capability-honest Cursor Jump Back fallback and zero dispatches.
- [ ] Hook replay/weak-duplicate handling follows its documented evidence only; a collision or ordering gap is retained as ambiguity rather than merged or alerted as current work.
- [ ] The resulting Island and diagnostic presentation contain no transcript content, raw workspace paths, commands, thoughts, response text, user email, or raw Cursor identifiers outside their permitted protected local representation.

## Required evidence

- [ ] A faithful Hooks fixture or supported local Cursor installation demonstrates concurrent post-install conversations, lifecycle/activity updates, a sourced child, and the resulting nested Island state.
- [ ] Negative captures cover Hook failure/timeout, unknown version, malformed input, duplicate/gap delivery, same-looking conversations, and ambiguous child completion; each shows honest health/state without a false terminal result.
- [ ] An observation-only Attention Request capture shows the unavailable reason, a Cursor Jump Back outcome at the achieved level, and a recorded zero-dispatch assertion.
- [ ] Installation plan/apply/verify/remove and drift fixtures demonstrate exact-entry ownership and redacted diagnostics.

## Blocked by

- #04 — Deliver the Horizon session-monitoring experience
- #07 — Negotiate Adapter capabilities and expose honest integration health
- #08 — Manage Integration Installations without owning external configuration
