Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-persistence
Blocked by: 04-define-local-first-privacy-security-and-future-service-boundaries.md, 12-define-canonical-event-and-session-lifecycle.md, 13-define-attention-request-and-action-routing-semantics.md, 14-define-host-context-identity-navigation-and-fallback.md
Blocks: 20-define-quality-attributes-and-failure-invariants.md, 22-select-application-architecture-and-component-boundaries.md, 23-specify-data-event-action-and-extension-contracts.md, 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Define persistence, history, recovery, and retention

## Question

Which canonical and derived state must survive restart; how are transcripts, events, requests, configuration, history, archives, cleanup, migration, export, corruption recovery, and retention handled locally without timers deleting active work or future hosted storage coupling the core model?

## Comments

### Resolution — 2026-07-18

The [persistence, history, recovery, and retention decision](../assets/persistence-history-recovery-and-retention.md) makes the protected local canonical store authoritative for accepted normalized facts and selected Adapter-supplied content, while treating cards, queues, and the 30-session working set as rebuildable presentation. History is retained until separately confirmed local deletion; the cap never evicts active, unresolved, attention-requiring, or child-active work. Restart persists evidence but makes live state unresolved, action leases stale, and Host locators unvalidated until documented reconciliation/revalidation proves otherwise.

The decision also requires atomic encrypted commits, versioned verified migrations, fail-closed corruption recovery, source-scoped deletion boundaries, distinct cleanup categories, explicit classified user-data export, redacted Diagnostic Bundles, and a local-only future-service seam. It does not create a raw Product-transcript archive, silently reset corrupt state, infer lifecycle from local artifacts, or couple core recovery to hosted storage.
