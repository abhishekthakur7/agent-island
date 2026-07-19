# Native Island Overlay feasibility spike

Disposable macOS 14+ Apple-Silicon spike for Linear ticket AB-116. It uses an
AppKit application lifecycle and `NSPanel` with hosted SwiftUI content to test
the Island Overlay window, input, display, accessibility, and lifecycle
boundaries. It intentionally contains no Agent Adapter, Product action, or
persistence implementation and must not be promoted into production code.

## Run

```sh
cd spikes/native-island-overlay
swift build
swift run NativeIslandOverlay
```

Use the menu-bar item to show/collapse the Overlay, deliberately engage its
keyboard mode, trigger **Automatic Reveal**, open the independent Settings
window, or quit. The status item is deliberately an accessory application:
launch, automatic reveal, hover, collapse, and withdrawal must not activate it.
Opening Settings is the one explicit activation path. Settings exposes
withdrawal, wake reconstruction, display selection, hover, and a deterministic
full-screen-policy simulation. The Overlay renders a representative
30-Agent-Session fixture.

For an automatic-reveal capture that leaves the app open for human focus and
accessibility observation:

```sh
swift run NativeIslandOverlay --evidence-scenario OW-1 --evidence-automatic-reveal-after-ready
```

`--evidence-quit-after-ready` remains the deterministic launch-measurement
mode. Do not combine it with the automatic-reveal argument.

## Verify and capture evidence

```sh
Scripts/build.sh
Scripts/test.sh
Scripts/capture-environment.sh
```

The XCTest suite covers the headless state machine, safe geometry, display
loss/reconnection, full-screen suppression, sleep/wake, termination, and the
fixture contract. A full Xcode installation is required for XCTest on macOS;
the Command Line Tools package alone may build the app but omit XCTest. For
this personal-use baseline, that limitation is an accepted implementation
risk rather than a gate.

Follow [Evidence/README.md](Evidence/README.md) for launch and resource capture,
then complete [Evidence/AB-116-REPORT-TEMPLATE.md](Evidence/AB-116-REPORT-TEMPLATE.md).
Automated traces do not replace the required Host-focus, VoiceOver, physical
display, Space/full-screen, sleep/wake, and ghost-window observations. Until
those rows are captured on supported hardware, they remain unverified. The
owner accepted the spike architecture for implementation on 2026-07-19.
