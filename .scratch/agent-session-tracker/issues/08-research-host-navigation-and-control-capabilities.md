Status: closed
Type: research
Label: wayfinder:research
Parent: ../MAP.md
Assignee: Codex
Blocked by: none
Blocks: 14-define-host-context-identity-navigation-and-fallback.md, 17-define-overlay-window-display-input-and-accessibility-behavior.md, 18-define-integration-setup-reconciliation-and-uninstall.md, 21-research-native-macos-implementation-stacks.md
Resolution: answered

# Research Host navigation and control capabilities

## Question

What stable, supported APIs and identifiers do iTerm2, Cursor's integrated terminal and IDE, Warp, and Orca expose for discovering and activating the exact application, Space, window, tab, pane, workspace, or thread, and what honest fallback level is available for each failure mode?

## Comments

### Resolution — 2026-07-18

Answered in [Host navigation and control capabilities](../assets/host-navigation-capabilities.md). Exact Host Context targeting is only a live, host-specific capability: iTerm2 supports session IDs; Cursor requires a connected extension retaining a terminal object and cannot target native Agent threads; Warp has no supported exact local surface API; and Orca exposes runtime-issued terminal handles with tab-level focus. Spaces have no public stable activation identity, so app/window activation must be reported as an explicit lower-level fallback. Navigation and terminal control remain separate capabilities.
