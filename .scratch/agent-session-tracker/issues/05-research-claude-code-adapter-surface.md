Status: closed
Type: research
Label: wayfinder:research
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 10-prototype-attention-completion-plan-and-question-workflows.md, 11-define-normalized-adapter-and-capability-contract.md, 13-define-attention-request-and-action-routing-semantics.md, 18-define-integration-setup-reconciliation-and-uninstall.md
Resolution: answered

# Research the Claude Code adapter surface

## Question

Which documented and safely observable Claude Code interfaces, versions, events, configuration locations, actions, permission modes, questions, plan-review flows, subagent signals, usage data, and failure modes can support the Parity Baseline?

## Comments

### Resolution — 2026-07-18

The documented hook API is the supported Claude Code Agent Adapter boundary:
an opt-in application-owned local helper can observe native Agent Session,
lifecycle, permission, structured-question, plan, Subagent Run, and failure
events, and can synchronously return only documented permission/question/plan
decisions. It cannot safely provide arbitrary interactive-session prompting,
plan-revision text, cancellation, or passive live usage; those cases retain a
Host Context fallback. The compatibility, setup, capability, and degradation
contract is recorded in [Claude Code Agent Adapter surface](../assets/claude-code-adapter-surface.md).
