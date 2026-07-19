# Immutable event facts and conservative lifecycle projection

Agent Island records validated, provenance-preserving normalized event facts
immutably and derives Agent Session, Turn, and Subagent Run lifecycle state as
a conservative projection. The Product-native event identity, source ordering
evidence, and explicit reconciliation scope govern reduction; receipt order,
Host lifetime, missing delivery, and local action results cannot manufacture
Product lifecycle truth. This separates recoverable evidence from an
intentionally replaceable current view, permits rewind and compaction within a
stable Agent Session, and makes duplicate, delayed, or disconnected delivery
safe.

## Consequences

- Events with stable source IDs are idempotent; weaker Adapter keys only
  suppress documented duplicate delivery and preserve ambiguity rather than
  merging Product work.
- A lifecycle card is derived from independent execution, attention,
  observation, and lineage dimensions. `unresolved` is the required outcome
  for a gap, restart, contradictory incomparable evidence, or unproven
  continuity; transport or Host loss never implies completion.
- Reconciliation is permitted solely through a documented Product surface and
  retains its authority/scope. Historical facts and rewound Turns remain
  inspectable, while stale action leases are not recovered after a restart.
