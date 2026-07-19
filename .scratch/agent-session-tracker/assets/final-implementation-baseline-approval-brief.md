# Final implementation-baseline approval brief

**Prepared:** 2026-07-18  
**Human owner decision:** Approved on 2026-07-18 (“proceed”).

## Owner decision

The human owner approved `SPEC.md` and its normative parity acceptance matrix
and deviation register as the frozen Agent Island implementation baseline,
including DR-01 through DR-05 for their stated cells. The approval keeps
production implementation, release parity, human visual review, both required
feasibility spikes, and all required production evidence gated. It neither
claims release readiness nor broadens the frozen scope.

## Recommendation and evidence

The Wayfinder destination has been achieved at its intended planning boundary:
an implementation-ready, evidence-backed specification for a personal,
local-first, native macOS 14+ Apple Silicon Agent Island baseline, covering
Claude Code, Codex CLI, and Cursor with iTerm2, Cursor, Warp, and Orca.
Production implementation remains outside this completed planning map until
the required feasibility gates have passed.

The canonical implementation artifacts are:

- [Agent Island specification](../SPEC.md), the ready-for-agent baseline.
- [Normative parity acceptance matrix and deviation register](parity-acceptance-matrix-and-deviation-register.md), version 1.0.0, with all 44
  frozen inventory records, applicable capability profiles, positive/negative
  scenarios, fallbacks, and separate specification versus production result.
- [Passing parity traceability and requirements-completeness audit](parity-traceability-and-requirements-completeness-audit.md), with its
  [completed audit ticket](../issues/25-audit-parity-traceability-and-requirements-completeness.md).

The audit's re-audit passed **specification completeness**: all 44 rows are
traceable, no proposed material deviation remains, and the specification owns
the normative matrix. This is deliberately not a production, released-parity,
or visual-review pass.

## Frozen scope and architecture

The approved baseline is single-person, local-first macOS 14+ Apple Silicon
only. It excludes accounts, teams, cloud sync/hosted-service implementation,
telemetry/analytics implementation, commercial flows, remote/multi-Mac work,
other Agent Products/Hosts, other platforms, source branding/assets, and
production implementation itself. The complete boundaries remain in the
[Wayfinder map](../MAP.md) and [specification](../SPEC.md#out-of-scope).

The selected architecture is an AppKit-first Swift application with SwiftUI
hosted Island/Settings content, a deterministic replay-safe local core, typed
outer ports, a single-writer SQLCipher SQLite canonical store with a
per-installation Keychain key, optional constrained signed XPC helper/receiver,
and Developer ID signing/notarization. It preserves the local-canonical,
stable-identity, versioned-capability, immutable-fact, exact-configuration,
live-action-lease, live-locator, non-activating-Overlay, and AppKit-first ADR
boundaries.

Before any production implementation proceeds, two required feasibility spikes
must pass:

1. An AppKit `NSPanel` Overlay spike proving non-activation, visible-only hit
   and accessibility regions, selected-display/notch geometry, Spaces/fullscreen,
   keyboard engagement, Settings independence, and sleep/wake recovery.
2. A signed/notarized protected-store spike proving Keychain + SQLCipher
   create/migrate/reopen, atomic durability, missing-key/corrupt-ciphertext/
   migration failure handling, deterministic rebuild, and fail-closed recovery.

Those spikes must also establish the stack-specific memory/energy budget for
the representative 30-Agent-Session workload.

## Deviations being accepted

Approval accepts the following already-documented deviations only for their
stated matrix cells and fallbacks:

| ID | Accepted difference and user impact |
| --- | --- |
| DR-01 | Original Horizon hierarchy and Agent Island identity replace source branding/visual arrangement; monitoring and interaction jobs remain, with human visual review still required. |
| DR-02 | No time/idle cleanup removes or conceals an Agent Session; safe History transition and explicit scoped local deletion remain. |
| DR-03 | Unsupported Product actions remain in the native Host; Agent Island shows the unavailable reason and an honest Jump Back, and dispatches nothing from unsupported/stale routes. |
| DR-04 | Jump Back reports only the live achieved Host level, from exact surface/tab down to app-only or unavailable; it never guesses a target or simulates input. |
| DR-05 | Usage Snapshot appears only from a live sourced capability; unavailable/stale usage is shown honestly and never estimated or fabricated. |

The [register](parity-acceptance-matrix-and-deviation-register.md#stable-deviation-register)
records the evidence, affected cells, required fallback, and owner disposition
for each deviation.

## Evidence intentionally still blocked

Every parity row remains blocked for future production evidence. Before a
cell can be called a released parity pass, the implementation must collect its
real or faithful controllable Adapter evidence, applicable functional and
negative fixtures, timing/launch/scale/resource evidence, accessibility and
Overlay evidence, and the human functional/interaction/visual-quality review.
Automated evidence cannot certify the visual gate.

The audit recorded one non-material editorial item: a stale heading fragment
in the remediation asset's evidence link. It does not alter a requirement,
matrix row, deviation disposition, acceptance scenario, or the approval
decision.

## Consequence of approval

Approval freezes these artifacts as the implementation baseline and accepts
DR-01 through DR-05 for their stated cells. It authorizes downstream production
planning/implementation only after the two feasibility gates are completed;
it does **not** declare production parity, release readiness, visual approval,
or permission to widen scope or bypass any quality, safety, privacy, or
capability gate.

## When the map must reopen

Reopen or start a fresh Wayfinder effort before implementation proceeds if the
owner rejects any deviation, changes the frozen Parity Baseline/scope, adds an
Agent Product, Host, platform, remote/cloud/commercial capability, changes a
durable ADR boundary or selected stack/storage design, a required spike fails,
or production evidence reveals a material requirement, capability, safety,
visual, or acceptance gap. A new material deviation also requires a new
Wayfinder decision rather than silent implementation discretion.

## Exact approval question

**Do you approve `SPEC.md` and its normative parity acceptance matrix/deviation register as the frozen Agent Island implementation baseline, including DR-01 through DR-05 for their stated cells, while keeping production implementation, release parity, and human visual review gated by the two feasibility spikes and required production evidence?**
