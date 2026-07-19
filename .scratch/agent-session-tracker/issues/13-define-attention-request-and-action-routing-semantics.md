Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: 05-research-claude-code-adapter-surface.md, 06-research-codex-cli-adapter-surface.md, 07-research-cursor-adapter-surface.md, 10-prototype-attention-completion-plan-and-question-workflows.md, 11-define-normalized-adapter-and-capability-contract.md, 12-define-canonical-event-and-session-lifecycle.md
Blocks: 15-define-persistence-history-recovery-and-retention.md, 16-define-notifications-sounds-filters-and-usage-behavior.md, 20-define-quality-attributes-and-failure-invariants.md, 23-specify-data-event-action-and-extension-contracts.md
Resolution: answered

# Define Attention Request and action-routing semantics

## Question

What durable lifecycle, queueing, validation, authorization, response, acknowledgement, expiration, dismissal, retry, and permission-mode rules ensure every approval, question, plan response, cancellation, and shortcut reaches only its owning Agent Session and turn?

## Comments

### Resolution — 2026-07-18

The [Attention Request and action-routing semantics](../assets/attention-request-action-routing-semantics.md)
make Attention Requests durable source-attributed records while reserving
Product control for a live, one-use Action Lease scoped to the exact native
request and owner tuple. The contract separates source truth, routing,
presentation, and drafts; defines queue order, validation, confirmation,
acknowledgement, expiry, retry, recovery, permission, cancellation, shortcut,
and Host-fallback rules; and prohibits stale, ambiguous, or cross-session
actions. [ADR 0004](../../../docs/adr/0004-live-action-leases-for-attention-routing.md)
records the deliberately durable-history/ephemeral-authority boundary.
