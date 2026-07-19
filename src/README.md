# Agent Island — production source

The first production vertical slices for Linear tickets
[AB-118](https://linear.app/abhithakur/issue/AB-118) through
[AB-123](https://linear.app/abhithakur/issue/AB-123): a local macOS
application accepts source-proven Agent Session observations from a
controllable first-party Adapter fixture, commits immutable Normalized Event
Facts, derives revisioned lifecycle projections, renders the original Horizon
monitoring experience, and provides the Atlas Settings shell in a native
application surface.

AB-118–AB-122 establish the AppKit-first shell, typed inward ports, one-way
fact-to-screen flow, protected local Agent Session persistence, and the
non-activating Overlay. AB-123 adds a conventional independently activating
Settings window with contextual/resumable onboarding and local preference
semantics. This baseline remains local-first: it has no cloud connectivity,
telemetry, live Product control, Host navigation, or action routing. It builds
on the already owner-accepted [Overlay](../spikes/native-island-overlay) and
[protected-store](../spikes/sqlcipher-protected-store) spikes.

## Module boundaries

Enforced by `Package.swift` dependency edges, not just convention — a target
that must not reach another literally cannot `import` it.

```text
MacOSInfrastructure (AgentIslandApp: AppKit shell + SwiftUI content)
     |                                   |
     | (composition root only)          | ObservableObject binding
     v                                   v
ApplicationRuntime  <---- AdapterPort <---- AdapterFixtureKit
     |         \
     |          ---- PresentationPort <---- PresentationRuntime
     v
SessionStore  ---->  SessionDomain (pure: identity, validation, negotiation, reducer, projection)
```

| Module | Owns | Depends on |
| --- | --- | --- |
| `SessionDomain` | Identity types, envelope validation, negotiation rules, the pure replay-safe reducer, projection/outcome types | nothing |
| `AdapterPort` | The `AdapterIntakePort` protocol an Adapter/fixture submits through | `SessionDomain` |
| `PresentationPort` | The `PresentationPort` protocol the UI subscribes through | `SessionDomain` |
| `SessionStore` | Single-writer append-only fact ledger, commit ordinal, idempotent dedup, revisioned projection publication, redacted diagnostics | `SessionDomain` |
| `ApplicationRuntime` | The only component holding `SessionStore`; implements both ports | `SessionDomain`, `AdapterPort`, `PresentationPort`, `SessionStore` |
| `AdapterFixtureKit` | The controllable first-party Adapter fixture and its required-evidence scenarios | `SessionDomain`, `AdapterPort` **only** |
| `PresentationRuntime` | Main-actor projection subscriber → `AgentSessionCardSnapshot` | `SessionDomain`, `PresentationPort` **only** |
| `AgentIslandApp` | AppKit `NSWindow`/`NSApplication` shell hosting SwiftUI content; composition root | all of the above |

`AdapterFixtureKit` cannot import `SessionStore` — the target simply has no
such dependency — so it cannot hold a database/key handle, mutate a card
directly, or bypass validation, regardless of what a future Adapter
implementer tries. The same is true of `PresentationRuntime`: it cannot call
an Adapter or the canonical store because its target depends on
`PresentationPort` alone.

## Atlas Settings (AB-123)

Settings is a standard activating macOS window, independent of the selected-
display Overlay. Its persistent sidebar groups ten destinations into
Preferences (General, Integrations, Notifications, Display, Sound, Usage) and
Advanced (Shortcuts, Labs, Diagnostics, Maintenance), with one independently
scrolling detail pane. Onboarding is contextual in General: it can be started,
skipped, resumed, and completed without removing normal Settings navigation.

Settings restores its window frame, selected destination, local preference, and
onboarding state across close/reopen and terminate/relaunch. Integration
enabled intent is presented separately from observed health; previews are
local and read-only; diagnostics are redacted by construction. The
[AB-123 evidence template](Evidence/AB-123-REPORT-TEMPLATE.md)
covers the required lifecycle, onboarding, side-effect, redaction, state-model,
keyboard, VoiceOver, and adaptive-layout observations.

## Build

```sh
cd src
swift build
```

macOS 14+ Apple Silicon. This sandbox has Command Line Tools only, no full
Xcode: `swift build` works, but `swift test`/`swift build --build-tests`
fails at module resolution (`unable to resolve module dependency: 'XCTest'`)
before any test code runs — the same accepted limitation already documented
for the [Overlay](../spikes/native-island-overlay/README.md) and
[protected-store](../spikes/sqlcipher-protected-store/README.md) spikes. The
`Tests/` suites are written and reviewed but unexecuted here; run them on a
full-Xcode machine with `swift test`.

## Run

```sh
swift run AgentIslandApp
```

Starts the selected-display, non-activating Island Overlay and an Agent Island
status-menu item. Open **Settings…** from that menu for the independently
activating Atlas window: it contains resumable onboarding, local presentation
preferences, intent-versus-health integration rows, read-only previews, and
the complete grouped Settings navigation. Current Agent Sessions remain in
the Island Overlay. Adapter fixture scenarios run through the headless
self-check below rather than appearing as production Settings controls.

## Self-check (headless evidence capture)

```sh
Scripts/self-check.sh
# or: swift run AgentIslandApp --self-check
```

Runs every AB-118 required-evidence scenario against a real
`ApplicationRuntime`/`SessionStore` pair with no GUI, and additionally
asserts the two invariants a per-scenario outcome alone can't prove:
transport loss never reaches a terminal execution state, and a duplicate
stable delivery never produces a second card. See
[Evidence/AB-118-REPORT-TEMPLATE.md](Evidence/AB-118-REPORT-TEMPLATE.md) for
a captured trace and the required interactive/visual observations this
harness cannot substitute for.

The Atlas Settings shell is verified through the human-observed rows in
[Evidence/AB-123-REPORT-TEMPLATE.md](Evidence/AB-123-REPORT-TEMPLATE.md).

## What this slice deliberately does not do

- **No Product action dispatch.** The Island Overlay only hosts Horizon;
  its controls cannot acknowledge, complete, navigate to, or otherwise mutate
  an Agent Product conversation.
- **No integration setup or health invention.** AB-123 presents enabled intent,
  observed health, evidence, and safe next steps separately; discovery or an
  enabled switch cannot configure an Integration Installation or claim
  Healthy without source evidence.
- **No consequential maintenance yet.** Resetting preferences, removing setup,
  deleting selected local data, and complete cleanup remain distinct, inert
  destinations until later scoped plans and confirmations are implemented.
- **No Product-supplied result/recap content yet.** The current Adapter
  contract admits operational metadata only. Horizon reserves an honest empty
  completion-recap state rather than inventing a result; later capability
  work can supply bounded Interaction Content.
- **No real Adapter.** `AdapterFixtureKit` is a controllable first-party
  fixture that builds envelopes the way a real Claude Code Adapter would and
  submits them through the production intake boundary. The first real
  Adapter is AB-134.
