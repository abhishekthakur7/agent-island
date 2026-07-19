# 17 — Implement Claude Code hook observation

## What to build

Deliver an opt-in Claude Code documented-Hooks Agent Adapter mode that observes compatible local Claude Code work through authenticated, classified local events. A person can explicitly install and inspect the integration, then see source-proven sessions, activity, completion/failure, Attention cues, sourced plan/question context, child work, and health without terminal scraping or an action claim beyond the separately delivered live hook-action capability.

## Context and constraints

This mode uses Claude Code’s documented hook surface and observed compatibility baseline, not Remote Control, cloud sessions, undocumented transcript layouts, terminal text, a competing resume process, simulated keystrokes, or arbitrary local files. The Claude native session ID, namespaced by the Adapter, is the only Agent Session identity. Model, working directory, transcript path, prompt ID, and labels are sourced attributed context, never merge keys.

The helper is application-owned, manifest-proven, uses authenticated local IPC, validates untrusted JSON and size, classifies fields before intake, redacts diagnostics, and never treats hook delivery as a generic action channel. Configuration writes are only fresh reviewed exact-entry operations; policy, permission modes, status lines, unrelated hooks, files, comments, symlinks, formatting, and external edits remain untouched.

## Acceptance criteria

- [ ] Explicit installation discovers configuration read-only, presents a fresh reviewable plan, adds only the exact manifest-proven application-owned hook entry at the chosen scope, verifies it afterward, and exposes enabled intent separately from observed health.
- [ ] The Adapter gates every observation capability by recorded Claude executable version and negotiated evidence; unknown/new/unsupported version or missing hook narrows only the affected capability and exposes an inspectable degraded/unavailable reason.
- [ ] Authenticated hook intake accepts only validated documented envelopes with Claude namespace/native session identity, source provenance, classification, ordering/continuity evidence, and source-proven parentage. Malformed, oversized, duplicate, cross-owner, or untrusted input is quarantined/rejected without creating state.
- [ ] Session start/activity events create or update the correct immutable-fact lineage. Transcript path lag, terminal/session cleanup, hook miss, interrupted session, compaction, restart, or differing hook order never fabricates continuity or completion.
- [ ] Stop produces completion only when its current source evidence permits it; a Stop with background tasks or scheduled wakeups remains active/idle, SessionEnd is cleanup rather than successful completion proof, and source StopFailure/PermissionDenied yields a sourced error/denial state rather than ordinary completion.
- [ ] Documented Notification events provide observation/reveal cues only; they do not create an action lease. PermissionRequest and PreToolUse context is retained only as protected, classified content owned by the exact session/request.
- [ ] Documented AskUserQuestion/ExitPlanMode shape and sourced plan Markdown are normalized as capability-scoped observation; unsupported free text/revision semantics are labelled unavailable and direct the person to the Host rather than inferring a response protocol.
- [ ] Source-proven SubagentStart/Stop creates nested child activity under its exact parent. A child start is never blocked, a child is terminal only with valid stop/result evidence, and transcript paths are neither read nor displayed merely because supplied.
- [ ] ConfigChange, version probe, and no-action helper probe update health/reconciliation evidence without adopting, rewriting, or auto-repairing configuration. Safe/bare/disabled hooks, workspace trust, invalid settings, managed policy, shadowed/removed entry, or helper loss show a non-destructive next step.
- [ ] Integration diagnostics contain redacted capability/health facts only; tool inputs, prompts, plan text, transcript paths, raw hook payloads, credentials, and command syntax remain out of Diagnostic Bundles.
- [ ] Observation continues to use only documented hooks. Missing events, helper timeout, local IPC loss, or transport restart retains an unresolved/degraded session and Host fallback rather than reading private Claude state or claiming a native request resolved.

## Required evidence

- Recorded documented-hook fixtures for concurrent sessions, activity, source completion/failure, background work, notification cue, question/plan context, and nested child lifecycle.
- Version/capability negotiation evidence and negative fixtures for unknown version, malformed input, duplicate/cross-owner event, hook timeout, helper/IPC loss, safe/bare mode, policy shadowing, and configuration drift.
- Exact-entry plan/apply/verify/removal evidence proving unrelated Claude configuration remains byte/semantics-preserved as appropriate and no automatic repair occurs.
- Redaction tests seeded with hook Interaction Content, paths, identifiers, and secret-like values.
- Parity-matrix evidence for applicable C-mode S1–S6, I5/I8, and degraded/fallback cells.

## Blocked by

- 04 — Deliver the Horizon session-monitoring experience
- 07 — Negotiate Adapter capabilities and expose honest integration health
- 08 — Manage Integration Installations without owning external configuration
