# AB-142 Warp Jump Back boundary evidence

## Registered implementation

`WarpHostAdapter` is registered in the package and composed by the AppKit app
root. It contains the production outer boundary for Warp: real `NSWorkspace`
app activation/launch and real macOS Accessibility trust, focused-window,
live-window enumeration, and `kAXRaiseAction` calls.

The supported baseline is app-only. `windowBestEffort` can occur only after a
person invokes `electCurrentFocusedWindowBestEffort()` from a contextual UI
control, grants Accessibility at that moment, and the same process-local AX
object occurs exactly once in a current live probe. Revalidation/navigation do
not request Accessibility permission. The token placed in the domain's
`warpAXWindow` locator maps only to an in-memory AX object; a new adapter
instance treats it as stale and falls back to app-only.

No code accepts or retains a URL, custom destination, title, tab/pane/block
text, terminal content, path, geometry, Space, or AX label. The AX boundary
has no input, key, pointer-click, text-entry, or terminal-input API. Its only
AX mutation is `kAXRaiseAction` on the already elected current window.

`WarpHostNavigationPort.feedback` is the required UI/VoiceOver/diagnostic
copy seam. It states the achieved level/reason and, for both app-only and
window-best-effort, explicitly says that the original Warp pane and tab were
not verified. It never includes a candidate token or Accessibility metadata.

## Controlled evidence

```sh
cd src
swift test --filter WarpHostAdapterTests
swift run AB142SelfCheck
```

The fixtures cover permission absent/denied/granted, no election, zero/one/
multiple current matching objects, stale election, app absence, same-title /
full-screen / Space non-matching, forbidden input, and a custom URL scheme
that remains unused. These are controllable seam checks, not proof of a live
Warp or macOS Accessibility run.

## Reachable composition

Settings → Integrations → **Warp Jump Back** now offers a person-selected
current Agent Session setup path. **Associate selected session with Warp
app-only Jump Back** stores only an in-memory app association and does not
activate Warp. **Use currently focused Warp window best effort** is the only
control that calls the election API and may prompt for Accessibility. The
app-root multi-host router sends a session to Warp only when Warp is its sole
associated Host; concurrent Cursor/iTerm2/Warp associations are reported as
ambiguous rather than guessed.

The election creates an in-memory `HostContextAssociation` using the returned
ephemeral locator and adapter incarnation. It is not persisted, restored,
synced, exported, or reused. Overlay text and VoiceOver use the shared Warp
outcome wording, which states both achieved level/reason and that the original
Warp pane/tab were not verified. Diagnostics contain only level/reason.

## Manual macOS evidence still required

1. With Warp running, use the explicit contextual election control and verify
   that macOS asks for Accessibility only after that control is selected.
2. Deny/revoke permission and verify an app-only result; do not observe a
   window raise.
3. Grant permission, focus one Warp window yourself, elect it, and verify a
   best-effort foreground result whose VoiceOver text says pane/tab are
   unverified.
4. Open a second Warp window, restart Agent Island, change Space/full-screen,
   and verify no window is guessed; app-only/unavailable remains explicit.
