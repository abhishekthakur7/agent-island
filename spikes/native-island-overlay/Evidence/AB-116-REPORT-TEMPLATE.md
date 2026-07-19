# AB-116 — Native Island Overlay spike evidence report

**Status:** `OWNER ACCEPTED WITH WAIVERS`  
**Decision:** `GO FOR IMPLEMENTATION`  
**Capture owner/date:** `[name / UTC date]`  
**Spike revision and executable SHA-256:** `[value]`  
**Evidence bundle:** `[relative or local path]`

This is a reporting template. Delete no failed or unavailable rows. A blank,
`NOT RUN`, or `UNAVAILABLE` field is not a pass. “Automated” below means it
can collect a trace or detect a condition; it does not certify platform
behavior that requires human observation.

## Owner decision — 2026-07-19

The owner approved this disposable spike and authorized production
implementation to proceed. Full-Xcode-only XCTest execution is not required
for this personal-use local application. All `NOT RUN` rows below remain
unverified risks and are not converted into passes by this decision.

## Conditions and reproducibility

| Field | Recorded value |
| --- | --- |
| macOS / build / Swift / Xcode | `[from environment.txt]` |
| Apple-Silicon model, RAM, power state | `[from hardware.txt / environment.txt]` |
| Built-in display: scale, safe area/notch form | `[value]` |
| External display: model, connection, scale, arrangement | `[value or N/A with reason]` |
| Host application and focus target used for each run | `[value]` |
| Full-screen / Space condition; `hideInFullscreen` value | `[value]` |
| Accessibility settings: VoiceOver, Reduce Motion/Transparency, Increase Contrast, text size, keyboard layout/IME | `[value]` |
| Fixture and command line; instrumentation schema/version | `[30-Agent-Session fixture; schemaVersion 1 or later]` |
| Raw artifacts retained | `environment.txt, hardware.txt, *.jsonl, stdout/stderr, captures, trace, manual notes` |

Attach command output from `capture-environment.sh`, `build.sh`, and `test.sh`.
For each scenario retain a short screen recording or timestamped screenshots
when permissible, and state where it is stored. Never put Interaction Content
in a shared evidence bundle.

## Proposed measurement guardrails

The first three targets are the established quality requirements; the resource
figures are **proposed spike guardrails only**, pending measured supported-
hardware evidence. They are not invented release budgets and must be revised
or accepted explicitly before production acceptance.

| Metric / boundary | Proposed comparison | Source / method | Result |
| --- | --- | --- | --- |
| Cold usable launch | p95 `< 2,000 ms` | App `launch_usable.elapsedMs`, 10 no-process runs | `NOT RUN` |
| Warm usable launch | p95 `< 1,000 ms` | Same, after a prior usable run with retained local state | `NOT RUN` |
| Local event → first rendered and accessible presentation | every standard sample `< 250 ms` | Same-clock intake/rendered instrumentation | `NOT RUN` |
| Explicit local interaction → first AppKit presentation result | p95 `≤ 250 ms` (spike guardrail) | `interaction_requested` → `interaction_rendered` JSONL | `NOT RUN` |
| Idle CPU, 10-minute no-event hold | median `≤ 1.0%`, p95 `≤ 2.0%` | `profile-resources.sh` 5-second series | `NOT RUN` |
| Loaded CPU, interaction/display cycle | p95 `≤ 10.0%` | Same resource series; describe workload | `NOT RUN` |
| RSS stability after 10 equivalent cycles | growth `≤ 10 MiB`; no monotonic retained growth | RSS series plus `vmmap` before/after | `NOT RUN` |
| Wakeups | median `≤ 20/s`, p95 `≤ 50/s` | Instruments Energy Log or root-only `powermetrics` | `UNAVAILABLE until captured` |
| Energy | no sustained elevated Energy Impact at idle; attach raw trace | Instruments Energy Log; human review | `UNAVAILABLE until captured` |
| Residual app processes after quit | exactly `0` | `residual-processes.sh` output | `NOT RUN` |

Record sample count, min/median/p95/max, exclusions, and the reason for every
excluded sample. A process runtime, a screen capture, or a test pass cannot be
substituted for an app-boundary latency measurement.

## Acceptance matrix

| ID | Required observation and capture | Automated evidence | Human evidence (required) | Result / artifact |
| --- | --- | --- | --- | --- |
| OW-1 | With an editor or terminal key, trigger automatic new-session and completion reveal. Capture pre/post key application/window and visible Overlay. | JSONL state/reveal timestamps and `applicationIsActive` diagnostic flag; optional launch/process trace. Cannot prove Host focus. | Verify typing remains in the Host; no Agent Island activation; repeat both reveal causes. | `NOT RUN` |
| OW-3 | Rapidly enter/exit the selected display’s top edge, visible island, and adjacent non-island top edge. Capture video with pointer indicator. | Transition log may show debounce/coalescing only. | Verify only visible bounds react; no edge-wide trigger, flicker, loop, or hidden expansion. | `NOT RUN` |
| OW-4 | Collapse while pointer-hovered, keyboard-engaged, VoiceOver-focused, and mid-transition. Capture each state before/after Escape/collapse. | JSONL `keyboard_*` / state transitions if available. | Verify visible, hit, and AX regions contract together; no stranded focus or Host activation. | `NOT RUN` |
| OW-8 | On built-in display at each available scale/safe-area configuration, inspect island geometry around the notch. | Screenshot dimensions can document geometry only. | Verify no content, text, badge, or action target crosses the protected center; no clipped wings. | `NOT RUN` |
| OW-9 | Select an external display; change arrangement/scale; disconnect/reconnect it. Capture selected-display status and process state. | Transition log and `residual-processes.sh` may detect duplicate process only, not duplicate panels. | Verify one Overlay only; disconnect withdraws rather than migrates; reconnect starts collapsed without stale reveal/focus. | `NOT RUN` |
| OW-10 | Repeat Space/full-screen transition with `hideInFullscreen` enabled, then disabled. Capture each configured result. | State log may show withdrawn/collapsed. | Verify no automatic Space crossing or Host activation; no residual hidden hit/AX region; report result without a Space claim. | `NOT RUN` |
| OW-12 | Repeat at least five sleep/wake cycles and restart while visible and while an Attention Request is pending. Capture state after every wake. | Crash/test logs, process/resource series, instrumentation transitions. | Verify cold-resume collapse, no replayed input/focus/reveal/action, conservative unavailable state where appropriate, and no crash. | `NOT RUN` |
| OW-13 | Open/close Settings from each display while Overlay is visible/unavailable and after selected display loss. | Process capture only; no automatic proof of level or frame. | Verify one normal-level independently activating Settings window, on screen; Overlay never becomes parent/key by side effect. | `NOT RUN` |
| OW-14 | Quit from collapsed, expanded, keyboard-engaged, and pending-attention/draft states. Run residual check after each. | `residual-processes.sh`; open-file/process snapshots before quit. | Verify no dispatch of pending action, no ghost shortcut/hit region, and durable request is still present through native fallback on next run. | `NOT RUN` |
| OW-15 | Run keyboard-only traversal and VoiceOver on built-in and external forms; repeat with Reduce Motion, Reduce Transparency, Increase Contrast, increased text, non-QWERTY layout, and CJK IME if available. Capture AX inspector/tree where permitted. | Instrumentation can show state, not labels, focus order, spoken output, or IME correctness. | Verify labelled visible-only focus stops, meaningful grouped status and rows, once-only attention announcement, visible focus, no color-only state/clipping, and full operation without hover. | `NOT RUN` |

## Keyboard and VoiceOver transcript / checklist

For every checked item, write the observed label/value and any deviation.

- [ ] Configured keyboard engagement visibly establishes the first focus target; Tab and Shift-Tab traverse only rendered controls.
- [ ] Escape cancels a standard local edit when relevant, otherwise collapses and ends keyboard engagement without reactivating a Host changed in the meantime.
- [ ] Collapsed Island exposes one concise status group; protected notch/breathing space is not a focus stop.
- [ ] Expanded/focused rows announce state, Project/task/title, Agent Product, Host, relative time, and attention/selection state without decorative chatter.
- [ ] Disabled/unavailable actions remain discoverable with an honest reason; Jump Back speaks/labels achieved level and reason.
- [ ] A higher-priority Attention Request is announced once without stealing VoiceOver focus or a draft.
- [ ] Reduced motion, transparency, contrast, text-size, layout, and IME variants remain operable and unclipped on both display forms.

## Go / no-go checklist

- [ ] Build and automated test logs are attached and successful, or failures are documented.
- [ ] Environment/hardware/power/display conditions and executable hash are attached.
- [ ] All applicable OW rows above have raw capture plus human observation; `UNAVAILABLE` items are not marked pass.
- [ ] Host focus, visible-only hit/AX regions, keyboard release, VoiceOver, selected-display withdrawal, full-screen/Space behavior, cold wake recovery, and termination have human evidence.
- [ ] Instrumentation boundaries/schema and raw logs support every claimed timing figure; `interaction_rendered` is first AppKit presentation, not a substitute for VoiceOver accessibility proof.
- [ ] CPU/RSS/open-file series, energy/wakeup trace (or an explicit unavailable reason), and before/after residual-process reports are attached.
- [ ] No crash, leaked process, ghost input region, focus theft, duplicate Overlay, stale replay, or accessibility failure was observed.
- [ ] Any failure has a reproduction command, artifact, impact, and owner; decision is `NO-GO` until resolved or scope is explicitly changed.

**Final rationale:** `[write evidence-backed rationale here; do not state a pass based solely on automated capture.]`
