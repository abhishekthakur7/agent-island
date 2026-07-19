Status: closed
Type: grilling
Label: wayfinder:grilling
Parent: ../MAP.md
Assignee: Terra-contracts
Blocked by: 12-define-canonical-event-and-session-lifecycle.md, 13-define-attention-request-and-action-routing-semantics.md, 14-define-host-context-identity-navigation-and-fallback.md, 15-define-persistence-history-recovery-and-retention.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 22-select-application-architecture-and-component-boundaries.md
Blocks: 24-assemble-implementation-ready-product-and-architecture-specification.md
Resolution: answered

# Specify data, event, action, and extension contracts

## Question

What implementation-neutral schemas, identifiers, versioning rules, invariants, commands, events, persistence boundaries, adapter interfaces, Host interfaces, diagnostics envelopes, and future telemetry or hosted-storage ports must the architecture specification define?

## Comments

### Resolution — 2026-07-18

The [data, event, action, and extension contracts](../assets/data-event-action-and-extension-contracts.md)
make the protected local canonical ledger, immutable Normalized Event Facts,
native owner tuples, and immutable negotiation provenance the implementation
boundary for Agent Island. They specify versioned envelopes and taxonomy;
source ordering, deduplication, corrections, and gaps; canonical versus
derived records; typed commands, Action Attempts, volatile Action Leases, and
acknowledgements; atomic persistence, snapshots, migration, and deletion;
Agent Adapter, Host, helper/IPC, configuration, diagnostics, export, and
future outbound ports; plus capability/degradation envelopes, evolution rules,
representative schemas, and contract fixtures. The contracts preserve local
privacy and fail-closed capability behavior without selecting a serialization
syntax or adding a public plug-in API.
