# AB-123 — Atlas Settings implementation verification

Copy this file for each capture session. Fill in the environment fields and
every row; a visual or accessibility claim is not complete until it has a
human-observed result. Do not include Interaction Content, credentials, raw
Product identifiers, paths, commands, or locators in a report.

## Scope and boundary

Atlas is a conventional, independently activating macOS Settings window. It
has a persistent sidebar and one independently scrolling detail pane. The
sidebar contains ten grouped destinations:

| Group | Destinations |
| --- | --- |
| Preferences | General, Integrations, Notifications, Display, Sound, Usage |
| Advanced | Shortcuts, Labs, Diagnostics, Maintenance |

Onboarding is contextual and resumable in General. Settings preferences and
onboarding progress are local state. They do not become Agent Product state,
Integration Installation configuration, Overlay state, or network data.

## Environment

- macOS version:
- Hardware/display arrangement:
- Xcode version (full Xcode is required for XCTest rows):
- Date/time:
- Operator:
- Capture/log locations:

## Build and test commands

Run from `src/` and attach the output or record the result below.

```sh
swift build
swift test
swift run AgentIslandApp
```

`swift build` is expected to work in this Command Line Tools-only checkout.
`swift test` and `swift build --build-tests` are expected to stop during
module resolution with `unable to resolve module dependency: 'XCTest'` when
full Xcode is not installed; this is an environment limitation, not a test
result. Run the XCTest rows on a full-Xcode macOS machine.

| Command | Result | Evidence/log |
| --- | --- | --- |
| `swift build` | | |
| `swift test` (full Xcode) | | |
| `swift run AgentIslandApp` | | |

## Settings shell and lifecycle

| Scenario | Expected evidence | Observed result | Pass/Fail |
| --- | --- | --- | --- |
| Initial open | One normal, titled Settings `NSWindow`; persistent sidebar; one detail pane that scrolls independently of the sidebar | | |
| App inactive | Explicit Settings/menu action activates Settings without activating a Host or changing Product state | | |
| Overlay visible | Settings opens independently while the Overlay remains the one selected-display surface; no child/attached-sheet relationship and no Overlay movement | | |
| Overlay unavailable | Menu can still open Settings when the selected display is unavailable or the Overlay is withdrawn | | |
| Already open | Repeated Settings actions reuse the existing window and state; no duplicate windows, observers, or panes | | |
| Close/reopen | Closing Settings closes only that window; reopening restores its frame, selected destination, and durable local preference values | | |
| Terminate/relaunch | After a clean quit and relaunch, the saved frame, local preferences/onboarding state, and selected destination restore; no stale window, Overlay, Host focus, Action Lease, or Product action is revived | | |
| Detail scrolling | Long content scrolls within the detail pane while the sidebar remains fixed; no horizontal overflow at the normal size | | |

## Destination walkthrough

Visit every destination with keyboard and pointer input. Record the visible
state, any local preference change, and whether the destination correctly
defers later integration or maintenance work.

| Destination | Required review | Observed result | Pass/Fail |
| --- | --- | --- | --- |
| General | Launch/overlay/hover and pointer-exit behavior, foreground suppression, fullscreen/no-active-session hiding, completion/attention reveal, and clearly labelled inspect/expand versus Jump Back behavior | | |
| Integrations | Discovery, enabled intent, setup/repair placeholder, capability evidence, observed health, evidence time, affected capability, and safe next step remain separate | | |
| Notifications | The local completion/attention filter preview updates without emitting a notification; later delivery policy is not claimed | | |
| Display | The local Island preview responds without moving or recreating the live Overlay; later detailed display controls are not claimed | | |
| Sound | A distinct local-policy destination is present and clearly defers audible routing/preview behavior to a later slice | | |
| Usage | A distinct display-only Usage Snapshot destination is present and explicitly refuses to estimate unavailable usage | | |
| Shortcuts | A distinct advanced destination is present and explicitly defers collision/input-source-safe binding mechanics | | |
| Labs | A distinct advanced/experimental destination is present; unsupported behavior is not implied by a toggle | | |
| Diagnostics | Allowlisted accepted/filtered/degraded evidence is explainable locally; future bundle export is disabled and the presentation is redacted by construction | | |
| Maintenance | Preference reset, setup removal, selected local-data deletion, and complete cleanup are distinct, visibly consequential, and inert until a later scoped plan/confirmation exists | | |

## Onboarding state matrix

Exercise onboarding from a clean local preference state, then repeat after
relaunch. It is contextual education in General, not a permanent replacement
for normal Settings navigation.

| State/path | Expected result | Observed result | Pass/Fail |
| --- | --- | --- | --- |
| First run | Explains aggregation, Host fallback, setup/health, and display concepts; progress is visible in General | | |
| Partial progress | Leaving after any completed step retains the completed steps and next step without falsely claiming completion | | |
| Skip | Skip is explicit; progress treatment is removed or marked skipped while all ten destinations remain available | | |
| Resume | Re-entering onboarding resumes at the next incomplete step and does not repeat completed education; relevant detail destinations remain reachable | | |
| Completion | Completion removes onboarding progress treatment but preserves ordinary Settings, diagnostics, and maintenance access | | |
| Relaunch | The same onboarding state is restored locally after terminate/relaunch; no Product or Integration Installation is changed | | |

## Intent versus observed health

Use three distinct fixture rows and inspect both visual labels and the
underlying state model:

| Example | Expected distinction | Observed result | Pass/Fail |
| --- | --- | --- | --- |
| Claude Code | Enabled intent + Healthy observed delivery/capability evidence | | |
| Codex CLI | Enabled intent + Degraded health, with reason, observation time, affected capability, and safe next step | | |
| Cursor | Detected but disabled intent; it must not appear Healthy merely because discovery found it | | |

Detection and an enabled switch must never configure an Integration
Installation or be used as a health claim. State-model review must show that
intent and health are independent fields/dimensions.

## Read-only preview zero-side-effect trace

Exercise Display and notification/filter previews, including changing their
inputs and leaving/reopening Settings. Inspect instrumentation and local
state before and after each interaction.

| Side effect to exclude | Expected observation | Result | Pass/Fail |
| --- | --- | --- | --- |
| Alert/notification | No macOS alert, attention reveal, glow, or notification is emitted | | |
| Sound | No event sound or sound-policy change is produced | | |
| Overlay frame/identity | Live Overlay frame, selected display, geometry, and identity remain unchanged | | |
| Overlay recreation | No second Overlay, panel, hit region, or accessibility surface is created | | |
| Configuration | No Integration Installation, hook, manifest, Product configuration, or file is written | | |
| Agent Product | No Product action, prompt, permission, conversation, or lifecycle state changes | | |
| Navigation | No Host activation, Jump Back, Space/display move, or implicit Settings destination change occurs | | |
| Persistence | Preview-only input is local/read-only and is not committed to durable preferences, ledger, diagnostics, or history | | |

## Diagnostics redaction

Inspect the allowlisted diagnostic presentation for a degraded and a
rejected/filtered case. Bundle creation remains disabled in this slice.

- [ ] Contains only redacted operational evidence and stable diagnostic codes.
- [ ] Omits Interaction Content: prompts, responses, commands, code, diffs,
      project/file references, and response text.
- [ ] Omits credentials, tokens, raw identifiers, titles, paths, and Host
      locators.
- [ ] Does not offer or perform network egress, export, or upload.
- [ ] Explains the affected capability, evidence time, and safe next step
      without claiming an unverified Product result.

Observed result / artifact:

## Keyboard, VoiceOver, and adaptive layout review

| Adaptation | Expected evidence | Observed result | Pass/Fail |
| --- | --- | --- | --- |
| Keyboard-only | Sidebar, detail controls, previews, onboarding, and safe fallbacks are reachable in visible order; focus is visible | | |
| VoiceOver | Destinations, grouped controls, status/reason/next step, preview read-only state, and Maintenance scope are announced meaningfully; no decorative glyph is required | | |
| Increased text | Labels and explanations remain readable; controls retain meaning and no horizontal overflow appears | | |
| Reduce Motion | Transitions use a restrained/non-animated equivalent without losing state or focus | | |
| Reduce Transparency | Material contrast and grouping remain legible | | |
| Increase Contrast | Borders, focus, semantic state, and disabled/inert actions remain distinguishable without color alone | | |
| Compact window | Sidebar/detail remain usable, detail scrolls vertically, and no horizontal overflow or clipped action occurs | | |

## State-model and boundary review

- [ ] Settings window lifecycle is separate from Overlay lifecycle and display
      ownership.
- [ ] Durable preference/onboarding state is separate from protected Agent
      Session evidence and from live/volatile authority.
- [ ] Onboarding progress, selected destination, and preview state cannot
      manufacture Product or integration facts.
- [ ] Integration enabled intent cannot derive Healthy/Degraded/Unavailable/
      Incompatible health without observed evidence.
- [ ] Maintenance actions have distinct scopes and are inert without an
      explicit later plan and confirmation.
- [ ] No Settings presentation path dispatches Product actions, navigates a
      Host, writes integration configuration, or creates network egress.

Review notes / source or test references:

## Disposition

- [ ] Build passes; XCTest results are attached or the CLT XCTest limitation is
      recorded above.
- [ ] All ten destinations and shell lifecycle rows pass.
- [ ] Onboarding first-run, partial, skip, resume, completion, and relaunch
      rows pass.
- [ ] Intent/health examples remain distinct.
- [ ] Preview zero-side-effect trace passes.
- [ ] Diagnostics are redacted and local.
- [ ] Maintenance actions remain distinct and inert.
- [ ] Keyboard, VoiceOver, adaptive settings, and compact no-overflow rows
      pass.

Sign-off:
