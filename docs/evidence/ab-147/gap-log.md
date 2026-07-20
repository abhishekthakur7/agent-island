# AB-147 gap log and follow-up recommendations

All items are release blockers. They are deliberately not rewritten as Product
defects, not silently accepted, and not compensated for by feature changes.

| Gap | Blocking evidence absent | Honest current behavior | Follow-up recommendation / triage |
| --- | --- | --- | --- |
| G-01 native visual parity | Built-in and external rendered captures for collapsed Clean/Detailed, expanded rows/detail/footer, setup banner, Settings, History, Usage. | Do not claim visual parity from SwiftUI/test source. | Human capture packet using the form; `ready-for-human`. |
| G-02 AX/VoiceOver/keyboard/scroll | AX tree, VoiceOver announcements, keyboard traversal/escape, focus, list/detail scroll, settings scroll. | Unavailable fallback must remain text-visible; automation does not certify it. | Human assistive-technology run; `ready-for-human`. |
| G-03 display/adaptation | Built-in-notch and external-pill behavior under text size, Increase Contrast, Reduce Transparency, Reduce Motion, full screen/Spaces. | Selection unavailable withdraws local presentation according to model seam only. | Human visual/adaptation run; `ready-for-human`. |
| G-04 lifecycle recovery | Full-app cold/warm launch, restart, sleep/wake, display loss/reconnect, stale lease and Host locator outcomes. | Retire lease/locator; keep Product work unresolved rather than clean it up. | Redacted timestamped recovery capture; `ready-for-human`. |
| G-05 resources | Native energy/wakeups, disk growth, audio output release, retained task/timer lifetime. | AB-146 headless RSS/CPU/handles are not a native app claim. | Instruments/authorized sampler and protected-store capture; `ready-for-human`. |
| G-06 live profile provenance | Current Product/Adapter-mode/Host version and capability evidence for all listed profiles. | Fixture contract/version is labelled as such; missing live capability is unavailable. | Read-only version/capability capture per profile; `ready-for-human`. |
| G-07 action surface | Native, keyboard, and VoiceOver observation of confirmation, one-use lease, indeterminate/applied wording, and native fallback. | Native Claude Code is the fallback; no silent retry. | Human Claude Code action run with redacted correlation; `ready-for-human`. |
| G-08 navigation | Live iTerm2/Cursor/Warp/Orca activation and achieved-level/fallback observations. Current raw-App targeting was denied. | Report the lower level or unavailable; never infer target. | Use an approved human-operated capture path, not repeated raw targeting; `ready-for-human`. |
| G-09 integration health | Visible distinction among enabled intent, capability, degraded health, repair/manual remedy. | Never label an unproven integration Active. | Human Settings/Integrations capture across an available and unavailable profile; `ready-for-human`. |
| G-10 privacy/config review | Native diagnostic export and visual confirmation of exact-entry repair/cleanup boundaries. | No Interaction Content or broad external cleanup is claimed. | Redacted export and review of a safe drift/remedy case; `ready-for-human`. |

## Closure rule

Close a gap only with a redacted artifact linked from the human form and
diagnostic index, including date, hardware, macOS, Product/Host version,
Adapter mode/capability, positive/negative case, and outcome. If a capability
is unavailable, the completed artifact must show its honest fallback rather
than convert the cell to `N/A`.

Until every applicable gap is closed, AB-147 remains `ready-for-human` and
cannot be marked Done.
