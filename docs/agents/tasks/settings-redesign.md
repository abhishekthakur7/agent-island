# Implementation task: redesign the Settings window to match the reference design

## Golden rule — read this first

**The reference screenshots (#9–#19) ARE the specification. Do not invent UI.**
Same rule as the overlay spec (`overlay-visual-redesign.md`): reproduce what the
images show — every label, description subline, control type, default state, option
label, section order, and icon — exactly as shown. If a detail isn't in a
screenshot, flag it in "Open questions"; do not design it from taste. Acceptance is
verified by **side-by-side comparison to the cited image**, not by "it compiles".

`≈` values are eyeballed from the mockups; if a design source (Figma) exists,
sample exact values and treat those as authoritative.

---

## Reference image index

| Ref | Screen |
|-----|--------|
| **#9** | Notifications — Custom Filters: Directory + Custom Filters: First Prompt (scrolled) |
| **#10** | Display — Notch (preview, Clean/Detailed, Display picker) + Panel size (top) |
| **#11** | Display — Panel size (Session card toggles) + activity-detail preview |
| **#12** | Display — Session card + Tuning (Notch width/height) |
| **#13** | Sound — Enable/Volume, Session, Interactions, System (top) |
| **#14** | Sound — System, My Sounds, Quiet Hours, Filters (scrolled) |
| **#15** | Usage — Usage Limits + Claude Usage Bridge |
| **#16** | General — System, Expansion, Visibility, Dismissal (top) |
| **#17** | General — Visibility, Dismissal, Interaction (scrolled) |
| **#18** | Integrations — CLI Hooks list |
| **#19** | Notifications — Completion notifications, Quiet scenes, Built-in Filters, Blocked Launcher Apps (top) |

## Scope

**In scope (redesign to match):** General, Integrations, Notifications, Display,
Sound, Usage.
**Out of scope (do not touch this pass, per owner):** SSH Remote, Shortcuts, Labs,
Pass, About. Leave their sidebar entries and screens as-is.

> **Brand name (S1 resolved): the product is "Agent Island".** Substitute every
> "AgentPeek" / "Vibe Island" brand string in the mockups with **"Agent Island"** —
> body copy (e.g. the Usage-bridge text), the default sound-pack label, and any
> chrome. The sample repo "vibe-island" inside the Display preview card is mock
> session data (illustrative), not chrome — leave preview sample text as-is.

---

## Global settings-window visual language (applies to every section)

From #9–#19 the window is a standard two-pane macOS Settings layout, dark theme,
**SF Pro sans** (not monospaced — contrast with the overlay). Monospace appears
only for path/prompt preset *values* and inside preview cards.

**Sidebar (left):**
- [ ] AC-G-1: Dark sidebar, translucent, with a **rounded colored app-style icon**
      per row + label. Icons/colors as shown: General = gray gear, Integrations =
      blue plug/puzzle, Notifications = red bell, Display = purple "AA", Sound =
      green speaker, Usage = pink/red gauge (#9–#19 left rail).
- [ ] AC-G-2: The **in-scope** rows form the top group (General, Integrations,
      Notifications, Display, Sound, Usage) with no visible group header (the
      screenshots show no "Preferences" header — the code currently renders one;
      match the screenshot). Below them, the existing "Advanced" (and any lower)
      groups keep their small gray header style. **Do not add or rename out-of-scope
      sidebar entries** (SSH Remote / Pass / About shown in the mockup are out of
      scope — leave the current set as-is). Group headers are small gray
      uppercase-ish labels (#16 left rail).
- [ ] AC-G-3: The selected row is highlighted with a lighter rounded-rect fill
      (e.g. Display selected in #10/#11/#12).

**Detail pane (right):**
- [ ] AC-G-4: Near-black pane. Each screen has a header = the section's colored
      icon + bold title (e.g. red bell + "Notifications" #9; purple "AA" +
      "Display" #10; green speaker + "Sound" #13).
- [ ] AC-G-5: Settings are grouped into **rounded dark cards** (`≈#1C1C1E` fill,
      radius `≈10`) with **hairline dividers** between rows inside a card. Related
      rows share one card (e.g. the three Session sounds in #13 share a card).
- [ ] AC-G-6: **Section subheaders** are gray, bold, small (e.g. "System",
      "Expansion", "Visibility", "Dismissal", "Interaction" in #16/#17; "Custom
      Filters: Directory" in #9). Order and wording match the images exactly.
- [ ] AC-G-7: Row anatomy: leading white **label**, optional gray **description
      subline** under it, trailing **control** (toggle / slider+value-pill / select
      with up-down chevrons / segmented / play button). Descriptions match the
      images verbatim (they are quoted per-row below).
- [ ] AC-G-8: Controls — toggles are iOS-style, **blue when ON** in Settings
      (system blue) *(note: onboarding used green; Settings uses blue — match each
      screenshot)*; sliders are blue with faint tick dots and a right-aligned value
      pill (e.g. "90pt", "0.15s"); pickers show the value + up/down chevron glyph.

---

# Sections

Each row below is: **exact label** — *"exact description subline if any"* — control
type — default/shown state. `[EXISTS/NEW]` tags are finalized in the "Code mapping"
section at the bottom once the code audit lands; treat the visual ACs as fixed.

## 1. General (#16, #17)

**System**
- [ ] AC-1-a: **"Launch at Login"** — toggle — shown OFF (#16).

**Expansion**
- [ ] AC-1-b: **"Expand notch on hover"** — toggle — ON (#16).
- [ ] AC-1-c: **"Hover duration"** — slider with value pill **"0.15s"** (#16).
- [ ] AC-1-d: **"Smart suppression"** — *"Don't auto-expand when the agent's
      terminal tab is in focus"* — toggle — ON (#16).

**Visibility**
- [ ] AC-1-e: **"Hide in fullscreen"** — toggle — ON (#16/#17).
- [ ] AC-1-f: **"Auto-hide when no active sessions"** — toggle — ON (#16/#17).

**Dismissal**
- [ ] AC-1-g: **"Auto-collapse on mouse leave"** — toggle — ON (#16/#17).
- [ ] AC-1-h: **"Auto reveal dwell"** — stepper/select showing **"5s"** —
      *"How long the panel stays open for completion and warning reveals. Press ESC
      to close sooner."* (#17).
- [ ] AC-1-i: **"Dismiss auto reveal on outside click"** — toggle — OFF —
      *"Clicking anywhere outside the notch panel immediately closes completion and
      warning reveals, ignoring the remaining dwell time."* (#17).
- [ ] AC-1-j: **"Idle session cleanup"** — select showing **"2 hours (default)"** —
      *"Applies only to sessions without a clear close signal (Codex, OpenCode,
      Cursor)."* (#17).

**Interaction**
- [ ] AC-1-k: **"Disable click-to-jump"** — toggle — OFF — *"When enabled, clicking
      a session won't switch to its terminal or IDE."* (#17).

## 2. Integrations (#18) — "CLI Hooks"

- [ ] AC-2-a: Section subheader **"CLI Hooks"**. A single card containing a **row
      per agent**, each: agent name (white) on the left, a **status** in the middle-
      right, and an **enable toggle** (blue when ON) on the far right (#18).
- [ ] AC-2-b: Status variants shown, reproduce all three:
      - **green check + "Active"** (Claude Code, OpenCode, Gemini CLI, Cursor Agent,
        Droid, Grok Build, Kimi Code, Copilot, Copilot (VS Code Agent), Pi Agent,
        Oh My Pi, Amp).
      - **amber ⚠ + "Needs authorization"** with an **"Authorize"** amber button
        (Codex).
      - **amber ⚠ + "Activate"** amber button (Hermes).
      - **green check + "Hook file ready"** with an ⓘ info glyph (Trae).
- [ ] AC-2-c: **Scope (S6): render only the agents Agent Island actually
      supports** — **Claude Code** is first; Codex and Cursor already exist; the
      other agents are future expansion. Do **not** show unsupported agents as fake
      "Active". When an agent is present, keep the mockup's top-to-bottom order
      (Claude Code, Codex, OpenCode, Gemini CLI, Cursor Agent, Trae, Droid, Grok
      Build, Kimi Code, Copilot, Copilot (VS Code Agent), Hermes, Pi Agent, Oh My
      Pi, Amp).
- [ ] AC-2-d: A trailing **"＋ Add CLI Branch…"** action row (blue, with ⊕ icon) at
      the bottom of the list (#18).

## 3. Notifications (#19, #9)

**Completion notifications**
- [ ] AC-3-a: **"Expand the panel for completion notifications"** — toggle — ON —
      *"Turn off to keep the panel collapsed and show a subtle glow instead.
      Approvals and questions still expand automatically."* (#19).
- [ ] AC-3-b: **"Subagent & Agent Team notifications"** — select showing **"As the
      main agent res…"** (truncated) — *"Choose when completion notifications
      appear. Approvals and questions always appear immediately."* (#19).

**Quiet scenes** — intro text *"Stays quiet while any scene below is active — no
auto-expand, no sound, approvals included. A subtle dot still marks completions."*
- [ ] AC-3-c: Three toggle rows with **leading glyphs**, all OFF (#19):
      **"🌙 Focus mode"**, **"🔒 Screen locked or asleep"**, **"◉ Screen recording or
      sharing"**.

**Built-in Filters**
- [ ] AC-3-d: **"Codex internal workers"** (with ⓘ) — toggle — ON —
      *"Preset directory and prompt filters appear in the matching sections
      below."* (#19).

**Blocked Launcher Apps**
- [ ] AC-3-e: Section **"Blocked Launcher Apps"** — *"Drop sessions launched by
      selected apps before they appear in Agent Island."* — a list/picker of apps (#19,
      partially cut off — confirm full control).

**Custom Filters: Directory** (#9)
- [ ] AC-3-f: Intro *"Hide any session whose working directory contains:"*.
- [ ] AC-3-g: A **text input** (placeholder *"e.g. /chronicle/dev-experiments"*) +
      a disabled-until-typed **"Add Pattern"** button, with helper *"🔍 Type a
      pattern to preview matches"* under it (#9).
- [ ] AC-3-h: **Preset filter rows**, each: folder glyph, name, a blue **"Preset"**
      badge, a **"Contains · <path>"** subline (path in **monospace**), an ⓘ glyph,
      and a toggle (ON). Reproduce the three shown: "Codex Memory Writer (cwd)" ·
      `/.codex/memories`; "Codex Chronicle Memory Summary" · `/chronicle/screen_recording`;
      "Claude-Mem plugin background sessions" · `/.claude-mem` (#9).
- [ ] AC-3-i: Tip line *"Tip: right-click a session card to add its directory as a
      filter."* (#9).

**Custom Filters: First Prompt** (#9)
- [ ] AC-3-j: Intro *"Hide any session whose first user prompt starts with:"*.
- [ ] AC-3-k: **"Match type"** row with a select showing **"Starts with"** (#9).
- [ ] AC-3-l: Text input (placeholder *"e.g. ## Memory Writing Agent"*) + "Add
      Pattern" + the same preview helper (#9).
- [ ] AC-3-m: Preset rows with an **"AI" text glyph**, name, "Preset" badge, a
      **"Prefix · <text>"** subline (monospace), ⓘ, toggle ON. Reproduce the three:
      "Codex Memory Writer (prompt prefix)" · `## Memory Writing Agent`; "Codex App
      suggested prompts" · `# Overview Ge…rsonalized suggestions`; "Codex App Git
      helper prompts" · `Using the sup…ontext below, generate` (#9).

## 4. Display (#10, #11, #12)

**Notch**
- [ ] AC-4-a: A **live notch preview** at the top — a black rounded notch pill over
      a desktop-wallpaper thumbnail, showing sample content "▦▦ Running … 7 sessions"
      (#10). It reflects the Clean/Detailed choice below.
- [ ] AC-4-b: A **segmented pair of preview cards**, **"Clean"** (*"More space for
      menu bar"*) and **"Detailed"** (*"Session titles & status at a glance"*), each
      a mini notch mock; the selected one has a **blue border** (Detailed selected
      in #10).
- [ ] AC-4-c: **"Display"** picker — value **"Main Display"** + up/down chevron
      (choose which screen the notch renders on) (#10).

**Panel size**
- [ ] AC-4-d: **"Content Font Size"** — select — **"11pt (Default)"** (#10).
- [ ] AC-4-e: **"Completion Card Height"** — slider — value pill **"90pt"** (#10).
- [ ] AC-4-f: **"Max Panel Height"** — slider — **"560pt"** (#10).
- [ ] AC-4-g: **"Max Panel Width"** — slider — **"640pt"** (#10/#11).

**Session card**
- [ ] AC-4-h: Toggles, all ON (#11/#12): **"Show Project Name"**, **"Show
      Worktree"**, **"Show AI Model"**, **"Show Subagents"** (*"Hide fan-out Task
      subagents to keep the panel clean and fast. Agent Teams and Codex stay
      visible."*), **"Show Agent Activity Detail"**.
- [ ] AC-4-i: A **live session-card preview** below the toggles (#11/#12): a black
      card "● vibe-island ⌥ chat-ui · Refa…" with pills **[Claude][Opus 4.8][Ghostty]**,
      "You: extract chatEndpoint into a transport-agnostic layer", "Editing
      chatEndpoint.ts · 12s", a "⑂ Agents (2)" group, "● Explore (Search API
      endpoints) 8s / └ Grep: handleRequest", "● Explore (Read config files) Done".
      The preview updates as the toggles above change.

**Tuning**
- [ ] AC-4-j: **"Notch width"** — slider — **"0pt"** (#12).
- [ ] AC-4-k: **"Notch height"** — slider — **"0pt"** — *"Fine-tune notch
      dimensions if your machine doesn't fit perfectly. 0 uses the macOS API
      value."* (#12).

## 5. Sound (#13, #14)

- [ ] AC-5-a: **"Enable Sound Effects"** — toggle — ON (#13).
- [ ] AC-5-b: **"Volume"** — slider with speaker glyphs at each end + a **"30%"**
      value label (#13).

**Session** — each row: bold label, gray description, a **sound picker** (dropdown
showing the sound name) + a circular **▶ play/preview** button.
- [ ] AC-5-c: **"Session Start"** — *"New Claude / Codex / Gemini session"* — picker
      **"Agent Island"** (#13).
- [ ] AC-5-d: **"Task Complete"** — *"AI finished its turn"* — **"Agent Island"** (#13).
- [ ] AC-5-e: **"Task Error"** — *"Tool failure or API error"* — **"Agent Island"** (#13).

**Interactions**
- [ ] AC-5-f: **"Approval Needed"** — *"Permission or question pending"* — **"Agent
      Island"** (#13).
- [ ] AC-5-g: **"Task Acknowledge"** — *"You submitted a prompt"* — **"Off"** (#13).

**System**
- [ ] AC-5-h: **"Context Limit"** — *"Context window almost full"* — **"Agent Island"**
      (#13/#14).
- [ ] AC-5-i: **"Idle Reminder"** — *"AI is waiting for your input"* — **"Off"** (#14).
- [ ] AC-5-j: **"Spam Detection"** — *"3+ prompts in 10 seconds"* — **"Off"** (#14).

**My Sounds**
- [ ] AC-5-k: Empty state **"No imported sounds yet."** + a **"＋ Add Sound…"**
      action row (#14).

**Quiet Hours**
- [ ] AC-5-l: **"Silence during quiet hours"** — toggle — OFF — *"Mutes all sounds
      during the selected time range (crosses midnight if end is earlier than
      start). Useful when agents run overnight."* (#14). *(When ON, a start/end time
      range appears — confirm control, Open Question S2.)*

**Filters**
- [ ] AC-5-m: **"Auto-detect probe sessions"** — toggle — ON — *"Automatically mutes
      health-check sessions (e.g. CodexBar ClaudeProbe)"* (#14).

> Sound-picker options: each picker lists the available sound packs plus
> **"Off"**. The default pack reads "Vibe Island" in the mockups → render as
> **"Agent Island"** (S1). Enumerate the full option set from the design source
> (Open Question S3).

## 6. Usage (#15)

**Usage Limits**
- [ ] AC-6-a: **"Show Usage Limits"** — toggle — ON — *"Display subscription usage
      limits in the notch panel header"* (#15).
- [ ] AC-6-b: **"Display Value"** — select — **"Used"** (options: Used / Remaining)
      (#15).
- [ ] AC-6-c: **"Preferred Provider"** — select — **"Auto (follow session)"** (#15).

**Claude Usage Bridge**
- [ ] AC-6-d: Section **"Claude Usage Bridge"** with body *"Agent Island will add a
      small bridge to your existing Status Line setup so it can read Claude usage
      data. Your visible Status Line output stays the same."* and a **blue "Connect
      usage" button** (#15).

---

## Code mapping — EXISTS vs NEW (from code audit)

**The six sections already exist 1:1** — shell `AgentIslandSettingsView`
(`AtlasSettingsShell.swift:6`), dispatcher `AtlasSettingsDetail`
(`AtlasSettingsSections.swift:5`), destinations `AtlasSettingsDestination`
(`AtlasSettingsModels.swift:7`). So this is **restyle + reword + fill the gaps**,
not a new settings shell.

Three cross-cutting rules for the implementer:
1. **Reuse the field.** Where a control is `EXISTS`, keep its backing field and
   just re-label / re-shape the control (often the current label differs, or it's a
   picker where the target wants a toggle). **Do not create duplicate preference
   state.**
2. **Build UI over existing model** where it's `PARTIAL` (the domain model already
   holds the value; only the control is missing).
3. **Some controls move sections.** e.g. "Expand the panel for completion
   notifications" lives in **General** today (`revealOnCompletion`) but the target
   puts it in **Notifications**.

Legend: **EXISTS** = field + control present (restyle/reword) · **PARTIAL** = model/
field exists, no matching control (build the UI) · **NEW** = net-new feature (no
backing model).

### General — `AtlasGeneralSection` (`AtlasSettingsSections.swift:93`)
| Target control | Status | Current label / field |
|---|---|---|
| Launch at Login (toggle) | EXISTS | picker "Launch behavior" → `AtlasGeneralPreferences.launchBehavior` (`.launchAtLogin`). **Reshape picker→toggle.** |
| Expand notch on hover | EXISTS | "Expand on hover" → `expandOnHover` |
| Hover duration (slider) | **NEW** | no `hoverDuration` field |
| Smart suppression | EXISTS | "Suppress for exact foreground Host" → `suppressWhenExactHostForeground`. **Reword + change subline.** |
| Hide in fullscreen | EXISTS | "Hide in full screen" → `hideInFullScreen` |
| Auto-hide when no active sessions | EXISTS | "Hide with no active Agent Session" → `hideWhenNoActiveSession` |
| Auto-collapse on mouse leave | EXISTS | "Collapse on pointer exit" → `collapseOnPointerExit` |
| Auto reveal dwell (5s) | PARTIAL | dwell constants exist (`AlertCandidateClass.defaultDwell`); no user setting |
| Dismiss auto reveal on outside click | **NEW** | — |
| Idle session cleanup (2h) | **NEW** | — |
| Disable click-to-jump | EXISTS | picker "Click behavior" (Inspect/JumpBack) → `clickBehavior`; `.inspectExpand` = jump disabled. **Reshape picker→toggle; confirm semantics.** |

### Integrations — `AtlasIntegrationsSection` (`AtlasSettingsSections.swift:196`)
| Target | Status | Detail |
|---|---|---|
| Agent roster | **scoped: Claude first (S6)** | `AtlasIntegrationKind` (`AtlasIntegrationModels.swift:4`) has 3: Claude Code, Codex CLI, Cursor. **Build/verify Claude Code first**; Codex + Cursor already exist; the other 12 are deferred future expansion (each a net-new adapter). Render only supported agents — never fake "Active". |
| Per-agent enable toggle | EXISTS | `AtlasIntegrationsSection.swift:242` → `AtlasIntegrationState.enabledIntent` |
| Status badge (Active / Needs authorization / Hook file ready) | PARTIAL | status is plain `LabeledContent` text, not a badge; enums exist (`AtlasIntegrationSummary`, `AtlasIntegrationAuthentication`, `AtlasIntegrationHealth`). **Build badge UI.** |
| Authorize / Activate buttons | PARTIAL | auth is a model enum, no wired action button (current buttons are "Install hooks" / "Verify session"). **Build the authorize action + button.** |
| Add CLI Branch… | **NEW** | — |
| Sidebar label | note | currently **"Integrations"**; target header reads **"CLI Hooks"** as the section subheader (keep sidebar item "Integrations"). |

### Notifications — `AtlasNotificationsSection` (`AtlasSettingsSections.swift:287`)
*Currently a read-only preview with 2 toggles; almost every target control is a new UI over an existing domain model.*
| Target | Status | Detail |
|---|---|---|
| Expand panel for completion notifications | EXISTS (in **General**) | `revealOnCompletion` ↔ `NotificationPolicy.revealCompletion`. **Move into Notifications.** |
| Subagent & Agent Team notifications (select) | PARTIAL | `AlertCandidateClass.childCompletion` + `showSourcedChildCompletion`; no select |
| Quiet scenes: Focus / Locked-asleep / Recording (3 toggles) | PARTIAL | `QuietScene.focusMode/.lockedDisplay/.asleep/.screenRecordingOrSharing` are runtime scene inputs, not settings toggles. **Build toggles.** |
| Codex internal workers (toggle) | PARTIAL | `AlertCandidateFilterPolicy.showBuiltInInternalWork` via `NotificationPolicySettingsModel.setFilter`; no UI |
| Blocked Launcher Apps (list) | PARTIAL→NEW | only a single bool `showLauncher`; no per-app blocklist model. **New storage + picker.** |
| Custom Filters: Directory (pattern system) | **NEW** | only bool `showDirectory`; no pattern list / preview |
| Custom Filters: First Prompt (pattern + match-type) | **NEW** | only bool `showFirstPrompt`; no pattern / match-type storage |

### Display — `AtlasDisplaySection` (`AtlasSettingsSections.swift:320`)
| Target | Status | Current label / field |
|---|---|---|
| Notch live preview | PARTIAL | generic `AtlasPreviewSurface` exists, not notch-shaped. **Build notch preview.** |
| Clean / Detailed segmented cards | EXISTS | picker "Collapsed layout" → `collapsedLayout`. **Reshape picker→segmented preview cards.** |
| Display picker (Main Display) | EXISTS | "Selected display" (`AppDelegate.swift:837`) → `selectedDisplayID` |
| Content Font Size (11pt) | PARTIAL | picker is Small/Med/Large scale enum `contentSize`, **not pt**. **Convert to pt-valued control (or relabel).** See S4. |
| Completion Card Height (slider) | EXISTS | "Completion-card height" → `completionCardHeight` |
| Max Panel Height (slider) | EXISTS | "Maximum panel height" → `maximumPanelHeight` |
| Max Panel Width (slider) | EXISTS | "Maximum panel width" → `maximumPanelWidth` |
| Show Project Name | EXISTS | "Project metadata" → `showProjectMetadata` |
| Show Worktree | EXISTS | "Worktree metadata" → `showWorktreeMetadata` |
| Show AI Model | EXISTS | "Model metadata" → `showModelMetadata` |
| Show Subagents | EXISTS | "Subagent Run metadata" → `showSubagentRunMetadata` |
| Show Agent Activity Detail | EXISTS | "Activity metadata" → `showActivityMetadata` |
| Session-card live preview | PARTIAL | generic preview, not a session-card mock. **Build card preview.** |
| Notch width / height sliders | **NEW** | no notch-dimension fields |

### Sound — `AtlasSoundSection` (`AtlasSettingsSections.swift:482`)
*Master toggle/volume/quiet-hours exist; every per-event picker+play is PARTIAL (model present, no UI).*
| Target | Status | Detail |
|---|---|---|
| Enable Sound Effects | EXISTS | "Sound enabled" → `SoundPolicy.masterEnabled` |
| Volume | EXISTS | `SoundPolicy.volume` |
| Per-event sound pickers + play (Session Start / Task Complete / Task Error / Approval Needed / Task Acknowledge / Context Limit / Idle Reminder / Spam Detection) | PARTIAL | classes in `AlertCandidate.swift`; per-class selection `SoundPolicy.selectionByClass`; `selectSound`/`previewSound` exist. **Build per-row picker + ▶.** |
| My Sounds (import list + Add Sound) | PARTIAL | `SoundPolicy.assets`, `register`/`remove`, `LocalSoundAsset`. **Build list + import UI.** |
| Silence during quiet hours (toggle) | EXISTS | "Quiet hours" → `quietHoursEnabled` |
| Quiet Hours time range | PARTIAL | `QuietHours.startMinute/endMinute`; no time-range control |
| Auto-detect probe sessions | PARTIAL | `AlertCandidateFilterPolicy.showProbe` via `setFilter`; no UI |

### Usage — `AtlasUsageSection` (`AtlasSettingsSections.swift:44`)
| Target | Status | Current label / field |
|---|---|---|
| Show Usage Limits | EXISTS | "Show Usage Snapshots" → `UsageDisplayPreferences.isVisible` |
| Display Value (Used/Remaining) | EXISTS | "Display" → `valueKind` |
| Preferred Provider (Auto/specific) | EXISTS | "Provider" → `providerSelection` |
| Claude Usage Bridge + Connect usage | **NEW** | no bridge/connect UI or field today |

### Biggest net-new efforts (call these out for planning)
1. **Additional CLI-Hook agent adapters** (Integrations) — **deferred** (S6: Claude first, rest expand later). Near-term work is Claude Code only; each future agent is a net-new backend adapter.
2. **Custom-filter pattern systems** (Notifications: Directory + First Prompt) — new storage, preset seeding, live match preview.
3. **Claude Usage Bridge / Connect usage** flow (Usage) — and the multi-window
   usage data it feeds (`5H/7D/MO` per provider), which is the same data gap as the
   overlay stats row (see `overlay-visual-redesign.md` §1.4).
4. **Per-event sound picker + preview UI** and **My Sounds import** (Sound) — UI over an existing model.
5. New General controls: hover duration, auto-reveal dwell, dismiss-on-outside-click, idle-session-cleanup.

---

## Open questions

- **S1 — RESOLVED:** product name is **"Agent Island"**; substitute "AgentPeek" /
  "Vibe Island" brand strings accordingly (see the brand note near the top).
- **S2 — CUT: no Quiet Hours.** Do not build the Quiet Hours setting or its
  start/end range control.
- **S3 — CUT: no sound packs.** Do not build selectable sound packs. *(If a sound
  on/off toggle already exists and ships today, leave it as-is — this cuts the
  **pack picker**, not existing behavior. Confirm if ambiguous.)*
- **S4 — Selects' full option lists:** "Subagent & Agent Team notifications",
  "Auto reveal dwell", "Idle session cleanup", "Content Font Size", "Display",
  "Preferred Provider" — enumerate every option from the design source.
- **S5 — "Blocked Launcher Apps"** and **"Add CLI Branch…"** full interaction (the
  picker / add-flow) is not fully visible in the captures.
- **S6 — RESOLVED:** **Claude Code is the first and only agent in scope now**; the
  rest are future expansion. Integrations renders the supported set (Claude Code
  first; Codex + Cursor already exist) — do **not** fabricate the other agents as
  "Active"; the roster grows as adapters ship.

## Definition of done
- [ ] Each in-scope section (General, Integrations, Notifications, Display, Sound,
      Usage) matches its cited screenshot(s) row-for-row: labels, descriptions,
      control types, default states, section order — verified by side-by-side image
      comparison.
- [ ] Sidebar grouping/icons and the global card/row/toggle/slider language (AC-G-*)
      are consistent across all six sections.
- [ ] Out-of-scope items (SSH Remote, Shortcuts, Labs, Pass, About) are untouched.
- [ ] Existing bindings are reused (see Code mapping); no duplicate preference state
      is introduced for a setting that already has a model field.
- [ ] `swift build` succeeds from `src/`.
</content>
