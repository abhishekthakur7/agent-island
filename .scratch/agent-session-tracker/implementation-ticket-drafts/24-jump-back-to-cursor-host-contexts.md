# 24 — Jump Back to Cursor Host contexts

**Status:** ready-for-agent

## What to build

Implement Cursor Host Jump Back with exact integrated-terminal navigation only while a connected Cursor extension retains the matching live terminal reference. For Cursor IDE Agent threads and any stale or ambiguous terminal context, offer only proven workspace/file, app-level, or unavailable fallbacks and explain the limitation.

## Context and constraints

Cursor’s public terminal surface has no durable terminal/tab/pane identity and no cross-window enumeration. The exact locator is the extension-endpoint incarnation plus its retained live terminal reference; name and process ID are transient evidence, not identity. A native Cursor Agent/Composer thread has no supported exact selection API. A deep link or URL scheme may prefill/open work but is never Jump Back to an existing session.

No Host association can be inferred from a conversation title, workspace root, process, window, Agents Window row, or accessibility element. Extension reload, endpoint loss, or window closure invalidates exact terminal navigation without changing Agent Session lifecycle.

## Acceptance criteria

- [ ] A connected Cursor extension records a Host Context association only with explicit endpoint-incarnation and live terminal-reference evidence for the owning Agent Session.
- [ ] A revalidated terminal reference in the same connected Cursor window produces `exactSurface` and the person sees the exact terminal revealed.
- [ ] Extension reload, endpoint disconnect, terminal/window closure, lost reference, version incompatibility, or duplicate plausible terminals invalidates exactness and never recreates it from terminal name, process ID, title, path, or layout.
- [ ] Cursor IDE Agent/Composer threads never claim exact thread selection. A separately proven related workspace/file may yield `workspaceOrFile`; otherwise the truthful result is `appOnly` or `unavailable`.
- [ ] A lower Cursor route is used only when independently negotiated and associated with the same Agent Session; ambiguity at the highest available level offers a safe chooser or downgrades.
- [ ] Jump Back feedback, accessibility labels, health, and diagnostics distinguish exact terminal, workspace/file, app-only, and unavailable outcomes with redacted actionable reasons.
- [ ] The implementation does not emulate clicks, keystrokes, terminal input, chat selection, or UI automation, and a successful Jump Back does not authorize a Cursor action.

## Required evidence

- [ ] A capability-probed Cursor extension fixture demonstrates exact terminal reveal while its retained reference is live.
- [ ] Reload, multi-window, duplicate-name/PID, terminal closure, and native-thread fixtures prove invalidation and the correct lower fallback without fuzzy rebinding.
- [ ] A Jump Back outcome capture includes visual, VoiceOver, health, and redacted diagnostic statements for each achieved Cursor level.

## Blocked by

- #08 — Manage Integration Installations without owning external configuration
- #10 — Navigate through the capability-honest Jump Back ladder
