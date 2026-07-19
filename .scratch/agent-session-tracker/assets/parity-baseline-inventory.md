# Parity Baseline inventory

**Baseline snapshot:** Vibe Island v1.0.42 and its public materials observed on 2026-07-18.  
**Applies to:** Agent Island, a personal, local-first macOS 14+ Apple Silicon application.  
**First-class Agent Products:** Claude Code, Codex CLI, and Cursor.  
**First-class Hosts:** iTerm2, Cursor's IDE and integrated terminal, Warp, and Orca.

This is the authoritative inventory for the Wayfinder map. It records what the
in-scope Parity Baseline requires a later specification to cover; it does not
select implementation mechanisms, claim unobserved details, or import Vibe
Island branding or assets. “Must cover” means the later requirements and
acceptance tests must account for the behavior, with any intentional deviation
handled by the parity-acceptance decision.

## Evidence register

| ID | Evidence | Coverage |
| --- | --- | --- |
| E1 | [Local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md) §§ “Direct inspection” and “Core interaction model” (lines 17–472) | Installed v1.0.42 UI, accessibility hierarchy, bundled strings, supplied captures |
| E2 | [Local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md) §§ “Functional inventory” and “Onboarding” (lines 473–615) | Public materials and supplied onboarding captures |
| E3 | [Local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md) §§ “Lessons from 24 changelog releases” (lines 616–787) | v1.0.18–v1.0.42 changelog; failure and lifecycle evidence |
| E4 | [Local product research](../../../VIBE_ISLAND_FUNCTIONALITY.md) §§ “Evidence and caveats” and “Sources” (lines 816–855) | Evidence provenance and contemporaneous public links |
| E5 | [Wayfinder map](../MAP.md) §§ “Notes” and “Out of scope” | Binding project scope exclusions |
| E6 | [Domain glossary](../../../CONTEXT.md) | Canonical Agent Island vocabulary |

The local research document already records the source URLs (homepage, Claude
Code, Codex, and changelog) and the direct-inspection method. It is the frozen
evidence record for this snapshot; later releases are excluded.

## Scope application

The source product supports more Agent Products, Hosts, remote access,
licensing, account-like features, and telemetry than this map permits. Apply
the following rule to every inventory item: retain its user-visible behavior
and quality only when it concerns the stated first-class Agent Products and
Hosts, personal local use, or an explicitly required future extension seam.

| Source capability | Baseline treatment |
| --- | --- |
| Claude Code, Codex CLI, and Cursor session monitoring and interaction | **In scope.** First-class coverage. |
| iTerm2, Cursor IDE/integrated terminal, Warp, and Orca Host Context and Jump Back | **In scope.** First-class coverage. |
| Other coding tools and terminals | **Out of scope as products.** Retain only adapter/Host extension-contract tests; do not require their integration. |
| Codex Desktop | **Out of scope.** Codex CLI remains in scope. |
| SSH Remote, tunnels, remote setup, remote usage relays, and multi-Mac fan-out | **Out of scope.** Do not reproduce their UI or behavior. |
| Pass, pricing, purchase, licensing, device management | **Out of scope.** |
| Accounts, teams, collaboration, cloud sync, hosted storage | **Out of scope.** |
| Product-improvement telemetry/analytics | **Out of scope for implementation.** Preserve only a future-service boundary. |
| Beta-update channel or unrelated experimental integrations | **Out of scope.** |
| macOS versions before 14, Intel Macs, non-macOS platforms | **Out of scope.** |

The source’s feature breadth is evidence of interaction patterns, not a reason
to expand scope. The baseline is neither “latest Vibe Island” nor a clone.

## A. Session discovery, aggregation, and lifecycle

The application must cover these visible outcomes for concurrently active
Agent Sessions, including parent work and Subagent Runs where the Agent
Adapter can evidence them. [E1, E2]

| ID | Inventory item | Evidence |
| --- | --- | --- |
| S1 | Detect supported local Agent Sessions, including sessions launched from the supported Hosts, and make enabled intent visibly distinct from current integration health. | E1 lines 83–121; E2 lines 580–589 |
| S2 | Aggregate concurrent sessions across Agent Products, projects, worktrees, and Host Contexts into one island; preserve each session’s own title, initial prompt/summary, Agent Product, Host, model when available, elapsed/relative time, and current state. | E1 lines 234–292; E2 lines 475–488 |
| S3 | Present live activity where supplied: working/thinking, tool name and abbreviated parameter, compacting/context activity, waiting, completion, error, and Attention Request. Do not invent activity a source cannot support. | E1 lines 180–233, 293–345; E2 lines 475–488 |
| S4 | Represent Subagent Runs as children of the owning Agent Session, not as unrelated top-level work; support the adapter’s capability to show, hide, or summarize them. | E1 lines 324–344; E2 lines 475–488 |
| S5 | Preserve a completed session’s recap and a currently active session’s state through the UI transitions necessary to inspect it. Detailed retention, recovery, and archive policy remains for the persistence ticket. | E1 lines 346–368; E2 lines 475–488 |
| S6 | Surface setup/compatibility needs inline with the session list without falsely calling an enabled integration healthy. | E1 lines 21–36, 100–121 |

## B. Island and session-list presentation

The island is a non-modal, top-edge companion surface: attached to the notch
on the built-in display or a floating/pill-equivalent surface on a selected
external display. It is not a conventional notification toast. It uses an
original Agent Island visual identity while matching the source’s hierarchy,
legibility, density, and state distinction. [E1]

| ID | Inventory item | Evidence |
| --- | --- | --- |
| I1 | Provide distinct clean/resting and detailed/active collapsed layouts. The former emphasizes compact status and session count; the latter adds a short state/activity label. | E1 lines 171–233 |
| I2 | Keep the protected physical-notch region free of content; maintain stable leading activity and trailing total-count zones across animation and changing labels. On external displays, retain the same readable compact status without assuming a physical notch. | E1 lines 180–233; E2 lines 590–603 |
| I3 | Redundantly communicate state through status glyph/icon, color, motion, and meaningful accessible text. Active is visually distinct from healthy/completed, setup/attention, and error/destructive states. | E1 lines 21–36, 171–233 |
| I4 | Use a full-width expanding panel attached to the top edge, with a fixed global header (usage where enabled, sound/mute, Settings), scrollable session content, compact rows for lesser-relevance/history, and richer selected rows. | E1 lines 21–36, 234–292 |
| I5 | In a session row show a leading state indicator, strong project/task/title line, abbreviated “You” prompt, optional activity/result line, and trailing Agent Product/model/Host/time metadata without collisions. Long values truncate or are bounded. | E1 lines 253–292 |
| I6 | Support both a focused auto-reveal of one session and a full list of all sessions. Selection, focused auto-reveal, and “show all” are independent presentation state. | E1 lines 253–292, 346–368 |
| I7 | Allow an inline, independently scrollable completion recap with original prompt, done state, response content, and a bounded completion-card height. | E1 lines 346–368; E2 lines 590–603 |
| I8 | Include rich task and Subagent Run summary blocks only when supplied by the Agent Adapter; preserve task counters, parent-child indication, role/task, elapsed time, and current activity. | E1 lines 293–345 |

Observed visual specifics such as pixel-art accents, near-black hierarchy,
rounded lower panel corners, compact monospaced-looking status text, subtle
separators, native control conventions, and color semantics are visual
reference behavior. They must inform the original visual system rather than
be copied as branded assets. Exact dimensions, motion curves, and original
branding remain prototype work. [E1 lines 21–36, 180–233]

## C. Event-driven reveal, collapse, and priority

| ID | Inventory item | Evidence |
| --- | --- | --- |
| P1 | A newly detected session may receive a short automatic reveal that promotes its live detail while retaining other sessions beneath it, then returns to collapsed state absent further reason to stay open. | E1 lines 293–345 |
| P2 | Completion may reveal a focused recap temporarily; user interaction changes its lifecycle, and a focused card can lead to the full list. | E1 lines 346–368 |
| P3 | Attention outranks ordinary activity in the collapsed status and expanded ordering; unresolved attention count and all-session count remain separately visible. | E1 lines 369–394 |
| P4 | A user can expand, hover-expand when enabled, collapse on pointer exit when enabled, and return to the complete session list without losing active detail. Click-to-jump is configurable, so clicking cannot universally mean expand. | E1 lines 171–233, 253–292; E2 lines 590–603 |
| P5 | The overlay must not leave an invisible large hit target after a visual collapse, flicker in competing hover transitions, or steal ordinary editor/terminal focus. | E1 lines 346–368; E3 lines 735–749; E2 lines 590–603 |

The observed 2–3 second start and 3–4 second completion dwell are evidence of
short-lived automatic presentation, not settled constants. The later overlay
and notification decisions must set exact timings and interruption precedence.

## D. Attention Requests and action workflows

Attention Requests remain owned by their Agent Session and turn. A later
contract must preserve the source-specific capability rather than presenting
unsupported controls. [E1, E2, E3]

| ID | Inventory item | Evidence |
| --- | --- | --- |
| A1 | Surface an actionable in-island card for supported approval, question, plan-review, cancellation, or error/attention events; keep multiple parallel requests visible/queueable without crossing ownership. | E1 lines 369–457; E2 lines 489–506; E3 lines 651–692 |
| A2 | For supported permissions, show enough relevant command, file, diff, tool, or MCP context to make a decision; offer allow/deny and only the Agent Product’s demonstrably available always-allow or mode choices. | E1 lines 369–383; E2 lines 489–498 |
| A3 | Support free-text, multiple-choice, multi-select where available, and multi-question answers. Multiple-choice choices have visible keyboard mappings and require a valid selection before advancing. | E1 lines 395–440; E2 lines 489–498 |
| A4 | Preserve in-progress multi-question answers while moving between questions and while switching from focused to full-list presentation. | E1 lines 395–440 |
| A5 | For plan checkpoints, render required Markdown richness, allow approval, and return written revision feedback while preserving the Agent Product’s permission-mode semantics. | E1 lines 369–383; E2 lines 499–506; E3 lines 620–650 |
| A6 | When an action cannot be routed through the Agent Adapter, explicitly direct the user to continue in its owning Host Context rather than implying an action was applied. | E1 lines 369–383 |
| A7 | Dismissal, denial, response, acknowledgement, retry, and expiration must be session/turn/request-scoped; stale attention must disappear promptly once resolved and must never affect a later prompt. | E3 lines 620–692 |

The direct evidence leaves selected-answer visuals, free-text/multi-select
validation, approval context layouts, plan-feedback visuals, and conflicting
reveal-event precedence unobserved. These are explicit specification/prototype
targets, not implied source requirements. [E1 lines 441–457]

## E. Jump Back and Host Context

| ID | Inventory item | Evidence |
| --- | --- | --- |
| J1 | A session action or notification can Jump Back to the most precise valid Host Context: exact iTerm2/Warp terminal window, tab, or pane when supported; Cursor IDE/integrated terminal context; or Orca Agent Session context. | E1 lines 458–472; E2 lines 518–546 |
| J2 | Distinguish exact pane/thread targeting, exact window/tab targeting, application activation, and unsupported navigation. UI claims and controls must reflect the current capability level. | E2 lines 518–546; E3 lines 707–734 |
| J3 | Capture/reconcile stable Host Context identity across similar titles, multiple windows/tabs/panes, worktrees, Spaces, fullscreen, recreation, minimizing, hiding, closure, and missing macOS permission. | E3 lines 651–666, 707–749 |
| J4 | If exact targeting is stale or impossible, fall back honestly and visibly; never issue simulated keystrokes to an ambiguous target. | E3 lines 707–734 |

## F. Notifications, sound, filtering, and usage

All notification behavior remains personal, local, and non-disruptive. Its
later rules must prevent a sound, macOS notification, glow, or auto-reveal
from duplicating an already visible/relevant event. [E1, E2, E3]

| ID | Inventory item | Evidence |
| --- | --- | --- |
| N1 | Distinguish completion, error, approval, question/attention, acknowledgement, context limit, idle reminder, spam, and session-start events; each may have its own visible and sound treatment. | E1 lines 122–152; E2 lines 507–517 |
| N2 | Offer immediate mute/sound control plus master sound enablement, volume, per-event choices/preview, imported local sounds, and quiet hours (including across midnight). | E1 lines 83–99, 122–152 |
| N3 | Suppress/quiet sound and auto-reveal for Focus mode, locked/asleep screen, screen recording/sharing, configured launcher/probe work, directories, and first-prompt patterns; retain the appropriate subtle visual signal where the source does. | E1 lines 83–99, 122–137; E2 lines 507–517 |
| N4 | Provide transparent, previewable filtering and custom rules; internal helper/probe sessions must not create user-visible phantom sessions or noise. | E1 lines 122–137; E3 lines 620–650, 679–684 |
| N5 | Offer a configurable provider-usage header where an Adapter can safely provide usage: visibility, used-versus-remaining, preferred provider or active-session following, reset information, and reversible integration behavior. Do not make a usage bridge mandatory when unsupported. | E1 lines 153–156, 253–263 |

## G. Onboarding, Settings, integrations, and maintenance

| ID | Inventory item | Evidence |
| --- | --- | --- |
| O1 | Provide first-run education in context: aggregation, completion awareness, Jump Back, automatic detection/configuration, per-integration enablement/health, and an explicit activation/next step. | E1 lines 37–49; E2 lines 604–615 |
| O2 | Present a full Settings surface, not merely a tiny popover, organized around General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, and About/maintenance-equivalent concerns. Exclude remote, Pass/licensing, and telemetry functionality. | E1 lines 50–99; E5 |
| O3 | General controls cover launch at login; hover/reveal/collapse behavior; smart foreground suppression; fullscreen and no-active-session hiding; completion/attention reveal; click-to-jump; and evidence-based idle cleanup policy. | E1 lines 83–99 |
| O4 | Integration controls cover enabled intent, health, detection, setup/repair, Agent Adapter-specific compatibility, and custom Jump Back rules where the Host contract supports them. Intent and health are never conflated. | E1 lines 83–121; E2 lines 580–589 |
| O5 | Display controls cover selected display, clean/detailed layout, content size, maximum panel dimensions, completion-card height, optional project/worktree/model/Subagent/activity detail, live preview, and notch/pill geometry. | E1 lines 83–99 |
| O6 | Shortcut controls cover configurable modifier and mappings, session navigation, panel actions, Escape collapse, global disable without destructive reset, collision safety, and input-source compatibility. | E1 lines 83–99; E3 lines 620–650, 735–749 |
| O7 | Health, diagnostics, and maintenance must show why an integration/session/action was accepted, filtered, deduplicated, downgraded, or broken; repair must be separate from disable/remove. | E1 lines 83–121; E3 lines 750–764 |
| O8 | Installation/reconciliation/uninstall must only modify the application’s owned configuration/hook/extension entries; retain user paths, JSONC/comments, symlinks, unrelated configuration, external edits, and unknown-version safety. | E2 lines 580–589; E3 lines 693–706, 750–764 |

## H. Cross-cutting lifecycle, reliability, and accessibility states

These externally visible edge conditions are mandatory inventory coverage.
Their model, persistence, and acceptance thresholds are deliberately deferred
to their linked decisions. [E3]

| Area | States and rules to cover |
| --- | --- |
| Event integrity | Duplicate, delayed, reordered, missing, rewind/retry, compaction, reconnect, duplicate completion, and cross-channel events produce one correct session/request/notification state. |
| Identity and ownership | Every Agent Session, Subagent Run, turn, Attention Request, Agent Adapter, Host, window/tab/pane/thread, project, and worktree has stable ownership; presentation labels are not primary identity. |
| Recovery | Restart reconstructs canonical cards without duplicate/ghost state; sleep/wake invalidates stale handles and safely reconnects; host closure only reconciles owned sessions. |
| Cleanup | Never remove active work solely because a timer elapsed. Terminal event, confirmed Host closure, explicit dismissal, or a defined recovery policy is required. |
| Action safety | Approval, plan response, question response, shortcut, and Jump Back refuse ambiguous ownership and degrade visibly. Permission-mode changes cannot leak across Agent Sessions. |
| Overlay | Built-in/external display, display disconnect, Spaces, fullscreen, pointer-at-top-edge, activation policy, keyboard focus, Settings level, and termination have explicit states. |
| Accessibility | Decorative animation is not noisily announced; compact status has text equivalent; keyboard operation and focus behavior work alongside non-activating overlay behavior; reduced-motion, VoiceOver, and high-contrast behavior remain evidence gaps to specify. |
| Scale and resource use | Large lists remain scrollable/performant; sound playback releases resources; denied filesystem/Accessibility operations are handled explicitly. |

## Traceability handoff

| Downstream issue | Inventory inputs |
| --- | --- |
| Prototype island interaction and visual system | I1–I8, P1–P5, visual-reference paragraph, overlay/accessibility evidence gaps |
| Prototype attention, completion, plan, and question workflows | A1–A7, P2–P3, unobserved action-state list |
| Define notifications, sounds, filters, and usage behavior | N1–N5, P1–P3, General/Display control portions of O3/O5 |
| Define overlay, window, display, input, and accessibility behavior | I1–I7, P1–P5, J1–J4, H overlay/accessibility |
| Prototype onboarding, Settings, and diagnostics information architecture | O1–O8 and the scope table |

## Explicit non-requirements and unknowns

Do not turn the following into baseline requirements: exact source dimensions,
colors, sound files, pixel art, branded copy/assets, proprietary source,
remote flows, commercial/Pass flows, telemetry, cloud/team features, later
releases, unsupported Agent Products or Hosts, or source-specific controls
that lack a supported capability in the chosen Agent Adapter/Host.

The later acceptance and prototype tickets must resolve the documented visual
and behavioral evidence gaps rather than silently filling them with a guessed
clone behavior. [E1 lines 441–457; E5]
