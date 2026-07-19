# Versioned, capability-scoped Agent Adapter boundary

Agent Island integrates each Agent Product through a version-negotiated Agent Adapter contract whose capabilities are scoped to the configured integration mode, Agent Session, and live native request rather than inferred from Product identity. The boundary normalizes identity, provenance, health, ownership, and typed outcomes while retaining Product-specific semantic variants; actions fail closed on missing evidence, incompatibility, degradation, or a kill switch because a lowest-common-denominator API would create false capability claims and unsafe cross-session control.

## Consequences

- Observation, action, configuration, and navigation claims are negotiated independently and retain their evidence and constraints.
- Product-specific extensions may add meaning but cannot bypass identity, data-classification, configuration-ownership, health, or dispatch-gate invariants.
- A changed or unknown Product/interface version triggers reprobe and capability-local degradation instead of optimistic compatibility.

