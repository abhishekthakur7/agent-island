# Live action leases for Attention Request routing

Agent Island retains an Attention Request as durable source-attributed history but routes a response only with a live, single-use Action Lease bound to its exact Product-native owner tuple, negotiated capability, permitted semantic response, and expiry. This deliberately separates durable visibility from short-lived authority: it prevents cross-session routing and stale approvals across restart, reconnect, source resolution, or Product change while preserving the native Host as the honest fallback.

## Consequences

- Presentation dismissal, local acknowledgement, and draft retention never resolve an Agent Product request.
- Each explicit response or control is one typed Action Attempt with independently proven `rejected`, `acceptedByProduct`, `applied`, `superseded`, or `indeterminate` outcome; ambiguous delivery is never retried automatically.
- Persistent permission changes and cancellation remain separately confirmed, capability-scoped actions rather than extensions of a generic approval button.
