# Host navigation and control capabilities

Research date: 2026-07-18  
Scope: local macOS Host Context navigation for iTerm2, Cursor, Warp, and Orca. This document distinguishes a supported, exact target from app activation and from an Accessibility-derived best effort. It does not infer control capability from a URL scheme, a window title, or screen position.

## Decision

Agent Island must represent Host navigation as a currently validated capability with a typed locator, not as a generic `open host` action. Exact pane targeting is available only while the host-issued runtime locator is resolvable. It must never be reconstructed from a title, working directory, process ID, tab ordinal, geometry, or screen image.

Use this navigation ladder, reporting the level actually achieved after every Jump Back:

| Level | Meaning | User-visible result |
| --- | --- | --- |
| `exactSurface` | A supported host API resolved and selected the recorded tab/pane/terminal. | “Opened the exact terminal/pane.” |
| `exactTab` | A supported host API resolved and selected the recorded tab, but cannot select a child pane. | “Opened the exact tab; select the pane.” |
| `workspaceOrFile` | A supported API opened the recorded workspace or file, not the original live surface. | “Opened the related workspace/file.” |
| `windowBestEffort` | Accessibility located one currently matching window and raised it; the match is not an identity claim. | “Brought a matching Host window forward.” |
| `appOnly` | macOS activated/launched the Host application only. | “Opened <Host>; the original context could not be located.” |
| `unavailable` | The Host is absent, its integration is disconnected, permission is missing, or there is no supported locator. | “Can’t jump back: <specific reason>.” |

`windowBestEffort` must be opt-in after Accessibility permission is granted, must not synthesize a durable Host Context association, and must be labelled as best effort. Automated input, keystrokes, and clicks are control operations, not a navigation fallback.

## System boundary: macOS windows, Spaces, and Accessibility

Public macOS activation can launch or make an application frontmost; Accessibility can enumerate and raise accessible windows when the user grants the TCC permission. Neither creates a public stable identifier for a Mission Control Space nor a public API to activate an arbitrary Space. Full-screen windows are Spaces as well, and the system's “When switching to an application, switch to a Space with open windows” setting can change where an app-level activation lands.

Therefore:

- persist an observed display/frame/AX window description only as diagnostic evidence;
- do not persist a Space as a navigable identifier or promise a particular Space/full-screen placement;
- treat failure to resolve a window on the currently visible Space, a full-screen transition, and a denied Accessibility permission as `appOnly` or `unavailable`, never as success;
- when an exact host API focuses its own window, allow macOS to choose the Space and report only the host-confirmed surface level, not a Space claim.

## Host matrix

| Host | Supported locator and selection | Exactness and lifetime | Honest fallback |
| --- | --- | --- | --- |
| iTerm2 | Python API exposes `window_id`, `tab_id`, and globally unique `session_id`; `App.async_activate`, `Window.async_activate`, `Tab.async_activate`, and `Session.async_activate` select the hierarchy. The documented AppleScript dictionary also exposes window/tab/session objects, session `unique id`, tab `select`, and session `select`. | `session_id` is the pane identity and is exact for a live iTerm2 instance/API connection. It must be re-resolved on every Jump Back and invalidated on session/tab/window closure or API disconnect; the documentation does not promise persistence across iTerm2 relaunch. A session activation selects its pane but must be preceded by tab/window/app activation. | If the session ID is absent, use the live tab ID for `exactTab`; if it too is absent, activate a known window; then `appOnly`. Never recreate a session by title/CWD. |
| Cursor integrated terminal | An installed Cursor extension can enumerate `vscode.window.terminals`, retain a live `Terminal` object, and call `Terminal.show()`, which reveals that terminal. It can observe opens/closes and use `processId` and `name` as transient evidence. | Exact terminal selection is possible only in the same Cursor window while the extension retains the object reference. The public Terminal interface has no stable terminal/tab/pane ID, no supported cross-window terminal enumeration, and no layout/pane selector. `name` and `processId` are not durable identifiers. | If a supplied extension endpoint is connected but its terminal reference is gone, activate its Cursor window (`windowBestEffort`/`appOnly`) or open a project/file through the Cursor CLI/URI (`workspaceOrFile`). Without that endpoint, Cursor offers app/workspace/file-level navigation only. |
| Cursor IDE chat / Agent thread | Cursor's public extension surface has URI handlers and generic chat-provider APIs, but no documented public API that locates and reveals an arbitrary native Cursor Agent/Composer thread by a stable thread ID. | No supported exact thread locator. A private Cursor data model, a chat title, or an accessibility element is not a supported thread identity. | Focus/activate Cursor, or open a related workspace/file. Say that the original thread cannot be selected. Do not emulate clicks into chat history. |
| Warp | The inspected Warp build registers a `warp` URL scheme, but has no SDEF/AppleScript dictionary and its public documentation provides no supported API or identifier for enumerating/selecting a local window, tab, pane, or Warp block. A scheme registration alone is not a navigation contract. | No supported exact locator for the local desktop terminal surface. Accessibility labels, tab titles, and block text are mutable presentation. | `appOnly` is the supported baseline. `windowBestEffort` is available only under the general Accessibility policy and cannot claim a particular Warp tab/pane. |
| Orca | Orca's shipped CLI/runtime exposes `terminal list --json` (live Orca-managed terminals), `terminal show --terminal <handle>`, and `terminal switch --terminal <handle>`/`terminal focus`. The local build's terminal model also uses a tab ID plus a UUID terminal-layout leaf ID explicitly described as surviving renderer reloads. It can list/select Orca-managed Worktrees and open workspace files. | A runtime-issued terminal handle is the command boundary and supports exact live terminal-tab selection while the Orca runtime recognizes it. A `tabId:stableLeafId` pane key is durable across renderer reloads but is host-internal implementation evidence, not an external cross-version contract; consume it only through the version-matched Orca runtime, and revalidate the returned handle before use. `terminal switch` is documented as a *tab* selection, so it must report `exactTab` unless a current runtime version explicitly confirms child-pane focus. | If handle validation fails but the Orca Worktree is still resolved, use a supported worktree/file action (`workspaceOrFile`); otherwise activate Orca (`appOnly`). Do not select by terminal title or worktree path alone. |

## Control boundary

Navigation and terminal input are distinct capabilities:

- iTerm2 can send input through its supported Python/AppleScript control surface after the exact live `session_id` is resolved.
- A Cursor extension can write/send to a live `Terminal` object it holds, subject to Cursor's extension API and user configuration. It cannot turn a terminal title or PID into an arbitrary terminal control target after restart.
- Orca exposes `terminal send`, `wait`, `stop`, `rename`, `split`, and close operations against a runtime-issued terminal handle.
- Warp has no supported local pane-control API in the researched surface.

All input-bearing actions require the separate Adapter capability and consent/attention policy. A successful Jump Back must not imply permission to send text, approve, deny, or manipulate a terminal.

## Failure and reconciliation rules

| Condition | Required behavior |
| --- | --- |
| Host app is not installed, cannot launch, or terminates during activation | Return `unavailable` with the host and failure; never fall through to a similarly named app. |
| Integration endpoint/API is disabled, disconnected, or version-incompatible | Mark its exact capability unavailable; offer only the next declared fallback. |
| Saved runtime locator no longer resolves (closed pane/tab/window, iTerm2/Orca restart, Cursor extension reload/window close) | Invalidate the locator. Do not use titles, CWD, PIDs, tab order, or fuzzy matching to rebind it. |
| Multiple Cursor windows or same-name terminals | An extension endpoint is scoped to one Cursor window. A locator must include that endpoint instance; ambiguity downgrades to `appOnly`/`workspaceOrFile`. |
| Full-screen transition, another Space, display move, minimized/hidden window | Ask the supported host API to activate its surface if available. If not, app activation is the highest supported level; do not assert Space correctness. |
| Accessibility denied, revoked, or element tree changes | Do not attempt UI automation. Omit `windowBestEffort` and explain how to enable Accessibility only if the user elects to use it. |
| URL scheme exists but has no documented destination grammar | Do not invoke it for navigation. This specifically applies to Warp's observed `warp://` registration. |
| Product-owned Agent Session still exists but Host Context was recreated | Preserve the Agent Session. Record the old Host Context as unavailable and associate a new one only on strong host/adapter evidence; do not silently replace it. |

## Evidence

Primary documentation:

- [iTerm2 Python API index](https://iterm2.com/python-api/) and its [App](https://iterm2.com/python-api/app.html), [Window](https://iterm2.com/python-api/window.html), [Tab](https://iterm2.com/python-api/tab.html), and [Session](https://iterm2.com/python-api/session.html) references: hierarchy identifiers and activation methods.
- [iTerm2 AppleScript reference](https://iterm2.com/documentation-scripting.html): window/tab/session hierarchy and the documented `select` / `unique id` terms. iTerm2 labels AppleScript deprecated; use its Python API as the preferred surface.
- [VS Code extension API: Terminal](https://code.visualstudio.com/api/references/vscode-api#Terminal) and [Window](https://code.visualstudio.com/api/references/vscode-api#window): `Terminal.show`, terminal lifecycle, and the lack of a public terminal ID. Cursor ships this compatible extension type surface; behavior still must be capability-probed against the installed Cursor version.

Local, version-specific inspection on the research Mac:

- iTerm2 3.5.5 (`com.googlecode.iterm2`) includes the Python API wrapper and `iTerm2.sdef`.
- Cursor 3.12.17 (`com.todesktop.230313mzl4w4u92`) registers `cursor://` and ships a VS Code-compatible `vscode.d.ts`. Its CLI supports project/file opening but exposes no command for selecting an existing terminal/tab or native chat thread.
- Warp 0.2026.07.15.08.55.01 (`dev.warp.Warp-Stable`) registers `warp://`, but its bundle has no SDEF and the consulted Warp documentation exposes no local window/tab/pane scripting contract. Treat this as absence of a supported exact-target API, not proof that hidden/private mechanisms cannot exist.
- Orca 1.4.145 (`com.stablyai.orca`) `orca agent-context --json` declares `terminal list`, `terminal show`, and `terminal switch`; its bundled `stable-pane-id` module documents a UUID leaf ID chosen because it crosses renderer reloads, PTY environment, hook IPC, and retained UI rows. This is evidence for version-probed runtime targeting, not a promise to depend on private app files.

## Consequences for dependent work

The Host Context definition must retain: host kind and bundle identifier; capability generation/version; optional endpoint instance; one typed runtime locator; evidence timestamps; and the most recent achieved navigation level/reason. It must not use a single universal `window/tab/pane/thread` string, a title, a Space ID, or a synthetic cross-host locator.

The integration/setup work must health-check exact navigation independently for each host, especially the Cursor extension endpoint and iTerm2 Python API connection. The overlay work must present fallback language at the achieved level and not render a successful Jump Back merely because `NSWorkspace` made an app frontmost.
