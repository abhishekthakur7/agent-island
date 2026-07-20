# AB-140 iTerm2 Host navigation evidence

Run from `src/`:

```sh
swift build --target ITerm2HostAdapter
swift run AB140SelfCheck
```

`ITerm2HostAdapter` is the production outer boundary registered by the AppKit
composition. An explicit setup/capture starts its bundled
`iterm2_api_bridge.py` once; that helper retains one documented iTerm2 Python
API connection and one opaque helper connection incarnation while serving
serialized JSON commands over pipes. Jump Back never starts or reconnects the
helper: revalidation and immediate activation happen on that same live
connection, with the helper checking the expected incarnation and resolving
the opaque ID again. A disconnect fails closed; only another explicit setup
or reprobe can replace the helper incarnation.

The bridge uses only live `session_id`, `tab_id`, and `async_activate` methods.
It has no AppleScript, accessibility/UI automation, keystroke, terminal-input,
title, CWD, PID, ordinal, geometry, Space, or visible-text path.

The XCT-free self-check covers a live exact pane, separately captured tab,
explicit helper-incarnation replacement, duplicate locator IDs, and
fuzzy-lookalike rejection. XCTest fixtures cover the same faithful client seam
on a full Xcode installation. On this development machine the official
`iterm2` Python module is not installed, so a live enabled-iTerm2 API
invocation remains manual platform validation and is not claimed as passing
evidence.

Production reachability is the existing General Settings **Click behavior →
Jump Back** setting: the Island Overlay's primary pointer click invokes the
composition for exactly one visible Agent Session. The existing configured
`inspect` keyboard shortcut invokes the same explicit click path when that
behavior is selected. The expanded Overlay renders the exact achieved level
and redacted reason, and posts the identical string as a VoiceOver
announcement; `exactTab` explicitly says “select the pane.” A manual macOS
run with an enabled iTerm2 API is still required to capture pointer/keyboard/
VoiceOver platform evidence.

Before that click is useful, **Settings → Integrations → iTerm2 exact Host
Context** provides a production-reachable, clearly labelled person-asserted
setup path: select one source-observed Agent Session and paste exact documented
iTerm2 session/tab IDs. The live probe must resolve them before Agent Island
records the association and registers current host-navigation capability
evidence. It performs no title/CWD/PID/tab-order inference.
