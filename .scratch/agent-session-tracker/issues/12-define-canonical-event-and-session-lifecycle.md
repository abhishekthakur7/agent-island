Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Codex
Blocked by: 03-define-domain-language-and-identity-boundaries.md, 11-define-normalized-adapter-and-capability-contract.md
Blocks: 13-define-attention-request-and-action-routing-semantics.md, 14-define-host-context-identity-navigation-and-fallback.md, 15-define-persistence-history-recovery-and-retention.md, 16-define-notifications-sounds-filters-and-usage-behavior.md, 20-define-quality-attributes-and-failure-invariants.md, 23-specify-data-event-action-and-extension-contracts.md
Resolution: answered

# Define the canonical event and Agent Session lifecycle

## Question

What normalized event taxonomy, ordering and deduplication rules, state transitions, ownership invariants, reconciliation rules, and recovery semantics produce correct Agent Session and Subagent Run state under duplicate, delayed, missing, reordered, rewind, compaction, restart, sleep, and host-closure scenarios?

## Comments

### Resolution — 2026-07-18

The [Canonical event and Agent Session lifecycle](../assets/canonical-event-session-lifecycle.md)
defines an immutable, provenance-preserving normalized fact sequence and a
conservative derived projection for Agent Sessions, Turns, and Subagent Runs.
Source-native IDs, documented ordering/revision evidence, explicit lineage,
and scoped reconciliation govern state; duplicate delivery is idempotent,
gaps/restarts/Host closure become unresolved observation rather than invented
completion, and rewind/compaction preserve historical turns in the same Agent
Session. [ADR 0003](../../../docs/adr/0003-immutable-event-facts-and-conservative-lifecycle-projection.md)
records the durable architecture decision.
