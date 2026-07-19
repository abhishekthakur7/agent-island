Status: closed
Type: task
Label: wayfinder:task
Parent: ../MAP.md
Assignee: Terra-parity-matrix
Blocked by: 27-close-explicit-attention-usage-and-settings-parity-gaps.md
Blocks: 25-audit-parity-traceability-and-requirements-completeness.md
Resolution: completed

# Complete the parity acceptance matrix and deviation register

## Question

What complete, versioned parity record maps every applicable S1–S6, I1–I8, P1–P5, A1–A7, J1–J4, N1–N5, O1–O8, and cross-cutting lifecycle row to its requirement, Product × Adapter-mode × Host capability cells, reproducible positive and negative scenario, evidence, result, and approved deviation or honest fallback?

## Comments

### Resolution — 2026-07-18 (record complete; ticket remains open)

Published the versioned, normative [parity acceptance matrix and deviation
register](../assets/parity-acceptance-matrix-and-deviation-register.md), now
explicitly owned and linked by [SPEC.md](../SPEC.md#traceability-and-acceptance).
It records all 44 inventory IDs (S1–S6, I1–I8, P1–P5, A1–A7, J1–J4, N1–N5,
O1–O8, and H), an unambiguous Product × Adapter-mode × Host profile covering
Claude Code Hooks, Codex app-server, Codex observed Hooks, Cursor Hooks,
Cursor ACP, iTerm2, Cursor Host, Warp, and Orca, and per-row requirements,
decision/source evidence, reproducible positive/negative fixture, result, and
fallback/deviation link.

The record distinguishes `pass` for specification completeness from `blocked`
production and human-review evidence; it reports no invented implementation
result. Original identity/assets and no-timer cleanup are linked as explicitly
supported approved deviations. Capability-scoped unsupported action, lower
Host-navigation, and unavailable-usage differences remain proposed material
deviations, not N/A or passes. Therefore this ticket remains `open` with
`Resolution: unresolved` pending the exact human-owner decision stated in the
register; `MAP.md` was intentionally not edited.

### Continuation — 2026-07-18 (owner approval and completion)

The human owner explicitly approved DR-03 (capability-scoped native-Host
fallback for unsupported Agent Product actions), DR-04 (the documented lower
Host-navigation ladder), and DR-05 (usage unavailable rather than estimated)
for their stated cells. The normative register now records each as an
**approved deviation** and every affected matrix row consistently reports
`approved deviation / blocked`; `blocked` continues to mean uncollected
production/visual evidence, not a failure or an invented test result.

All 44 inventory IDs remain complete, no proposed material deviation remains,
and the ticket is closed as completed. `MAP.md` was intentionally not edited.
