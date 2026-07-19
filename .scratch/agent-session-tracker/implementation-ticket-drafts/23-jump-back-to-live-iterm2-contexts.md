# 23 — Jump Back to live iTerm2 contexts

**Status:** ready-for-agent

## What to build

Enable Jump Back from an Agent Session to its exact live iTerm2 pane when a currently revalidated iTerm2 locator proves that target. If exactness is no longer available, make only the highest independently supported lower navigation attempt and state exactly what was achieved.

## Context and constraints

An iTerm2 session ID is exact only within a live iTerm2 API connection. It is not durable across relaunch and cannot be recreated from title, current working directory, PID, tab position, window frame, Space, or visible text. Host Context association remains separate from Agent Session identity and must be source-proven or a clearly marked person assertion.

The navigation ladder is `exactSurface`, then `exactTab`, then applicable window/app fallback, or `unavailable`; an app activation is not an exact navigation success. Jump Back never sends terminal input or grants an Agent Product action capability.

## Acceptance criteria

- [ ] A source-proven Agent Session–iTerm2 Host Context association preserves host identity, provenance, incarnation, opaque locator evidence, validation time, and prior navigation result without using presentation metadata as identity.
- [ ] Before every Jump Back, the integration revalidates the live iTerm2 API connection and recorded session locator; a live pane is activated through the documented host capability and reported as `exactSurface`.
- [ ] If the exact session is unavailable but a separately validated tab is available, the result is `exactTab` and explains that the person must select the pane; no pane success is claimed.
- [ ] Closed panes, tabs, windows, API disconnect, iTerm2 restart, incompatible capability evidence, and validation failure invalidate the exact locator while preserving historical association evidence.
- [ ] Missing exact evidence can use only a separately negotiated lower route for the same Agent Session; it never recreates a pane from title, CWD, PID, ordinal, geometry, path, or Space.
- [ ] Multiple similar iTerm2 contexts belonging to the same session at the same highest level require a safe chooser or a lower fallback; contexts from another Agent Session are never tried.
- [ ] Visual, VoiceOver, and diagnostic results name the achieved level and redacted reason, including `unavailable`; no fallback generates simulated terminal input or implicit product control.

## Required evidence

- [ ] A live or faithful iTerm2 fixture demonstrates revalidation and `exactSurface` activation of a recorded pane.
- [ ] Closure/relaunch/disconnect and duplicate-title/CWD/PID fixtures show invalidation, no fuzzy rebinding, and correct exact-tab/app-only/unavailable results.
- [ ] Keyboard, pointer, and VoiceOver captures show the same achieved-level statement and preserve the required Overlay focus behavior.

## Blocked by

- #08 — Manage Integration Installations without owning external configuration
- #10 — Navigate through the capability-honest Jump Back ladder
