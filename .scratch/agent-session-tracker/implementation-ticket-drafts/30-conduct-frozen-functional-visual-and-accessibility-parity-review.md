# 30 — Conduct the frozen functional, visual, and accessibility parity review

**Status:** ready-for-agent

## What to build

Assemble the completed implementation’s evidence into the frozen parity acceptance matrix and conduct the required human functional, visual-quality, and accessibility review. This ticket does not add product features, widen scope, or use review findings as a catch-all implementation backlog; it produces an explicit pass, blocked, or gap record for each applicable matrix cell and approved deviation.

## Context and constraints

The frozen baseline is Vibe Island v1.0.42 observed on 2026-07-18, for macOS 14+ Apple Silicon and the defined Claude Code, Codex CLI, Cursor, iTerm2, Cursor Host, Warp, and Orca profiles. The parity matrix is the canonical acceptance seam: all applicable records require real or faithful controllable Adapter evidence, a positive and negative scenario, capture/diagnostic correlation, and current Product/Adapter/Host/capability versions. An unavailable negotiated capability is applicable and must show its honest fallback; it is not silently N/A.

DR-01 through DR-05 remain limited to their approved cells: original Horizon identity; no time/idle cleanup; native-Host fallback for unsupported Product actions; achieved-level Host navigation; and sourced-or-unavailable Usage Snapshots. Automation can collect functional evidence but cannot self-certify the human visual review. A gap remains blocked and must be routed to a separately scoped follow-up ticket rather than fixed here.

## Acceptance criteria

- [ ] Every applicable S, I, P, A, J, N, O, and H matrix record has a traceable Product/Adapter-mode/Host profile, version/capability evidence, positive and negative fixture result, expected fallback/deviation disposition, capture, redacted diagnostic correlation, and current review status.
- [ ] Each unavailable/degraded cell demonstrates its named capability-honest fallback; no result is relabelled N/A merely because implementation evidence is missing or a capability has narrowed.
- [ ] The review confirms the release-blocking failure invariants: no invented Product truth, ownership crossing, stale/duplicate control, unsafe navigation claim, active-work loss, duplicate/disruptive presentation, privacy/configuration overreach, dishonest health, or inaccessible fallback.
- [ ] Functional review exercises the completed concurrent-monitoring, attention, action, recovery, integration-health, History, Usage Snapshot, and Jump Back outcomes against their approved capability profiles.
- [ ] Human visual review covers resting and active collapsed Island, expanded multi-session list, focused completion, Attention Request, integration health/setup, Settings, built-in-notch and external-display forms, and accessibility adaptations; it evaluates hierarchy, density, readability, original identity, non-disruptiveness, and motion rather than image-diff similarity.
- [ ] Accessibility review covers keyboard-only operation, VoiceOver, Reduce Motion, Reduce Transparency, Increase Contrast, increased text, non-QWERTY binding, and CJK/IME behavior across visible Island and Settings content.
- [ ] Review evidence confirms DR-01 original identity with no source assets, DR-02 no automatic active-work cleanup, DR-03 zero-dispatch native fallback for unsupported actions, DR-04 achieved-level navigation without simulated input, and DR-05 sourced-or-unavailable usage with no estimate.
- [ ] Any non-passing result remains explicitly blocked with reproducible evidence and a narrowly scoped follow-up recommendation; this ticket makes no feature change and does not declare released parity or owner approval without the required human decision.

## Required evidence

- [ ] Completed parity matrix records and a review index link every capture, fixture, environment/version record, timing/resource result, and redacted diagnostic evidence to the applicable cell.
- [ ] Human-review notes and captures document the functional, visual, motion, original-identity, and accessibility assessment for each required surface/form.
- [ ] An approved-deviation checklist records the affected cells, observed fallback, and required proof for DR-01 through DR-05.
- [ ] A final gap log distinguishes passed, blocked, unavailable-with-honest-fallback, and follow-up-needed results without reclassifying blocked production evidence as specification pass.

## Blocked by

- #15 — Apply General and Display settings safely
- #16 — Support safe shortcuts, keyboard operation, and adaptive accessibility
- #17 — Observe Claude Code sessions through a managed Integration Installation
- #18 — Route supported Claude Code attention actions
- #19 — Observe independently launched Codex CLI sessions
- #20 — Monitor and control direct Codex app-server sessions
- #21 — Observe Cursor IDE Agent Sessions through Hooks
- #22 — Start and control Cursor ACP sessions
- #23 — Jump Back to live iTerm2 contexts
- #24 — Jump Back to Cursor Host contexts
- #25 — Jump Back to Warp Host contexts
- #26 — Jump Back to Orca Host contexts
- #27 — Display sourced Usage Snapshots
- #28 — Recover safely across restart, wake, disconnect, and termination
- #29 — Prove 30-session responsiveness and resource stability
