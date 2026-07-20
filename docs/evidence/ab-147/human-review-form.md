# AB-147 human visual and accessibility review form

Automation must not self-certify this form. A person records one redacted
capture/correlation for every applicable cell on the frozen Vibe Island v1.0.42
baseline, macOS 14+ Apple Silicon comparison. Blank, failed, or unavailable
means **BLOCKED**, not pass and not `N/A`.

## Run identity

| Field | Record |
| --- | --- |
| Reviewer / date | |
| Mac model / Apple Silicon / macOS build | |
| Agent Island revision / launch method | |
| Baseline source/version/date | Vibe Island 1.0.42 / 2026-07-18 |
| Product / Adapter mode / Host profile and version | |
| Negotiated or observed capability / source | |
| Redacted diagnostic correlation ID and artifact path | |
| Screen recording/screenshot/AX export retention location | |

## Visual surfaces and concurrent work

Mark result as `pass`, `fail`, or `unavailable-with-fallback`; describe the
fallback and link the capture. `pass` requires a human observation, never only
a fixture/test result.

| Cell | Result / capture / notes |
| --- | --- |
| Built-in display: collapsed Clean island, protected notch gap, meaningful combined status/count | |
| Built-in display: collapsed Detailed island; no desktop blocking or Host activation | |
| External display: floating-pill adaptation; no hardware-notch implication | |
| Expanded panel: fixed usage/sound/Settings header, scrolling 30-row workload, selected detail and footer | |
| Session row/detail: status redundancy, metadata truncation, task/subagent/attention ordering, recap internal scroll | |
| Setup/compatibility banner and dismissal; no duplicate/disruptive surface | |
| Settings: sidebar, grouped controls, trailing alignment, Integration health and consequential controls separation | |
| History: 31st safely inactive archive and recap inspection; 31 active/attention/child rows do not archive | |
| Usage Snapshot: one sourced display and one unavailable display; no estimate/billing claim | |

## Accessibility and input

| Cell | Result / capture / notes |
| --- | --- |
| AX tree exposes only visible Overlay region; collapsed glyph animation is not noisy; combined status/count is announced | |
| VoiceOver reads attention state, action availability/outcome, health, Usage unavailable, and exact achieved Jump Back level/reason | |
| Keyboard: explicit Overlay engagement, session navigation, typed action confirmation/cancel, Escape collapse, and focus return | |
| Scroll: expanded list, selected recap/detail, Session History, and Settings content remain operable with keyboard/VoiceOver | |
| Larger text / content size preserves hierarchy, controls, truncation, and reading order | |
| Increase Contrast and Reduce Transparency preserve boundaries/status without excess decorative contrast | |
| Reduce Motion removes/reduces animation without suppressing status or attention meaning | |
| Quiet Scene/filter suppression remains understandable and deliberate inspection can reach state without replaying alert | |

## Product/Host and recovery outcomes

| Cell | Result / capture / notes |
| --- | --- |
| Claude Code action: live owner-bound action, stale/duplicate negative, indeterminate/applied wording, native fallback | |
| iTerm2: exact pane/tab success plus stale/revalidation failure and achieved-level announcement | |
| Cursor Host: exact navigation only when source-proven; duplicate/incompatible case does not choose lookalike | |
| Warp: permission denied/revoked and elected window cases; app-only/window-best-effort wording proves pane/tab unverified | |
| Orca: exact-tab at most; restart/duplicate and missing child surface lower/unavailable outcome | |
| Integration health: enabled intent separate from capability/Active/degraded/manual remedy | |
| Cold/warm app launch and full restart preserve no stale lease/locator or invented Product completion | |
| Sleep/wake and display disconnect/reconnect withdraw/recover only after revalidation; active work remains present/unresolved | |
| Extended idle: energy/wakeups, disk growth, no retained task/timer or audio output | |

## Reviewer decision

| Decision | Record |
| --- | --- |
| Structural verifier result | |
| Human visual/accessibility disposition | |
| Open gap IDs from `gap-log.md` | |
| Release readiness | `BLOCKED` until every applicable row has qualifying evidence |
| Reviewer signature/approval reference | |

This AB-147 form records parity review only. It does not authorize Product
actions, Integration Installation cleanup, diagnostic egress, or a feature
change.
