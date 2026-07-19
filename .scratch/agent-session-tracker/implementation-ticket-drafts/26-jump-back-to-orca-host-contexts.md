# 26 — Jump Back to Orca Host contexts

**Status:** ready-for-agent

## What to build

Enable Jump Back through the version-matched Orca runtime, revalidating its live terminal handle before use. Report `exactTab` for the documented terminal-switch capability unless the current negotiated runtime explicitly proves child-pane focus; otherwise fall back to an associated workspace/file, app-only, or unavailable result.

## Context and constraints

The runtime-issued terminal handle is the only command boundary. Internal stable-pane observations are implementation evidence, not an external cross-version locator, and must be consumed only through a compatible runtime that currently validates the handle. A worktree/path resemblance cannot revive an exact Orca terminal. Navigation never permits terminal send/stop/split/rename or Agent Product actions.

## Acceptance criteria

- [ ] A source-proven Orca Host Context association retains the version/mode-scoped runtime evidence and opaque terminal handle separately from Agent Session identity.
- [ ] Before every Jump Back, the current Orca runtime/version capability and terminal handle are revalidated; the documented tab-selection route reports `exactTab`, not pane or surface success.
- [ ] `exactSurface` is available only when the currently negotiated Orca runtime explicitly confirms selection of the exact child surface; no internal implementation detail upgrades the result.
- [ ] A failed/expired handle, Orca restart, runtime disconnect, incompatible version, or contradictory evidence invalidates exact navigation and preserves historical association evidence rather than rebinding by title, Worktree, or path.
- [ ] When independently proven, an associated Worktree/file produces `workspaceOrFile`; otherwise the implementation uses `appOnly` or `unavailable` and states the exact reason.
- [ ] Navigation feedback, accessibility, health, and redacted diagnostics consistently state `exactTab`, `exactSurface`, workspace/file, app-only, or unavailable with no false success claim.
- [ ] No Jump Back path sends terminal input or invokes Orca terminal control operations, and locator loss does not change the owning Agent Session lifecycle.

## Required evidence

- [ ] A version-matched Orca runtime fixture proves live-handle validation and documented `exactTab` navigation.
- [ ] A current-runtime exact-child fixture, if available, proves the extra capability before `exactSurface` is shown; otherwise the evidence records its absence.
- [ ] Restart, handle loss, duplicate-recognition metadata, incompatible runtime, and workspace fallback fixtures prove no fuzzy rebinding and the exact achieved result.

## Blocked by

- #08 — Manage Integration Installations without owning external configuration
- #10 — Navigate through the capability-honest Jump Back ladder
