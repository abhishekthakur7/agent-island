# 29 — Prove 30-session responsiveness and resource stability

**Status:** ready-for-agent

## What to build

Create and run the representative 30-Agent-Session workload and its measurement harness so the completed product can demonstrate responsive, legible, accessible, and resource-stable operation under ordinary concurrency, recovery, and overflow conditions. Establish the stack-specific resource budget from measured supported-hardware results; do not silently turn a measurement shortfall into a product behavior change.

## Context and constraints

The working-set limit is presentation only. A safely inactive thirty-first Agent Session moves losslessly to Session History; when every retained session is active, unresolved, attention-requiring, or child-active, the working set must exceed 30. No idle timer, resource pressure, filter, collapse, or measurement fixture may delete, conceal, or terminally reclassify active work.

The accepted timing targets are local event-to-first correct visual/accessibility state below 250 ms, confirmed local action-to-one Adapter handoff below 150 ms, warm usable launch below one second, and cold usable launch below two seconds on supported Apple Silicon. An upstream Product delay does not excuse a local timing miss. Before this ticket, numeric memory/energy limits are deliberately unset; this ticket measures and records the native-stack resource budget rather than inventing one.

## Acceptance criteria

- [ ] A reproducible workload instantiates 30 independently owned Agent Sessions across applicable Product/Adapter/Host profiles with active, waiting, completed, unresolved, child, attention, selection, recap, history, scroll, and ordinary-event states represented.
- [ ] The workload includes duplicate, delayed, reordered, gap, reconnect, rewind, compaction, concurrent-attention, restart, and wake traces without losing owner boundaries, current state, requests, or historical evidence.
- [ ] A thirty-first safely inactive session moves to Session History with facts and recap inspectable; an all-active/all-attention/child-active set visibly exceeds 30 and evicts nothing.
- [ ] Standard-condition local event-to-correct visual and accessibility presentation is under 250 ms for every valid sample; confirmed action-to-one Adapter handoff is under 150 ms without claiming Product application.
- [ ] Warm usable launch is under one second and cold usable launch is under two seconds while still integrity-checking state, disabling stale Action Leases, invalidating live locators, and providing a usable Overlay or explicit selected-display-unavailable state.
- [ ] The workload remains keyboard-operable, VoiceOver-operable, scroll-stable, and legible through selection, bounded recap, nested children, compact Horizon rows, and History transitions.
- [ ] Idle and loaded CPU, memory, wakeups/energy, disk, open handles, tasks/timers, and audio-resource lifetime are recorded across workload, extended idle, display changes, and repeated sleep/wake; equivalent repetitions show no retained growth, busy polling, leaked handle, leaked sound/output, or background-presentation loop.
- [ ] Measured supported-hardware results establish and record the native-stack numeric resource budget. Any over-target valid timing sample, resource-instability failure, or unmet safe-overflow behavior remains a release-blocking result, not an automatic deviation.

## Required evidence

- [ ] Versioned workload fixture, environment record, input trace, timing boundaries, diagnostic correlation, and visual/accessibility capture for each applicable measured cell.
- [ ] Separate 31st-archive and all-active overflow captures prove the no-active-work-loss invariant.
- [ ] Cold/warm launch, repeated restart/wake, extended-idle, display-change, and sound-release resource series include the resulting proposed native-stack budget and reviewable methodology.
- [ ] Failure report format identifies whether a miss is an application sample or reproducible measurement fault; it never masks a valid over-target sample as pass.

## Blocked by

- #12 — Move inactive work into inspectable Session History
- #27 — Display sourced Usage Snapshots
- #28 — Recover safely across restart, wake, disconnect, and termination
