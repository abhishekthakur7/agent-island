# Agent Island — production source

The first production vertical slices for Linear tickets
[AB-118](https://linear.app/abhithakur/issue/AB-118) through
[AB-122](https://linear.app/abhithakur/issue/AB-122): a local macOS
application accepts source-proven Agent Session observations from a
controllable first-party Adapter fixture, commits immutable Normalized Event
Facts, derives revisioned lifecycle projections, and renders the original
Horizon monitoring experience in a native application surface.

This slice is deliberately **observation-only**: no live Product control,
configuration ownership, host navigation, cloud connectivity, action routing,
or durable persistence. It establishes the AppKit-first shell, SwiftUI-hosted
presentation content, typed inward ports, and one-way fact-to-screen flow the
architecture ADRs require, on top of the already owner-accepted
[Overlay](../spikes/native-island-overlay) and
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
activating conventional window: it contains the display/presentation controls,
Agent Sessions, Adapter fixture controls, and scenario log. Every fixture
button submits through `AdapterIntakePort` — the same typed boundary a real
Claude Code/Codex/Cursor Adapter would use — so triggering a scenario from the
UI is real evidence, not a UI-only simulation.

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

## What this slice deliberately does not do

- **No Product action dispatch.** The Island Overlay only hosts Horizon;
  its controls cannot acknowledge, complete, navigate to, or otherwise mutate
  an Agent Product conversation.
- **No Product-supplied result/recap content yet.** The current Adapter
  contract admits operational metadata only. Horizon reserves an honest empty
  completion-recap state rather than inventing a result; later capability
  work can supply bounded Interaction Content.
- **No real Adapter.** `AdapterFixtureKit` is a controllable first-party
  fixture that builds envelopes the way a real Claude Code Adapter would and
  submits them through the production intake boundary. The first real
  Adapter is AB-134.
