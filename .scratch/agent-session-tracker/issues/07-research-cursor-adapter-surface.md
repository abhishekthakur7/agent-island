Status: closed
Type: research
Label: wayfinder:research
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 10-prototype-attention-completion-plan-and-question-workflows.md, 11-define-normalized-adapter-and-capability-contract.md, 13-define-attention-request-and-action-routing-semantics.md, 18-define-integration-setup-reconciliation-and-uninstall.md
Resolution: answered

# Research the Cursor adapter surface

## Question

Which documented and safely observable Cursor Agent and Cursor IDE interfaces, versions, events, extension points, actions, approvals, questions, plan flows, subagent signals, usage data, and failure modes can support the Parity Baseline without conflating the Agent Product and Host roles?

## Comments

### Resolution — 2026-07-18

Cursor supports two non-interchangeable capability tiers: Hook-based observation
of new local IDE Agent Sessions, and fully controlled ACP sessions that Agent
Island starts as the ACP client. Hooks provide stable conversation/Turn IDs,
activity, compaction, and partial Subagent Run evidence, but no documented
external response channel for native approvals, questions, or plan review. ACP
provides request-scoped permissions, multiple-choice questions, plans, todos,
subagent completion, cancellation, and terminal-status protocols only for the
sessions it owns. Cursor's IDE and Agents Window remain Host surfaces, not
Agent Product identity or navigation APIs.

See [Cursor adapter surface](../assets/cursor-adapter-surface.md) for the
evidence, capability tiers, sensitive-data treatment, version gates, and
failure/reconciliation requirements.
