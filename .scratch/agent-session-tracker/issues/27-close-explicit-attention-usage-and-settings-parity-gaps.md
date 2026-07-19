Status: closed
Type: task
Label: wayfinder:task
Parent: ../MAP.md
Assignee: Terra-spec-gaps
Blocked by: 24-assemble-implementation-ready-product-and-architecture-specification.md
Blocks: 28-complete-parity-acceptance-matrix-and-deviation-register.md
Resolution: completed

# Close explicit attention, usage, and Settings parity requirement gaps

## Question

Which explicit requirements, implementation decisions, and acceptance scenarios must add A3's visible keyboard mappings and valid-answer gate, N5's capability-gated usage controls, and O3/O5's applicable General and Display controls to the implementation baseline, and which source behaviors are already-approved safe deviations rather than omissions?

## Comments

### Resolution — 2026-07-18

Closed the audit's explicit A3, N5, O3, O4, and O5 gaps in
[SPEC.md](../SPEC.md) and recorded their inventory mapping, exact additions,
acceptance scenarios, evidence, approved cleanup improvement, and capability
fallbacks in the linked [attention, usage, and Settings parity remediation
asset](../assets/attention-usage-settings-parity-remediation.md).

The specification now requires A3's visible choice mappings outside text
entry, no default selection, reversible selection, and valid-answer Next gate;
N5's capability-gated usage controls and unavailable fallback; and O3/O5's
complete applicable General and Display controls and read-only preview. It
also declares O4 custom Jump Back rules inapplicable to first-class Hosts
without a documented user-defined destination contract. The source idle
cleanup setting is recorded as the previously approved no-automatic-retention
material improvement, not an omission. Positive and negative scenarios cover
all five inventory rows. The audit-noted repeated phrase was reduced to one
occurrence. Story numbering remains 1–88, local asset links/headings resolve,
and `MAP.md` was intentionally not edited as directed.

Exact `Decisions so far` entry for the map owner to append:

```markdown
- [Close explicit attention, usage, and Settings parity requirement gaps](issues/27-close-explicit-attention-usage-and-settings-parity-gaps.md) — Made A3, N5, O3, O4, and O5 explicit and testable, recording the approved no-timer cleanup improvement and capability-honest fallbacks.
```
