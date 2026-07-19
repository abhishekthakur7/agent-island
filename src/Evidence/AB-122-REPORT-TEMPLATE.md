# AB-122 — Native Island Overlay feasibility evidence

## Implemented boundary

- One non-modal `NSPanel` is bound to an explicit stable selected-display UUID.
  It is normally non-activating, never joins all Spaces, and is withdrawn
  rather than migrated when that display disappears.
- The panel's visible geometry drives the only AppKit hit regions. Built-in
  display geometry reserves the protected center from content and hit regions;
  external displays have one equivalent floating top-edge surface.
- Keyboard engagement is explicit and visible. Escape, collapse, display loss,
  quiet-scene suppression, sleep, and termination release it and remove the
  panel's mouse/accessibility regions before ordering it out.
- Settings is a separate ordinary, activating `NSWindow`, reachable from the
  status-menu application menu whether or not the overlay is available.

## Repeatable headless evidence

```sh
cd src
swift build
swift run AgentIslandApp --self-check
```

`AgentIslandAppTests/IslandOverlayModelsTests.swift` covers the pure lifecycle
and geometry contract. Run `swift test` on a full-Xcode macOS machine; this
checkout's Command Line Tools installation cannot resolve XCTest.

## Required native observations (not yet represented as passing evidence)

| Observation | Capture / result |
| --- | --- |
| Built-in-notch and external selected display: visible region, no protected-center hit/AX node | pending |
| Auto reveal, hover, inspect/expand click, redraw: prior Host key window stays key | pending |
| Explicit keyboard engagement: visible first target, traversal, Escape/collapse release | pending |
| Disconnect/reconnect: withdraw/no migration, then collapsed-only restore | pending |
| Fullscreen/Space and configured quiet-scene screen sharing behavior | pending |
| Repeated sleep/wake and Quit: no residual panel/hit/AX region or Product action/navigation | pending |
| VoiceOver collapsed aggregate, expanded rows, visible-only traversal, and accessibility adaptations | pending |
