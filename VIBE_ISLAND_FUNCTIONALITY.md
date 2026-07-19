# Vibe Island — Product Purpose and Functionality Notes

Research date: 2026-07-18  
Product: [vibeisland.app](https://vibeisland.app/)  
Platform: Native macOS application (macOS 14+, Apple Silicon)

Directly inspected build: Vibe Island v1.0.42 from `/Applications/Vibe Island.app`

## Executive summary

Vibe Island is a macOS companion for AI coding agents. It turns the MacBook notch—or a floating pill on an external display—into a compact control center for monitoring and interacting with many agent sessions at once.

Its core promise is to keep developers in their current editor or app while agents work elsewhere. From the island, a user can see session progress, notice when attention is required, approve or deny actions, answer agent questions, review plans, and jump directly to the exact terminal, tab, split pane, IDE window, or Codex Desktop thread that owns a session.

The product is not an AI agent itself. It is a local orchestration, notification, and navigation layer over existing coding tools.

## Direct inspection of the installed v1.0.42 app

The installed app confirms the broad product description above, but exposes several details that were missing or too general in the earlier notes. The inspection was read-only: the island, expanded session list, Settings window, accessibility labels, and bundled English UI strings were reviewed without changing preferences or activating integrations.

### Visual language and component hierarchy

The notch surface is visually separate from the conventional Settings window. It is a nearly black, edge-to-edge overlay that grows downward from the physical notch or floating pill, with large rounded lower corners and no conventional title bar. The dark surface is not flat: session rows, setup notices, transcripts, and footer actions use subtly different near-black fills and fine low-contrast separators to create depth without visible card borders everywhere.

The expanded panel has a consistent vertical hierarchy:

1. A compact header row. Usage information sits at the leading edge; mute/sound and Settings controls sit at the trailing edge.
2. Optional setup or compatibility banners, such as **Install Cursor extension?**, with a colored integration icon, one-line explanation, primary **Install** action, and a circular dismiss control.
3. A scrolling session region. Each session begins with a pixel-art status/agent icon, a strong task title, a secondary prompt or activity line, and compact metadata chips aligned toward the trailing edge. Chips distinguish the CLI/agent, model, host, and other context using icon, label, tint, and outline rather than relying on text alone.
4. Inline detail content for the selected or completed session. The detail block is inset, uses its own darker fill and rounded corners, distinguishes the user's prompt from the agent response, shows completion state at the trailing edge, and has an internal scrollbar when the recap is taller than the configured completion-card height.
5. A centered footer action such as **Show all 7 sessions**. This footer is part of the panel surface, not a detached macOS button, and toggles between the focused-card view and the full session list.

The clean collapsed layout is deliberately sparse: small pixel-art status glyphs sit at the leading side and a monospaced-looking session count sits at the trailing side. The detailed layout adds a short state label such as **Working…** or **Running** while preserving the count. Status is communicated redundantly through animation, glyph shape, and color. Blue is used for active/working agent activity, green for healthy/completed state, amber/orange for setup or attention, and red for errors or destructive/deny states.

The product uses compact pixel-art imagery as its signature accent, but the surrounding interface follows native macOS conventions: SF-style utility icons, traffic-light window controls, right-aligned switches, sliders with numeric value capsules, pop-up menus, inset grouped rows, native scrollbars, and restrained system typography. A clone should preserve that contrast rather than applying the pixel aesthetic to every control.

### Verified onboarding sequence

First launch is a multi-step guided sequence presented over the user's current desktop with the background dimmed. Progress dots remain near the bottom and each page has one dominant white rounded action button.

1. **Vibe Island — Dynamic Island for your AI coding tools.** The opening page anchors the Vibe Island mark near the notch, demonstrates the island over a real coding workspace, and offers **Get Started**.
2. **All your AI agents, one Dynamic Island.** A live island example appears at the top while a terminal/editor example demonstrates parallel agent activity below it.
3. **Know the moment it's done.** The page demonstrates completed-session surfacing and explains that finished work appears automatically without hunting through terminal tabs.
4. **Click to jump back.** The page pairs an island session with a terminal example and explains precise return to the owning window, tab, or split. It advances with **Next**.
5. **All Set.** A tall translucent/tinted card reports automatic detection and configuration, then lists supported agents with a health check and an individual enable switch. This page makes integration enablement explicit before continuing with **Next**.
6. **Welcome aboard.** The final page returns focus to the collapsed island, tells the user to restart existing sessions or begin a new one, and completes setup with **Start Vibing**.

The onboarding is not a generic modal wizard. It repeatedly uses the actual notch/panel in context, animates or swaps the supporting terminal/editor illustration, and teaches one product promise per page: aggregation, completion awareness, precise jump-back, integration setup, then activation.

### Settings visual structure

Settings uses a compact two-column macOS preferences window. A persistent dark sidebar contains colored square icons, destination labels, and muted group headings; the selected destination has a soft rounded gray highlight. The content pane scrolls independently and uses section headings followed by grouped control rows. Labels and explanatory copy are left aligned, while switches, menus, buttons, status indicators, and numeric values align to a stable trailing column.

Important component details visible across Settings include:

- blue macOS switches for enabled preferences and neutral gray switches for disabled preferences;
- green status dots and **Active** labels for healthy integrations, amber warning triangles and orange actions for incomplete setup, and separate enable switches even when health is not active;
- thin sliders with a blue filled track, white circular thumb, and a small value capsule on the right;
- live previews embedded directly in the Display page for both notch layouts and the session-card configuration;
- destructive or consequential maintenance actions visually separated from ordinary toggles;
- secondary explanations in smaller muted text immediately below the corresponding label instead of in tooltips;
- native scrollbars that appear inside the content pane and inside independently scrollable transcript/recap blocks.

These alignment, hierarchy, and state-color rules should be shared components in a clone. They are repeated throughout the application and are part of the product's perceived fidelity, not incidental styling.

### Actual Settings information architecture

Settings is a conventional resizable macOS window with a persistent dark sidebar. It has eleven destinations:

- **General**
- **Integrations**
- **Notifications**
- **Display**
- **Sound**
- **Usage**
- **Shortcuts** under an **Advanced** heading
- **SSH Remote** under **Advanced**
- **Labs** under **Advanced**
- **Pass** and **About** under a **Vibe Island** heading

This is a useful correction to the earlier description of “audio/settings controls”: settings are not a small popover. They are a full preference surface with sliders, pop-up menus, toggles, inline previews, integration health, diagnostics, licensing, and destructive cleanup actions.

### Verified settings and controls

| Section | Controls and behavior present in v1.0.42 |
| --- | --- |
| General | Launch at login; expand on hover; hover-duration slider; smart suppression while the owning terminal tab is focused; hide in fullscreen; auto-hide with no active sessions; auto-collapse on pointer exit; completion/warning auto-reveal dwell; optional outside-click dismissal; idle cleanup policy for sessions without a reliable close event; and an option to disable click-to-jump. |
| Integrations | Per-CLI health/status plus enable toggles; an **Add CLI Branch…** action; automatic setup of newly supported CLIs; a Claude Code native-terminal-title compatibility setting; and **Custom Jump Rules** for third-party terminals that register a URL scheme. |
| Notifications | Completion expansion versus a collapsed glow; independent subagent/Agent Team completion timing; quiet scenes; blocked launcher apps; directory filters; first-prompt filters; preset filter visibility; preview of how many live sessions a pattern would match; and right-click shortcuts from a session card to create directory or first-prompt filters. |
| Display | **Clean** and **Detailed** collapsed-notch layouts; target-display selection; content font size; completion-card height; maximum panel height and width; project, worktree, model, subagent, and activity-detail visibility; a live session-card preview; and fine notch-width/notch-height tuning. |
| Sound | Master sound-effects switch and volume; per-event sound selection and preview; imported sounds; quiet hours; and automatic muting of probe/health-check sessions. |
| Usage | Show or hide subscription limits in the expanded-panel header; choose whether the displayed value is used or remaining; select a preferred provider or follow the active session automatically; and connect a reversible Claude Status Line bridge without changing its visible output. |
| Shortcuts | Select the modifier key; globally disable shortcuts without erasing mappings; configure the session switcher and reverse switcher; collapse with Escape; and operate approvals, questions, options, and session navigation while the panel is open. Holding the modifier reveals button hints. |
| SSH Remote | Add, edit, set up, connect, and disconnect remote hosts so remote AI CLI sessions can be monitored and approved from the notch. The app supports SSH options, key/port/bastion configuration, manual-only connections for enterprise or browser SSO, remote Claude/Codex usage relay, Docker/Podman setup guidance, and both universal TCP and CLI-only Unix-socket tunnels. |
| Labs | Beta updates; an idle-only high-memory relaunch safety net; use Claude Code Auto Mode instead of Bypass; defer to native Claude Code approvals; choose how Codex approvals surface; and auto-detect Cursor sandbox approval behavior. |
| Pass / About | License/device management and Pass image copy/save actions; manual update checks and update-notification preferences; purchase/license status; website/community/feedback links; anonymized diagnostic export; optional product-improvement telemetry; acknowledgements; full auto-configuration removal; and Quit. |

The SSH feature has an explicit three-step flow—**Add Host → Set Up → Connect**. Setup uploads a small hook binary and configures supported remote CLIs. The UI states that public-key authentication is expected, with ControlMaster reuse available for MFA. It also contains recovery guidance for restricted networks, air-gapped machines, stale tunnels, changed host keys, port conflicts, and multi-Mac fan-out.

### Current integration surface shown by the installed app

The Integrations screen currently exposes these CLI-hook rows on this Mac:

- Claude Code
- Codex
- OpenCode
- Gemini CLI
- Cursor Agent
- Trae
- Droid
- Grok Build
- Kimi Code
- Copilot
- Copilot (VS Code Agent)
- Hermes
- Pi Agent
- Oh My Pi
- Amp

Each row separates the user's enabled intent from actual health. Healthy integrations show **Active**; other states include **Needs authorization**, **Hook file ready**, and an actionable **Activate** button. In the inspected build, Trae explains that its generated `hooks.json` still needs Configured Hooks enabled inside Trae, while Hermes 2026-04+ requires its Vibe Island plugin to be explicitly enabled. This means an enabled toggle must not be interpreted as proof that event delivery is operational.

### Notification filters verified in the UI

Quiet scenes silence sound and automatic expansion—including approval expansion—while still leaving a subtle completion dot. The available scenes are Focus mode, screen locked/asleep, and screen recording/sharing.

Built-in filters specifically suppress known internal/background work. The installed UI includes presets for:

- Codex memory-writer sessions under `/.codex/memories`;
- Codex Desktop Chronicle screen-recording summaries under `/chronicle/screen_recording`;
- Claude-Mem background compression under `/.claude-mem`;
- Codex memory-writer prompt prefixes;
- Codex Desktop suggested-prompt generation;
- Codex Desktop Git message helpers;
- Craft Agent title-generation prompts.

Custom directory rules use substring matching. First-prompt rules expose a match-type selector and pattern field. Launcher-app blocking happens earlier: sessions created by selected helper or probe apps are dropped before appearing at all.

### Sound event taxonomy verified in the UI

Sound is configured by event rather than by only the broad notification/approval/idle categories previously documented. v1.0.42 exposes:

- Session Start
- Task Complete
- Task Error
- Approval Needed
- Task Acknowledge
- Context Limit
- Idle Reminder
- Spam Detection, defined as three or more prompts in ten seconds

Each event has its own sound menu and preview button and may be set to **Off**. Users can import sounds, schedule quiet hours that may cross midnight, and auto-mute probe sessions such as CodexBar/ClaudeProbe health checks.

### Usage-limit display verified in the UI

The expanded-panel header can show provider usage as an icon, reset countdown, percentage, and secondary reset-period text. Settings can show **Used** or remaining capacity and can follow the currently selected session's provider automatically. Claude usage is read through a small reversible Status Line bridge: Vibe Island caches `rate_limits` and forwards the same input to the user's existing status-line command so its visible output remains unchanged.

## Primary user problem

Developers running several agents in parallel must repeatedly switch among terminals, IDE windows, tabs, and worktrees to answer questions or check progress. Ordinary notifications say that something happened but usually do not expose enough context or return the user to the precise session.

Vibe Island addresses this by providing:

- one unified view of agent sessions;
- ambient status that is visible without opening another app;
- actions for common blocking prompts;
- accurate navigation back to the session that needs attention;
- clear completion and attention signals across multiple agents.

## Core interaction model

### 1. Collapsed island

The default state is a small black pill attached to the notch/menu-bar area. Direct inspection confirms two selectable layouts:

- **Clean**, which prioritizes menu-bar space and shows compact pixel-art state plus a session count;
- **Detailed**, which adds a textual state such as “Working…” or “Running” and the session count.

Both variants use pixel-art agent/status icons. A completion can remain collapsed as a subtle glow/dot instead of expanding, depending on notification settings.

#### Detailed collapsed-notch screen specification

A live capture of the installed app with twelve active sessions verifies the following screen-level details. These should be treated as implementation requirements rather than as a loose visual reference.

**Surface and geometry**

- The island is a single uninterrupted near-black surface attached flush to the top edge of the display. It does not look like a detached notification toast.
- In the captured state, the visible surface is a wide, shallow bar approximately twelve times wider than its visible height. The device-specific width remains governed by Display settings, so this ratio is descriptive rather than a hard-coded size.
- The lower-left and lower-right corners are rounded. The top corners disappear into the display edge and should not read as the top corners of a floating pill.
- There is no visible outline. Separation from the underlying application comes from the solid black fill, rounded lower silhouette, and a very restrained shadow at most.
- The island does not dim, blur, or block the desktop below it while collapsed. Everything below the shallow notch surface remains usable and visually unchanged.

**Three-zone layout**

- The collapsed bar is organized into a leading status group, a deliberately empty center/notch region, and a trailing session-count group.
- Content is vertically centered on one compact baseline. Leading and trailing insets are visually balanced even though the groups have different widths.
- The center is a flexible spacer, not unused padding. It protects the physical camera/notch area and keeps text and icons on the two visible wings. No text, badge, progress bar, or click target should cross this protected region.
- The layout must tolerate different physical notch widths and the floating-pill mode on external displays without moving the status and count groups off-screen.

**Leading active-status group**

- Two small blue pixel-art glyphs appear first. They are decorative activity/status indicators rather than conventional SF Symbol buttons.
- The glyphs share the same electric-blue family but use different pixel silhouettes. Their animation frames may change while the agent works, creating activity without moving the surrounding layout.
- A short textual state follows the glyphs with a small fixed gap. In the capture it reads **Working…**; another observed animation/state frame reads **Running**.
- The state label uses compact monospaced or strongly monospaced-looking type, muted off-white/gray rather than pure white, and a heavier weight than secondary Settings explanations.
- The trailing dots/caret-like terminal frame is part of the working animation. The label area should reserve enough width for the longest state so animation frames do not cause the count or island width to jitter.
- Blue denotes active work. This is intentionally different from the green used for completion/healthy states and the amber/red used for attention or failure.

**Trailing session-count group**

- The far side shows **12 sessions** as a single compact phrase in the captured state.
- The numeric count is brighter and visually stronger than the word **sessions**, allowing the total to be scanned first.
- The label uses the same compact monospaced visual language as the working state and remains on one line.
- The count reflects all tracked sessions, not only the session supplying the current **Working…** state.
- The group is right aligned and remains stable while the leading activity glyphs or state copy animate.
- There is no disclosure chevron, close control, sound button, Settings button, project name, model badge, or individual-session metadata in this collapsed state. Those controls appear only after the island expands.

**State and interaction implications**

- The live capture was taken after clicking the notch, yet the app remained in the detailed collapsed state. Therefore, a click must not be hard-wired to mean “open the full panel” in every configuration.
- The implementation needs separate states for clean/resting, detailed/active or hover, focused completion auto-reveal, and fully expanded session list. They must not be represented by a single `isOpen` boolean.
- Click behavior must respect settings such as click-to-jump, while hover expansion must respect the expand-on-hover preference and configured delay.
- The detailed collapsed state may update from **Working…** to **Running** without changing its outer geometry. The pixel glyph animation and status-copy update should not trigger a full panel expansion.
- The entire visible black surface should behave as one coherent island hit region, while the protected physical-notch center remains free of visual content.
- Accessibility exposed the status and count as compact text equivalent to **Working… 12 sessions** while the pixel glyphs remained decorative. A clone should provide the same meaningful combined status without forcing assistive technology to announce animation frames.

**Capture artifacts that must not be implemented**

- The mouse pointer and soft circular halo visible near the center came from the computer-control capture environment; they are not a Vibe Island hover glow or product animation.
- The white area below the island was the active desktop/window background in the capture; it is not part of the island window.
- The capture was cropped for inspection. Its surrounding whitespace and crop boundaries do not define the production window size or hit area.

The island can auto-hide when no sessions are active. Its alignment and size can be adjusted, including for MacBook models and external displays.

### 2. Expanded session panel

Opening or hovering over the island reveals a larger dark panel containing multiple session cards or rows. Each session can show:

- session or task title;
- initial user prompt or short summary;
- agent/tool name;
- terminal, IDE, or host context;
- project name, optionally;
- relative time or elapsed time;
- working, waiting, completed, or attention-required state;
- live reasoning/status text and tool activity;
- completion recap;
- Git branch/worktree indicator;
- optional model name;
- nested subagents under their parent task.

Direct inspection shows color-coded status icons; agent, model, and host badges; recent completion summaries; a scrolling multi-session list; and header controls for usage limits, sound, and Settings. A completion row can expand in place into a scrollable transcript/recap. The footer can collapse the view to the most relevant card or reveal all sessions. The panel can also show an inline setup banner—for example, offering to install the Cursor extension required for precise terminal-tab jumping.

#### Verified expanded multi-session list

The fully expanded island is a dense, vertically scrolling activity surface rather than a stack of identical bordered cards.

**Panel shell and global header**

- The panel remains attached to the top display edge and expands almost the full configured maximum width and height, ending in large rounded lower corners.
- The shell is solid black. The desktop remains visible around the side and lower edges; it is not covered by a modal scrim.
- The header's leading side shows provider usage with a small provider icon followed by multiple limit windows. The captured example shows **5h 2% 29m | 7d 2% 6d6h**: period label, bright green percentage, and muted reset countdown, separated by a vertical divider.
- The header's trailing side contains only a sound/mute icon and a gear-shaped Settings button. Both are light gray, unboxed utility controls with generous hit targets.
- Usage, sound, and Settings remain fixed at the panel level while the session list scrolls below them.

**Session-row anatomy**

- A full-detail row uses a leading pixel-art status glyph, a central content column, and a trailing metadata column.
- The first line combines project/session name, a centered dot, and task title in strong white text. Long titles truncate with an ellipsis rather than wrapping into the metadata badges.
- The second line begins with a bold muted **You:** label followed by the initial prompt in gray. Long prompts truncate in compact rows.
- A third activity/result line is optional. Active tool use colors the tool name blue—for example **Bash**—while its command/path remains muted gray. Completed output or a recap may use gray or green depending on state.
- The trailing badges identify agent, model, host, and elapsed time. Codex uses a blue-tinted badge; Claude uses an amber/brown badge; model and host badges are neutral gray; elapsed-time badges are the lowest-contrast metadata.
- A bright green circular dot at the far trailing edge communicates a healthy/completed state for rows where text alone would be ambiguous.
- Pixel-art glyphs are state-coded: blue for active tool work, green for ready/completed activity, orange for a blocking Claude question, and a small neutral dot for compact idle/history rows.
- The narrow segmented bar beside some pixel characters is part of the status animation family and must remain aligned with the main glyph.

**Row-density variants**

- Active and recently completed sessions use the full two- or three-line layout.
- Older or less relevant sessions collapse to a single title line with a neutral leading dot and only essential agent/time badges on the right.
- A long completion summary may wrap across several lines instead of being clipped immediately, but it stays within the central content column and does not push badges out of alignment.
- Rows are separated primarily with vertical whitespace. The normal list does not put every session inside a visible card border.
- The selected or hovered row is an exception: it gains a full-width charcoal rounded rectangle. In the captured state, this also reveals a trailing archive/cleanup icon.
- Sessions from different projects are interleaved chronologically; the project name remains part of each title rather than becoming a separate section heading.
- The panel supports more content than fits vertically. Lower rows continue beyond the visible crop, so the list must scroll without moving the global header.

**Selection and disclosure behavior**

- Expanding one session reveals richer content inline while neighboring sessions retain their list positions below it.
- Attention content is placed at the top as the most urgent selected session; the remaining sessions stay accessible underneath in the full-list mode.
- A focused auto-popup instead hides the surrounding list and ends with **Show all 11 sessions**. Activating that footer transitions to the full-list mode without discarding the active question.
- The list therefore requires independent concepts for `selectedSession`, `focusedAutoReveal`, and `showAllSessions`; selection alone must not determine whether other sessions are visible.

#### Session-start auto-reveal with tasks and subagents

When a CLI hook detects a newly started parent session, the island can expand automatically for approximately **2–3 seconds**. This is a separate event and presentation from completion auto-reveal or an attention-required question.

**Lifecycle and state behavior**

1. A new-session hook event creates or updates the owning session in the local session registry.
2. The collapsed notch expands downward into the full panel shell without requiring a click.
3. The new session is promoted to the top and opened in a rich detail state showing its current tool activity, task breakdown, and spawned subagents.
4. Existing sessions remain visible underneath, preserving the broader multi-session context rather than replacing it with a standalone notification.
5. After roughly **2–3 seconds**, the temporary reveal returns to the collapsed notch when there is no further reason to remain expanded.

This needs its own `sessionStartAutoReveal` state and dwell timer. It must not be implemented by pretending that the user manually selected the session, because manual selection and automatic dismissal have different lifecycles.

**New-session header**

- The normal global provider-usage header, sound control, and Settings control remain visible.
- The session uses blue animated pixel-art glyphs because it is actively working rather than completed or blocked.
- The title line contains project, centered dot, and a truncated task title.
- The second line contains **You:** and the truncated initial prompt.
- The live activity line colors the current tool name blue—for example **Bash**—and shows a muted, truncated command after it.
- Trailing badges identify the agent, model, and host, such as **Claude**, **Opus 4.8**, and **Orca**.
- A bright green dot at the far right communicates that the session is connected/healthy while its blue glyphs communicate active work. These signals are complementary rather than interchangeable.

**Task-summary block**

- Tasks appear in a dedicated near-black inset block with rounded corners and generous internal padding.
- Its header reads **Tasks**, followed inline by a muted aggregate summary such as **(0 done, 1 in progress, 11 open)**.
- The three counters must be derived from task state and update live; they are not static descriptive text.
- Each task is a single compact row containing a state marker, issue/task identifier, and title.
- The current in-progress task uses a filled blue circular marker and brighter off-white text.
- Open tasks use empty rounded-square checkbox-like markers and lower-contrast gray text.
- The captured preview shows only the first several tasks even though the header reports twelve total tasks. The component therefore needs a bounded preview/overflow policy rather than assuming every task will fit.
- Task identifiers such as **AB-89** remain visually attached to their titles so users can map agent work back to the external tracker.
- Long task titles remain on one line in the captured density and should truncate before escaping the inset block.

**Subagent-summary block**

- Subagents use a second independent near-black rounded block immediately below Tasks.
- The header begins with a small branching/tree icon, then **Subagents**, followed by the count in parentheses—for example **(1)**.
- Each subagent row begins with a blue status dot, followed by a bold role/name and its assigned task in parentheses, such as **general-purpose (Implement AB-89 mobile layout)**.
- Elapsed time, such as **24s**, appears inline at the end of the primary subagent row in muted text.
- A subordinate activity line is indented with a tree elbow/branch glyph. It shows the current shell/tool activity, including a `$` prompt and a truncated command.
- The indentation and tree glyph communicate parent-child ownership; a subagent must not look like another top-level session.
- Task and subagent blocks are related but separate: the task list communicates planned work state, while the subagent block communicates who is executing work and what they are doing now.

**Relationship to the remaining session list**

- After the two inset blocks, normal sessions resume using the established row anatomy and badge alignment.
- The promoted new session consumes more height than ordinary rows, but it does not visually restyle every neighboring session as a card.
- Existing active, completed, and compact historical rows keep their own status colors and density underneath.
- The panel may overflow vertically during this reveal, so the rich new-session content participates in the same scroll region as the remaining sessions while the global header stays fixed.

#### Completion auto-reveal lifecycle

When one session completes, the island enters a temporary focused completion state. This is distinct from the user manually opening the full session list:

1. The notch expands downward into the large panel with a smooth height-and-corner expansion animation.
2. The completed session is selected automatically and shown as the only primary card, even when many sessions exist.
3. The focused completion remains visible for roughly **3–4 seconds** in the observed UI so the result can be read at a glance.
4. If the user does not interact, the panel reverses the expansion and returns automatically to the collapsed notch state. It must not remain as an invisible full-screen or full-width hit target after its visible content has collapsed.

The focused completion layout contains:

- the normal panel header, with provider-usage/reset information on the left and sound plus Settings controls on the right;
- a colored pixel-art completion glyph and narrow activity/status bars at the leading edge of the session row;
- the project/session title followed by a centered dot and concise task title;
- right-aligned metadata pills for the agent, model, and host, followed by a bright green completion dot and a cyan jump-back control;
- two muted one-line summaries below the title: the initial **You:** prompt and the final response, both truncated with an ellipsis when needed;
- a large inset recap card with a fine gray outline and rounded corners;
- a recap header containing **You:**, the wrapped original prompt, and a trailing **Done** state, separated from the answer by a subtle horizontal divider;
- the agent's completion response in monospaced text, with an internal vertical scrollbar when it exceeds the configured completion-card height; and
- a low-emphasis centered footer such as **Show all 11 sessions**, which opens the complete multi-session view.

The animation should preserve the sense that the panel grows from and collapses back into the physical notch. The recap appears as part of the expanding surface rather than as a separate popup window or notification banner.

### 3. Attention and action cards

When an agent is blocked, the island expands into an actionable card. Depending on the integration, the user can:

- allow or deny file edits, shell commands, MCP calls, and other permission requests;
- choose “always allow” or permission-mode options where supported;
- answer multiple-choice questions using buttons or keyboard shortcuts;
- answer free-text questions;
- handle multi-question prompts through a paginated wizard;
- review a proposed plan rendered as Markdown;
- approve a plan or send written feedback for revision;
- see a “Continue in Cursor” style cue when an action must be completed in the source app.

Parallel approval requests are queued so multiple agent runs can be managed without losing prompts.

#### Verified collapsed attention and live-tool states

The detailed collapsed notch changes its central message according to the highest-priority live event:

- During ordinary active work, it can show the current tool and a truncated parameter summary, such as **Bash: cd /Users/abhishekt…**, preceded by blue animated pixel glyphs and followed by **11 sessions**.
- When Claude is waiting on an `AskUserQuestion` tool call, the glyphs switch to orange and the central label becomes **AskUserQuestion** in high-contrast monospaced text.
- The attention variant adds an amber/brown capsule containing an orange bell and the pending-attention count, such as **1**, before the total session count.
- The attention badge count and total session count are separate values: one represents unresolved prompts, while the other represents all tracked sessions.
- The task/activity label truncates before colliding with the counts. The trailing count region remains stable as tool names and parameters change.
- Attention orange replaces active blue throughout the glyph, bell, question header, category tag, and option-number system, establishing one coherent blocking-state color.

#### Verified Claude multi-question wizard

An `AskUserQuestion` request expands into a paginated wizard embedded inside the island. The screenshots verify both a focused popup and the same wizard at the top of the full session list.

**Owning-session header**

- An orange pixel-art agent glyph and question-mark frame identify the blocking session at the leading edge.
- The title line shows project, centered dot, and truncated task name. The next line shows **You:** plus a truncated initial prompt.
- Right-aligned metadata pills show **Claude**, the model such as **Opus 4.8**, the host such as **Orca**, and elapsed time such as **<1m** or **1m**.
- A cyan jump-back control remains at the far trailing edge. It visually combines a keyboard hint with an outbound/up-right arrow.
- Depending on available width and mode, an archive/cleanup icon may appear alongside the session metadata.

**Wizard identity and progress**

- An orange two-speech-bubble icon introduces **Claude's Question**, followed by the total in muted orange parentheses—for example **(3 questions)**.
- A row of small circular progress indicators appears below. Answered questions are green, the current question is orange, and unanswered future questions are gray.
- The textual counter, such as **Question 1 of 3** or **Question 2 of 3**, is aligned to the far right on the same progress band. It uses muted monospaced text.
- Both dot progress and textual progress are present; neither should be removed as redundant because they serve different scan patterns.

**Question and option structure**

- The question begins with an orange bracketed category tag such as **[Branch]** or **[Linear status]**, followed inline by the question in bold off-white text.
- Each answer is a full-width amber-brown rounded row with consistent vertical spacing.
- A brighter orange rounded number tile appears at the leading edge of each row. Numbering begins at 1 and maps directly to keyboard selection shortcuts.
- The option title is bold and off-white. Supporting explanation sits below in smaller muted gray text and may wrap to a second line.
- Recommendation guidance is included within the explanation as **(Recommended)** instead of using a separate badge.
- A subtle trailing chevron communicates that the entire option row is actionable.
- When the configured modifier key is held, the trailing chevron is replaced by shortcut hints such as **⌃1**, **⌃2**, and **⌃3**. The number tile remains visible, so shortcut disclosure augments rather than replaces the visual numbering.
- Selecting an option is required before advancing. The screenshots show no preselected default, including for the recommended answer.

**Wizard navigation**

- **Previous** is left aligned and **Next** is right aligned below the option stack.
- On the first question, **Previous** is disabled. On later questions it becomes a filled medium-gray button with a left chevron.
- **Next** remains disabled until the current question has a valid response. Its disabled state uses a near-black fill and very low-contrast label/chevron.
- The focused modifier state can add the keyboard shortcut beside **Next**, including the Control-plus-Return mapping used to submit multi-select responses.
- Moving from question 1 to question 2 changes the dot colors, counter, category, question copy, options, and Previous state while preserving the panel shell and owning-session header.

**Focused popup versus full-list presentation**

- In focused auto-popup mode, the question consumes the panel's primary body and a centered **Show all 11 sessions** footer sits at the bottom.
- In full-list mode, the question remains the first and most prominent session. Other sessions continue immediately below it, including a completed session with its own badges and older compact rows.
- One captured full-list variant places the wizard in a subtly lighter rounded container with an outline, visually separating the active blocking workflow from the sessions beneath it.
- The wizard must preserve its current question and any entered answers when switching between focused and full-list modes.
- The panel does not open a separate macOS dialog for the question; the complete workflow stays inside the notch surface.

#### Evidence gaps remaining after this screenshot set

These captures substantially resolve the expanded-list and question-flow design, but they do not yet show:

- the visual state of a selected answer, selection reversal, validation error, or submitted answer;
- free-text and multi-select question inputs, including long input, focus, and error behavior;
- live approval/deny/always-allow cards and their command, file, diff, or MCP context;
- plan-review Markdown, feedback entry, and revision states;
- context menus and the right-click directory/first-prompt filter workflow;
- completed/failed task markers, task-list overflow controls, multiple simultaneous subagents, and whether task or subagent rows are directly actionable;
- the exact behavior when another session-start, completion, or attention event arrives during the 2–3 second new-session dwell;
- precise transition durations and easing between collapsed attention, focused question, full list, and return-to-notch states;
- reduced-motion, keyboard-focus, VoiceOver, and high-contrast variants; or
- the same flows on an external-display floating pill and at minimum/maximum configured panel dimensions.

These are remaining evidence targets, not blockers to beginning information architecture or component planning. They should remain explicit unknowns rather than being silently invented during visual design.

### 4. Jump back to source

Clicking a session or notification returns the user to the owning context rather than merely opening the terminal application. The product claims precise targeting of:

- terminal window;
- terminal tab;
- split pane;
- IDE window and integrated terminal;
- tmux or Zellij session/pane;
- agent pane in tools such as Orca or herdr;
- Codex Desktop thread;
- the correct macOS Space or fullscreen window.

This precise jump is one of the product’s main differentiators.

## Functional inventory

### Session monitoring

- Auto-detect active sessions from supported AI coding tools.
- Combine sessions from different agents into one panel.
- Track session state in real time.
- Show thread/session titles and update them automatically.
- Display live agent reasoning or progress text where available.
- Display tool names and parameters such as Read, Write, Edit, Bash, and tests.
- Show when an agent is thinking, compacting context, using a tool, waiting, completed, or needs attention.
- Send macOS completion and attention notifications.
- Provide away/idle recaps for supported Claude Code sessions.
- Group subagents under parent sessions and provide controls to filter or hide them.
- Support parallel sessions, worktrees, and multiple IDE windows.

### Permission approval and Q&A

- Approve or deny agent permission requests from the notch.
- Show relevant command, file, diff, or tool context before approval where supported.
- Offer keyboard shortcuts for common actions.
- Answer multiple-choice and free-text agent questions.
- Support multi-question workflows.
- Route approvals to the correct session during parallel work.
- Expose agent-specific modes such as follow-focus, notify, silent, auto, or always-allow where available.

### Plan review

- Detect plan-review checkpoints such as Claude Code `ExitPlanMode`.
- Render headings, lists, code blocks, and other Markdown content.
- Approve the plan from the island.
- Send feedback so the agent can revise the plan.
- Preserve or match the agent’s active permission mode.

### Notifications and sounds

- Notify on completion, approval requests, questions, and other agent events.
- Use synthesized 8-bit/pixel-style sounds.
- Import custom sound packs or create custom sounds.
- Independently configure notification, approval, and idle reminder sounds.
- Quickly mute from the expanded panel.
- Use quiet scenes to stay silent during Focus mode, screen lock, screen recording, or screen sharing.
- Define silence rules by prompt text, title, CLI/tool, project path, hidden directory, or launching app.
- Suppress duplicate alerts when the user is already viewing the relevant conversation.

### Terminal, IDE, and agent-host integration

The site claims support for 20+ terminal/host environments. Explicitly mentioned examples include:

- iTerm2;
- Ghostty;
- Warp;
- Terminal.app;
- WezTerm;
- Kitty;
- Alacritty;
- Hyper;
- Zed;
- Zellij;
- tmux and tmux `-CC`;
- VS Code;
- Cursor;
- Windsurf;
- Antigravity integrated terminals;
- Orca;
- Otty;
- Superset;
- Supacode;
- cmux;
- Conductor;
- herdr.

The product distinguishes precise jumping from fallback activation. Its FAQ says precise window/tab/pane jumping is available for a subset of terminals; other terminals receive app activation with best-effort tab matching. The exact list changes frequently, so clone work should model this as an extensible capability registry rather than a hard-coded set.

### AI coding-agent integration

The live site advertises support for 26 agents and names the following families/integrations across its homepage and changelog:

- Claude Code;
- OpenAI Codex CLI and Codex Desktop;
- Gemini CLI;
- Cursor Agent and Cursor IDE;
- ZCode;
- Antigravity CLI;
- Trae;
- OpenCode;
- MiMoCode;
- Factory Droid;
- Qoder;
- Qwen;
- Grok Build;
- Kimi Code/Kimi;
- DeepSeek;
- Mistral Vibe;
- GitHub Copilot CLI and VS Code agent flows;
- CodeBuddy;
- WorkBuddy;
- Kiro;
- Hermes;
- Amp;
- Pi Agent;
- Oh My Pi;
- Gajae Code;
- Craft Agent.

The onboarding screenshot also shows per-integration enable/disable switches after automatic detection. Agent capabilities are not necessarily identical: some provide only monitoring and completion events, while others also support approvals, questions, live tool details, plan review, or precise jumping.

### Automatic setup and maintenance

- Scan the Mac for installed/supported agents.
- Auto-configure hooks, plugins, IDE extensions, launchers, or other integration points.
- Show detected integrations during onboarding and let the user toggle each one.
- Detect overwritten or broken hooks and repair them.
- Respect custom config paths and JSON-with-comments files where supported.
- Auto-install or reconcile IDE extensions for relevant integrations.
- Offer a complete uninstall that removes installed hooks, extensions, and launcher scripts.

### Display and interaction preferences

- Work at the built-in MacBook notch and on external displays.
- Prompt the user to switch which display hosts the island.
- Auto-hide in fullscreen or when idle, depending on settings.
- Customize panel width and expanded height.
- Tune notch alignment.
- Auto-collapse when the pointer leaves.
- Offer a keyboard-navigable session switcher.
- Customize shortcuts, reset individual bindings, disable global shortcuts, or reverse the shortcut mode.
- Toggle visibility of project name, model name, branch/worktree, and subagents.
- Right-click the pill for Settings and Quit.
- Use a non-activating overlay that does not steal focus from the current editor or terminal.

## Onboarding flow observed in supplied screenshots

The screenshots indicate a polished, multi-step onboarding flow with approximately five pages:

1. A full-screen introduction overlays the user’s desktop/app and presents Vibe Island as a “Dynamic Island for your AI coding tools.”
2. A prominent **Get Started** action begins setup.
3. The product scans for supported AI agents and automatically configures them.
4. An **All Set** screen lists detected tools with green checkmarks and an individual switch for each integration.
5. Progress dots and a **Next** button guide the user through remaining setup or education.

The onboarding uses a retro pixel-art visual language, rounded black/white panels, red gradient presentation screens, and a temporary branded wallpaper/background treatment.

## Lessons from 24 changelog releases

The following review covers 24 substantive releases from v1.0.18 through v1.0.42. It intentionally ignores features outside this personal-use project’s scope and focuses on failures that could affect local session monitoring, approvals, navigation, notifications, configuration, and UI behavior.

### Release-by-release findings

| Release | Relevant mistake or correction | Lesson for our build |
| --- | --- | --- |
| v1.0.42 | Plan approval changed Claude Code’s permission mode; dismissed questions remained visible; some Codex approvals were routed inaccurately. | Treat approval, prompt dismissal, and mode selection as separate session-scoped state transitions. An approval must never mutate an unrelated permission preference. |
| v1.0.41 | Session cards disappeared after restart; Cursor produced duplicate/ghost subagents; approval cards were lost during parallel runs; Rewind created duplicate sessions. | Persist canonical session identities, make event ingestion idempotent, and model parallel approval requests as a durable queue. |
| v1.0.40 | OpenCode emitted repeated completion notifications; active Kimi sessions were removed; status setup could overwrite custom configuration; broken hooks needed repair. | Deduplicate completion events, use explicit activity evidence before cleanup, and make configuration changes merge-safe and self-healing. |
| v1.0.39 | The app notified for conversations already being viewed, intercepted silent auto-review events, and missed completion cards in native IDE sessions. | Attention rules need foreground-context awareness and a clear taxonomy separating user-facing prompts from automatic internal work. |
| v1.0.37 | Window jumps often reached only the app, not the exact pane; background alerts were missed; approval cards became stuck; hover caused panel flicker. | Use stable window/tab/pane identities, not simulated keystrokes. Drive cards and hover behavior with explicit state machines. |
| v1.0.36 | The app could crash after the Mac woke from sleep. | Treat wake as a cold-resume boundary: invalidate stale handles, reconnect integrations, and rebuild derived UI state safely. |
| v1.0.35 | The same wake-from-sleep crash required another release. | Add repeat sleep/wake stress tests; a single successful resume test is insufficient. |
| v1.0.34 | Old warnings and recap text leaked into later turns; prompts could disappear during tool cleanup; one Codex thread affected another thread’s visibility. | Scope every transient value by session and turn. Cleanup must operate on exact ownership, never global heuristics. |
| v1.0.33 | Renamed Cursor modes were interpreted incorrectly; an OpenCode migration broke its event bridge; plugin discovery could connect to the wrong local process; always-allow behavior regressed. | Version and capability detection belong inside each adapter. Validate process identity and fail closed when permission semantics are unknown. |
| v1.0.32 | A preceding release caused wrong-window jumps; question text could be lost; sessions were removed after a fixed five-minute timeout; shortcuts collided. | Preserve prompt payloads until explicit resolution, base cleanup on lifecycle signals instead of TTL alone, and validate shortcuts against active bindings. |
| v1.0.31 | New customization work introduced wrong-window navigation and other regressions fixed immediately in v1.0.32. | New settings must reuse the same tested routing and state primitives as defaults; feature breadth should not bypass core invariants. |
| v1.0.30 | A prior release froze the session list; Gemini approvals left sessions stuck; a placeholder conflict crashed Kimi; custom sounds did not persist. | Test adapter events against the shared session reducer, namespace integration data, and verify persistence through a full restart. |
| v1.0.29 | Empty toolbar areas opened a context menu; large session lists needed virtualization; restricted file systems exposed compatibility issues. | Keep hit targets exact, design list rendering for many parallel sessions early, and handle denied/unavailable filesystem operations explicitly. |
| v1.0.28 | An upstream Claude Code change broke the mode shortcut; auxiliary subagents polluted the main list; editing configuration triggered false hook-removal warnings. | Avoid undocumented shortcuts, classify helper sessions separately, and debounce/reconcile configuration changes before declaring an integration broken. |
| v1.0.27 | Cursor could remain stuck in “working”; Warp navigation needed tab/split-pane fixes. | Require terminal-state confirmation for every adapter and test navigation across multiple windows, tabs, and panes. |
| v1.0.26 | UI scrolling still had bounce defects after broader integration work. | Maintain a small interaction-polish suite for scrolling, expansion, collapse, and edge positioning even while adapters change rapidly. |
| v1.0.25 | External-display hiding misfired; symlinked config needed protection; idle audio and Accessibility-driven window restoration could crash; Settings flashed during prewarm. | Test symlinked dotfiles, multi-display state, idle teardown, Accessibility calls, and hidden-window creation as first-class lifecycle paths. |
| v1.0.24 | Nearly the same integration bundle and fixes appeared again in v1.0.25, now marked beta. | Introduce new adapters behind explicit capability flags and graduate them only after lifecycle, approval, and jump behavior pass the same contract tests. |
| v1.0.23 | Settings could fall behind other windows; dropdowns failed on multi-monitor setups; Quit did not work reliably. | Define window level, activation policy, display ownership, menus, and termination behavior explicitly instead of accepting framework defaults. |
| v1.0.22 | Hooks were not restored after restart; Cursor CLI and Cursor IDE were confused; uninstall cleanup was incomplete. | Persist integration intent separately from current hook state, distinguish agent from host application, and maintain an exact installation manifest. |
| v1.0.21 | CJK input methods delayed shortcuts; split-pane matching was inaccurate; config files with comments needed special handling. | Test shortcuts with multiple input sources, use durable pane identifiers, and preserve JSONC/comments and unrelated user settings during edits. |
| v1.0.20 | Codex approval detection could contribute to desktop instability; Cursor cards flashed briefly. | Put risky event interception behind a kill switch and suppress UI until an event passes identity and relevance validation. |
| v1.0.19 | Internal probes created phantom sessions; hover could immediately collapse the panel; approval response was slow. | Mark internal traffic at the source, debounce opposing hover transitions, and keep the approval path short and synchronous where possible. |
| v1.0.18 | Agents inside Cursor terminals were invisible; Cursor terminals were misidentified as VS Code; closing the host left incorrect session state; top-edge hover detection failed. | Model agent, terminal, and host IDE as separate identities. Propagate host closure deterministically and test pointer behavior at screen boundaries. |

### Recurring root causes

#### 1. Identity was inferred from unstable presentation data

Many bugs involved wrong windows, duplicate sessions, ghost subagents, or confusion between Cursor and VS Code. Titles, process names, visible prompts, and window order are useful labels but poor primary keys.

Our design should assign stable identifiers to:

- agent session;
- parent and subagent relationship;
- conversation turn;
- approval or question request;
- host application;
- window, tab, and pane;
- project and worktree.

Every incoming event should include or resolve to these identifiers before it changes UI state.

#### 2. Event processing was not consistently idempotent

Repeated notifications, duplicate cards after Rewind, and phantom sessions suggest the same logical event could be consumed more than once or arrive through multiple channels.

Required guardrails:

- give events stable IDs when the integration supplies them;
- otherwise derive a bounded deduplication key from session, turn, event type, and source timestamp;
- make reducers safe to replay;
- store the last accepted sequence/cursor per session;
- test duplicate, delayed, reordered, and missing events.

#### 3. Cleanup relied on timing and broad heuristics

Fixed timeouts removed active sessions, while other cards remained stuck after completion. Cleanup should be evidence-based.

A session should leave the active list only after a terminal event, confirmed host closure, explicit dismissal, or a carefully defined recovery policy. A timeout may trigger reconciliation, but should not directly delete a session that still has activity or unresolved prompts.

#### 4. Approval state was coupled to general session state

The changelog repeatedly mentions lost, stuck, misrouted, or semantically incorrect approvals. Approval requests need their own lifecycle:

`received → presented → responding → acknowledged → resolved/dismissed/expired`

Each request must retain its original session, turn, permission mode, payload, and response. Closing a card or completing a tool cleanup event must not silently destroy an unresolved request.

#### 5. Upstream agent behavior changed frequently

Agent modes were renamed, hook formats moved, desktop implementations migrated, and internal helper sessions appeared. A single generic integration layer will become a maze of exceptions.

Each adapter should own:

- supported version range;
- capability detection;
- event translation;
- known helper/internal-session filters;
- configuration migration;
- permission semantics;
- degradation behavior when an upstream contract is unknown.

#### 6. Configuration writes were too risky

The product had to fix overwritten settings, custom config paths, symlink handling, comments, hook drift, and false hook-removal alerts.

Our configuration writer should:

- resolve the correct config path without assuming defaults;
- preserve comments and unrelated keys;
- understand symlinks;
- write atomically;
- keep an in-memory before/after representation for validation;
- reconcile after external edits;
- record only the exact entries our app owns;
- never replace a whole file to change one hook.

#### 7. Precise navigation was treated as easier than it is

Reliable jumping required repeated fixes across terminal apps, multiple windows, tabs, split panes, Spaces, worktrees, and recreated agent panes.

For each host, define navigation capability levels:

1. exact pane/thread jump using a stable host API;
2. exact window/tab jump;
3. application activation only;
4. unsupported.

The UI should promise only the level currently available. If identity becomes stale, reconcile it or fall back honestly instead of sending simulated keystrokes to an uncertain target.

#### 8. Overlay lifecycle and macOS window behavior need dedicated testing

Hover flicker, immediate collapse, wrong display ownership, Settings window level, fullscreen behavior, top-edge hit testing, sleep/wake crashes, and Accessibility restoration appeared repeatedly.

These paths need an explicit test matrix:

- built-in display and external display;
- multiple Spaces and fullscreen apps;
- pointer entering/leaving at the screen edge;
- display connect/disconnect;
- sleep/wake and app restart;
- host minimized, hidden, moved, or closed;
- Accessibility permission absent, granted, or revoked;
- keyboard focus and non-QWERTY/CJK input sources.

### Non-negotiable engineering rules for our clone

1. Start with only the agent and terminal adapters needed for personal use; prove the adapter contract before adding more.
2. Use one canonical session store and pure, replay-safe reducers for all integrations.
3. Keep approvals and questions as durable entities, not booleans attached to session cards.
4. Never delete an active session solely because a timer elapsed.
5. Never route a response or jump unless session ownership is unambiguous.
6. Never overwrite an integration’s configuration file; merge only app-owned entries atomically.
7. Prefer stable host APIs and identifiers over titles, window order, or simulated keystrokes.
8. Validate an event before showing UI, playing a sound, or sending a notification.
9. Put invasive or version-sensitive integration behavior behind a per-adapter kill switch.
10. Test restart, duplicate events, event reordering, sleep/wake, multiple windows, worktrees, and host closure before calling an adapter reliable.
11. Keep the island non-disruptive: no focus theft, audio takeover, hover loops, or repeated completion noise.
12. Provide a diagnostics view that explains why a session, prompt, or jump was accepted, ignored, deduplicated, or downgraded.

### Minimum regression suite derived from the changelog

- The same event delivered twice creates one card and one notification.
- Rewind/retry creates a new turn without duplicating the session.
- Two parallel agents can request approval without either request disappearing or crossing sessions.
- Dismissing a question removes it immediately and does not affect later questions.
- Plan approval preserves the chosen permission mode.
- An internal helper/subagent can be nested or hidden without hiding its parent.
- An active session survives idle time, compaction, and temporary missing events.
- A completed session cannot remain permanently “working.”
- Restart reconstructs session cards without duplication.
- Sleep/wake invalidates stale handles and restores integrations without a crash.
- Closing an IDE removes or reconciles only sessions owned by that IDE.
- Two IDE windows with similar titles jump to the correct tab/pane.
- A recreated pane either self-heals its identity or visibly falls back to app activation.
- Config changes preserve comments, symlinks, custom paths, and unrelated settings.
- External config edits do not create false “integration removed” warnings.
- Shortcuts work with non-QWERTY and CJK input sources and never collide silently.
- Rapid pointer entry/exit cannot cause an expand-collapse loop.
- The overlay behaves correctly on a built-in display, external display, and across Spaces/fullscreen.
- Audio is released after playback and never takes over the output device while idle.
- An unknown upstream agent version degrades safely instead of guessing permission semantics.

## Clone-relevant product boundaries

A faithful clone needs more than a floating notch UI. The essential system has four layers:

1. **Agent adapters** — ingest hooks/events from each coding agent and normalize them into a shared session/event model.
2. **Session state engine** — track parents/subagents, status, prompts, approvals, completions, and recovery after restarts.
3. **Action routing** — return approvals, answers, and plan feedback to the correct agent session safely.
4. **Context navigation** — map a session to its terminal/IDE/thread identity and focus the exact window, tab, pane, or Space.

The notch panel, notifications, sounds, onboarding, and settings sit on top of these layers.

## Suggested normalized capability model

Each agent adapter should declare capabilities instead of assuming every integration supports every feature:

- `sessionMonitoring`
- `liveText`
- `toolEvents`
- `completionNotifications`
- `permissionRequests`
- `questionPrompts`
- `freeTextAnswers`
- `planReview`
- `subagents`
- `preciseJump`

This matches the observed product behavior and allows integrations to degrade gracefully.

## Evidence and caveats

Confirmed from the live site on 2026-07-18:

- homepage feature sections;
- Claude Code integration page;
- Codex integration page;
- changelog through v1.0.42, dated 2026-07-18.

Confirmed from supplied screenshots:

- collapsed and expanded island layouts;
- multi-session list and status presentation;
- onboarding overlay and five-step progress treatment;
- automatic tool detection/configuration with per-agent switches;
- sound/settings controls and external-display switching prompt.

Confirmed by direct inspection of the installed v1.0.42 app:

- the Clean and Detailed collapsed layouts;
- expanded-panel session rows, completion recap, usage header, sound/Settings controls, and inline integration setup banner;
- the complete Settings sidebar and the General, Integrations, Notifications, Display, Sound, Usage, Shortcuts, Labs, and About control surfaces;
- integration health states and the current 15-row CLI-hook inventory;
- notification presets, custom directory/prompt rules, launcher blocking, quiet scenes, and live pattern-match previews;
- event-specific sound configuration, imported sounds, quiet hours, and probe muting;
- the Claude Status Line usage bridge and automatic provider-following behavior;
- SSH Remote and Pass capabilities corroborated by the installed build's bundled English UI resources.

One supplied screenshot shows an unrelated local product dashboard (“The Automator”); it was not treated as evidence of Vibe Island functionality.

The supported-agent and terminal lists change quickly and are slightly inconsistent between the homepage, integration pages, onboarding screenshot, and newest changelog. They should be treated as a time-stamped inventory, not a permanent specification.

## Sources

- [Vibe Island homepage](https://vibeisland.app/)
- [Claude Code integration](https://vibeisland.app/claude-code/)
- [Codex integration](https://vibeisland.app/codex/)
- [Changelog](https://vibeisland.app/changelog/)
- Installed Vibe Island v1.0.42 UI, macOS accessibility hierarchy, and bundled English UI resources
- Local screenshots captured from the installed app on 2026-07-18
