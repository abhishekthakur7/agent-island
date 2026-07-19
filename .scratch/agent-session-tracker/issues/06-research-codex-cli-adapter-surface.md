Status: closed
Type: research
Label: wayfinder:research
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 10-prototype-attention-completion-plan-and-question-workflows.md, 11-define-normalized-adapter-and-capability-contract.md, 13-define-attention-request-and-action-routing-semantics.md, 18-define-integration-setup-reconciliation-and-uninstall.md
Resolution: answered

# Research the Codex CLI adapter surface

## Question

Which documented and safely observable Codex CLI interfaces, versions, events, configuration locations, actions, approvals, questions, plan flows, subagent signals, usage data, and failure modes can support the Parity Baseline?

## Comments

### Resolution — 2026-07-18

The [Codex CLI adapter-surface record](../assets/codex-cli-adapter-surface.md)
identifies a safe two-path integration: version-pinned local app-server for
directly controlled Codex Threads and opt-in lifecycle hooks for
independently launched interactive CLI Sessions. It records native identity,
event, attention, question, plan, subagent, usage, configuration, and
diagnostic surfaces from the current Codex manual and local `codex-cli
0.144.5` schema generation.

The conclusion deliberately separates documented interfaces from local
implementation observations. App-server approval callbacks can be answered
only through their active, native request identity; structured questions and
plan deltas are capability-gated; hooks can observe but cannot take over a
terminal approval; and persisted JSONL/SQLite state is diagnostic-only, never
an authoritative event feed or write surface. The record also sets setup,
version negotiation, reconnect, stale-state, privacy, and uninstall constraints
for downstream adapter and attention decisions.
