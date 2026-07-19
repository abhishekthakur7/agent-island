# Parity traceability and requirements-completeness audit

**Audit date:** 2026-07-18  
**Subject:** [Agent Island specification](../SPEC.md) against the frozen
[Parity Baseline inventory](parity-baseline-inventory.md),
[acceptance standard](parity-acceptance-standard.md), product defaults, closed
Wayfinder decisions, ADRs, and the original local research record.

## Verdict

**FAIL — the implementation baseline is not yet approval-ready.** The source
decisions provide broad and generally safe requirement coverage, but
`SPEC.md` does not own the required complete parity matrix or a deviation
register. It consequently cannot demonstrate every inventory item's
applicability, Product/Adapter-mode/Host capability cell, acceptance scenario,
evidence, and approval state. Several source controls are also reduced to
general Settings or keyboard statements rather than an unambiguous
requirement and test.

This audit does not revise `SPEC.md`, invent a deviation, or treat a supporting
asset as an implicit acceptance record.

## Pass criteria applied

The baseline passes only when all of the following are true:

1. Every in-scope inventory item (S1–S6, I1–I8, P1–P5, A1–A7, J1–J4,
   N1–N5, O1–O8, and cross-cutting H rows) has an explicit requirement,
   implementation decision, and reproducible acceptance scenario.
2. Each row identifies its applicable and unavailable Claude Code, Codex CLI,
   Cursor Hooks, Cursor ACP, iTerm2, Cursor Host, Warp, and Orca capability
   cells; an unavailable cell has evidence and an honest fallback.
3. Every material difference has a stable proposed/approved/rejected/
   superseded deviation record. A proposed record is not a pass.
4. Requirements preserve the closed identity, lifecycle, Action Lease, Host
   locator, local-first, Overlay, configuration-ownership, architecture,
   packaging, quality, feasibility-spike, and scope boundaries.
5. The testing decision names observable positive and negative evidence,
   including human visual review, rather than relying on private implementation
   assertions.

## Traceability and completeness matrix

`✓` means the assembled specification states a material requirement and test
direction. `△` means broad coverage exists but the row cannot be accepted yet;
`✗` means a requirement or acceptance definition is missing. Requirement and
test references are to the numbered sections of [SPEC.md](../SPEC.md).

| Baseline inputs | Requirement / implementation coverage | Testing coverage | Result | Audit finding |
| --- | --- | --- | --- | --- |
| S1–S6 session discovery, aggregation, activity, children, recap, health | US 1–16, 52, 57–63; ID 1, 4–9, 18 | TD 1, 2, 7, 12 | △ | Correct broad model; no inventory-by-Product/mode/Host applicability records. |
| I1–I8 Island hierarchy, rows, recap, task/child detail | US 17–23; ID 13–15 | TD 7, 9, 13 | △ | Visual system is specified, but no per-item acceptance record or visual-review disposition exists. |
| P1–P5 reveal, priority, collapse, hover, non-disruption | US 24–30; ID 14–16 | TD 7, 8, 10, 13 | △ | Behavior is covered; no matrix rows identify source event/capability applicability and evidence. |
| A1–A2, A4–A7 attention, context, drafts, plan, fallback, stale scope | US 31–43; ID 8–11 | TD 2, 3, 7, 9 | △ | Safe typed routing is well covered, pending explicit matrix/deviation records. |
| A3 choice controls | US 35, 77; ID 15; attention-workflow decision specifies numbered options, number keys, and valid-next gating | TD 3, 9 | ✗ | `SPEC.md` never requires visible choice keyboard mappings or tests valid-selection gating. “Complete keyboard operation” does not make the mapping discoverable or preserve the inventory's required negative case. |
| J1–J4 Host Context and Jump Back | US 44–51; ID 12; capability-aware iTerm2/Cursor/Warp/Orca rules | TD 4, 8 | △ | Host claims are conservative and match research, but the required cell-by-cell capability determination is absent. |
| N1–N4 event classes, sound, quiet scenes, filters, foreground, probes | US 24–27, 64–67; ID 16 | TD 7, 10 | △ | Rules and safety are strong; matrix records are still absent. |
| N5 usage-header configuration | US 68; ID 16 | TD 10 | ✗ | The spec allows display-only Usage Snapshots, but does not require the documented user controls for visibility, used-versus-remaining, preferred-provider/active-session following, and reset information, or their acceptance tests. |
| O1–O2 onboarding and Settings information architecture | US 69–71, 76–79; ID 17 | TD 7–9, 13 | △ | Atlas, previews, and accessibility are present, but individual control coverage is not traceable. |
| O3 General controls | US 24–30, 65, 72, 75; ID 14–17 | TD 7–10 | ✗ | Launch-at-login; no-active-session hiding; and explicit General control semantics for click-to-Jump-Back, fullscreen, and reveal/collapse are not stated as a complete requirement/test set. The source-derived idle-cleanup behavior is safely superseded by the no-timer rule, but needs a documented material-improvement/deviation record. |
| O4 integration controls | US 52–63; ID 7–9, 18 | TD 2, 5 | △ | Intent/health, setup, repair, and compatibility are covered; custom Jump Back rules are only implicit in Host capability material and lack a clear applicable/inapplicable declaration. |
| O5 Display controls | US 17–22, 71, 73–75; ID 13–15 | TD 7–9, 13 | ✗ | Requirement/test coverage does not explicitly bind clean/detailed selection, content size, panel width/height, completion-card-height control, or optional metadata visibility. Supporting design defaults do not replace a SPEC requirement. |
| O6–O8 shortcuts, diagnostics, ownership, reconciliation/uninstall | US 52–58, 72, 77, 84–85, 88; ID 15, 18–21 | TD 2–6, 9 | △ | Safety coverage is strong; individual acceptance rows and diagnostics' inventory evidence links are absent. |
| H lifecycle, identity, recovery, cleanup, action, overlay, accessibility, scale | US 4, 6–16, 27–30, 40–51, 73–85, 88; ID 1–24 | TD 1–14 | ✓ | The immutable-fact, conservative-recovery, ownership, privacy, quality, packaging, and two-spike boundaries are explicit and tested at decision level. Final parity evidence remains blocked by the missing matrix. |
| Changelog-derived invariants (duplicate/reorder, rewind, lost/stuck attention, focus/hover, sleep/wake, configuration drift, CJK, sound release, unknown versions) | ID 4–21 and US 7–8, 27–29, 36–43, 52–67, 72, 80–85, 88 | TD 1–12, 14 | ✓ | All recurring safety lessons have a requirement and negative-test direction; no contradiction with ADRs found. |
| Scope, future seams, architecture/contracts/packaging and feasibility gates | US 1–3, 86–87; ID 1–3, 7–9, 21–24; Out of Scope | TD 2, 5–6, 11–14 | ✓ | First-class scope, local-only posture, extension seams, signed AppKit-first architecture, and mandatory Overlay/store spikes are explicit and do not authorize excluded services or implementation. |

## Findings

### Critical

1. **No complete parity matrix or deviation register in the implementation
   baseline.** The [acceptance standard](parity-acceptance-standard.md#1-what-is-being-accepted)
   requires the implementation-ready specification to own a record for every
   applicable inventory item, including capability cells, scenario, evidence,
   result, and deviation link. `SPEC.md` instead says a future implementation
   “must have” such a matrix. It provides neither the required records nor a
   deviation register. This prevents acceptance of unsupported/limited cells
   and hides the omissions below.

### High

2. **A3's visible number-key mappings and valid-selection gate are not
   normative in `SPEC.md`.** They appear only in the supporting attention
   workflow. Add an explicit requirement and positive/negative acceptance
   scenario for visible mappings (outside text entry), no default selection,
   reversible single/multi selection, and disabled Next until valid.

3. **N5 usage controls are under-specified.** Capability-gated display alone
   does not require visibility, used/remaining, preferred/follow behavior, or
   reset information. Define these controls or record each omission as an
   approved capability/evidence deviation.

4. **O3/O5 Settings controls are incompletely expressed.** General and Display
   are named, but the source inventory's control outcomes are not a complete,
   testable baseline in `SPEC.md`. Explicitly distinguish safe improvement
   (no timer cleanup) from omitted behavior and specify the remaining
   applicable controls.

### Medium / editorial

5. **Repeated phrase in implementation decision 15.** “redraw,
   screen/display changes, and ordinary expand/inspect clicks retain” appears
   twice. It does not alter the requirement's meaning.

## Checks that passed

- Local Markdown links resolve: 65 Markdown files were checked, including the
  map, closed-ticket resolutions, assets, specification, glossary, ADRs, and
  original research record.
- Terminology is consistent with `CONTEXT.md`; no unsafe Agent Product/Host
  conflation, lifecycle claim, privacy expansion, or scope leak was found.
- The specification preserves each ADR's durable boundary and does not replace
  the mandatory feasibility spikes with unsupported feasibility claims.
- No broken numbered sections were found; the one duplicated phrase above is
  non-material.

## Required follow-up tickets (proposed; not created by this audit)

1. **Complete parity acceptance matrix and deviation register**

   **Question:** “What complete, versioned parity record maps every applicable
   S1–S6, I1–I8, P1–P5, A1–A7, J1–J4, N1–N5, O1–O8, and cross-cutting
   lifecycle row to its requirement, Product × Adapter-mode × Host capability
   cells, reproducible positive/negative scenario, evidence, result, and
   approved deviation or honest fallback?”

   **Proposed dependency edges:** blocked by **Close explicit attention, usage,
   and Settings parity requirement gaps**; blocks **Audit parity traceability
   and requirements completeness** (re-audit/closure). The existing Audit →
   **Approve the implementation baseline and exceptions** edge then remains
   the approval gate.

2. **Close explicit attention, usage, and Settings parity requirement gaps**

   **Question:** “Which explicit requirements, implementation decisions, and
   acceptance scenarios must add A3's visible keyboard mappings/valid-answer
   gate, N5's capability-gated usage controls, and O3/O5's applicable General
   and Display controls, and which source behaviors are approved safe
   deviations rather than omissions?”

   **Proposed dependency edges:** blocked by the closed **Assemble the
   implementation-ready product and architecture specification** ticket;
   blocks **Complete parity acceptance matrix and deviation register**. The
   resulting path is Close gaps → Complete matrix → Audit re-audit → **Approve
   the implementation baseline and exceptions**.

## Required map entry after a passing re-audit

Do not add this while the ticket remains open. When a later re-audit passes,
the exact one-line `Decisions so far` entry is:

```markdown
- [Audit parity traceability and requirements completeness](issues/25-audit-parity-traceability-and-requirements-completeness.md) — Verified explicit inventory-by-capability acceptance records, approved deviations, and complete requirements coverage for the frozen baseline.
```

## Re-audit — 2026-07-18

**PASS — specification completeness is now sufficient for the final human
approval workflow.** This is not a production or released-parity verdict:
every matrix row remains `blocked` for implementation evidence and the visual
review required by the acceptance standard.

### Evidence rechecked

- `SPEC.md` now explicitly owns the versioned normative
  [parity acceptance matrix and deviation register](parity-acceptance-matrix-and-deviation-register.md).
- The matrix contains exactly 44 inventory rows in canonical order: S1–S6,
  I1–I8, P1–P5, A1–A7, J1–J4, N1–N5, O1–O8, and H. Every row has normative
  requirement references, decision/source evidence, a profile-based
  capability determination, a reproducible positive/negative scenario, a
  fallback/deviation pointer, and separate specification/production result.
- The Product × Adapter-mode × Host profile explicitly covers all C, D, and K
  cells for iTerm2, Cursor Host, Warp, and Orca; the valid R-C and A-C Cursor
  cells; the remaining Cursor combinations as N/A; and the independent H
  navigation ladder. Unknown, lost, or unsupported capability remains a
  narrowed applicable cell with the stated fallback.
- `SPEC.md` now makes A3's keyboard mapping and validation, N5's
  capability-gated usage controls, O3's General controls, O4's documented
  inapplicability, and O5's Display controls and their positive/negative
  acceptance tests explicit.
- DR-03, DR-04, and DR-05 are recorded as human-owner-approved deviations for
  their stated cells; the register has no proposed material deviation. DR-01
  and DR-02 continue to preserve the original-identity and no-timer-cleanup
  boundaries. Scope exclusions, ADR boundaries, local-first privacy,
  contracts, quality gates, packaging posture, and mandatory feasibility
  spikes remain intact.

### Non-material observation

The active local-file target of every checked link resolves. One local heading
fragment is stale in
[attention, usage, and Settings parity remediation](attention-usage-settings-parity-remediation.md):
`persistence-history-recovery-and-retention.md#retention-archive-and-deletion`
does not match the target's current `#history-archive-and-cleanup` heading.
It is a non-normative evidence-link defect only; it does not change a
requirement, matrix row, deviation disposition, or acceptance scenario. It is
recorded here rather than silently corrected during the independent audit.
