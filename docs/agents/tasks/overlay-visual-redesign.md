# Implementation task: redesign the Island overlay to match the reference design

## Golden rule — read this first

**The eight reference screenshots ARE the specification. Do not invent UI.**

A previous attempt at this task failed because the implementer applied their own
visual taste instead of reproducing the reference design. Every visual decision
in this document traces to a specific reference image. When implementing:

- If a detail is shown in a reference image, reproduce it **as shown** — wording,
  iconography, layout order, color, weight, casing.
- If a detail is **not** shown in any reference image, do **not** design it from
  imagination. Flag it as an open question (see the "Open questions" section) and
  match the nearest reference, or leave the existing behavior unchanged.
- "Looks clean / modern / native" is **not** an acceptance criterion. "Matches
  Image #N" is. Every AC below is phrased as a checkable, observable statement.
- Acceptance is verified by **visual comparison against the reference image**, not
  by "the code compiles."

Exact colors/measurements below are eyeballed from the mockups and marked
`≈`. Where the original design source (Figma/mockup file) exists, **sample the
exact values from it** and treat those as authoritative over the `≈` values here.

---

## Reference image index

| Ref | What it is | Role |
|-----|-----------|------|
| **#1** | Current shipping overlay: two washed-out translucent gray pills on the notch — left "✦ 5 ⌄ / …", right "⌄ Inspect / Expand" | **The "before" we are replacing.** |
| **#2** | Target — expanded panel, empty state: header "0 Sessions" + multi-agent stats + menu/gear, body "AgentPeek · waiting for sessions". *(Its trial banner is CUT — §1.8.)* | Target |
| **#3** | Target — onboarding welcome (app icon, "AgentPeek", "Your coding agents, in the Mac notch", "Get started") | Target (Phase 2) |
| **#4** | Target — onboarding "Which agents do you use?" 3-column agent grid + "Continue" | Target (Phase 2) |
| **#5** | Target — onboarding "Connect an agent", 2-column install cards with spinners | Target (Phase 2) |
| **#6** | Target — onboarding "A few preferences" (Notifications, Launch at login toggles) | Target (Phase 2) |
| **#7** | Target — collapsed notch pill: "▦ Waiting on 2 subagents" … "2 Sessions" | Target |
| **#8** | Target — expanded panel, permission request: activity row, "PERMISSION REQUESTED", curl code block, Deny/Allow | Target |
| **#9** | Target — expanded panel, **populated multi-session list** (2 sessions): header stats `5H:24% 7D:21%`, dense session rows (model/branch/tokens/context/mem/disk/cost/diff + launching-app icon). *(pasted in chat as #22)* | Target |
| **#10** | Target — **focused single session**: detailed usage header (`5h 24% 2h14m │ 7d 21% 3d5h`, green), rich card (agent message body + "You:" prompt + scrollable transcript + `⌃G` jump). *(Its "Unlock full control" paywall banner is CUT — §1.11.)* | Target |
| **#11** | Target — **collapsed notch pill** (out of focus): gray pixel-grid glyph + active agent **"Claude"** (amber) + green activity glyph … right-aligned **"9 Sessions"**; soft gray gradient wings at the outer edges. *(pasted in chat as #24)* | Target |
| **#12** | Target — **hover → expanded** overlay in real context: stats header with a **"View usage details"** hover tooltip; session rows whose activity line is a **green status** (`💬 Claude is waiting for your input`). *(pasted in chat as #25)* | Target |
| **#13** | Target — **menu-bar popover** (click the menu-bar icon): per-provider usage detail (Claude/Codex/Cursor/OpenCode) with % used, green progress bars, reset/refill times, token/cost, and an "Active / Metrics" toggle. *(pasted in chat as #26)* | Target |
| **#14** | ⚠ **Partly stale build** — `AskUserQuestion` card: header "2 Sessions" + stats cluster + ☰ + ⚙; activity row; "● QUESTION PENDING" + "Answer in terminal"; questions **stacked** with radio options; "0 of 3 answered" + "Send". | **Mixed — read the note** |
| **#15** | Target — **menu-bar popover, "Metrics" tab** (the other half of #13): per-provider cards with a token total, usage histogram, input/output/cache-read breakdown, and a per-model split; "Active / Metrics" toggle with **Metrics** selected. | Target (§1.12) |
| **#16** | Target — **permission request, live build**: header "3 Sessions" + stats; activity row "Waiting to run curl -L …" · `niche-radar` · `5m` · `esc`; "● PERMISSION REQUESTED"; wrapped `$` command block; **Deny ⌘N** / **Allow ⌘A**; "Deny with feedback" / "Open Terminal ⌥T". | Target (§1.7) — **confirms the spec** |
| **#17** | **Content reference — multi-select question.** Header chip "Weekend" + ✕; question; 4 options each with a **square checkbox** + bold label + description; an "Other" option; footer "**1** Submit answers"; "Esc to cancel". ⚠ *This is Claude Code's own IDE rendering, not the overlay.* | Target (§1.13) — **content, not styling** |
| **#18** | Target — **focused session overlay, newest live build**: detailed usage header `☀ 5h 53% 8m │ 7d 25% 3d3h` + 🔊 + ⚙ (**no hamburger**); session card `agent-island · Create sample multi-select question w…` + pills `Claude` `Opus 4.8` `Cursor` `2m`; "You:" line. *(Its paywall banner + "with a license" footer are CUT — §1.11.)* | Target (§1.4/§1.10) — **confirms both specs** |

> **#17 + #18 compose into one screen.** Per the design intent: **#18 is the overlay
> shell** (usage header + focused session card + "You:" line), and **#17's question
> content renders directly below it, inside the same overlay** — not in a separate
> window. #17 shows *what* to render; the overlay's monospaced/opaque language governs
> *how*.
>
> **#18 is the newest capture and it has NO hamburger** — only the mute toggle and
> gear. That independently corroborates **Q11** and confirms #14/#16 were older builds.

> ### ⚠ How to read #14 — it is a real build, and parts of it are wrong
>
> #14 is a photograph of a working app, so its **surface, monospaced type, spacing,
> owning-session activity row, and amber attention label are trustworthy** and are the
> best evidence in this document for those things.
>
> But three details in it were reviewed and **rejected**:
> - the **stacked** question form → the **paginated wizard** wins (Q10)
> - the **hamburger** in the header → **stays out** (Q11, AC-1.3-c)
> - *(its Codex blue-violet mark was **accepted** — that one is right, Q7)*
>
> **Use #14 for the shell, never for the question form or the header icons.**

**Priority for this pass: Phase 1 (the overlay — #1→#2/#7/#8).** Phase 2
(onboarding — #3–#6) is documented so nothing is lost, but is secondary.

**Brand name (resolved): the product is "Agent Island".** The mockups render
"AgentPeek" (empty state #2, onboarding #3–#5); wherever that brand string appears
in UI copy, render **"Agent Island"** instead. (Image-index rows above quote the
raw screenshots verbatim.)

---

## Product principle: the overlay shows what the agent is actually doing

**Agent Island surfaces real agent activity — permission requests and questions —
from hooks, and lets the person act on them.** Showing a redacted summary where the
mockups show real content is a **failure**, not a safe default.

> **Not in scope: code changes.** Rendering diffs or changed-line content is **not a
> requirement.** The `+879 −44` diff *stat* in AC-1.6-c stays (it is metadata shown in
> #9); no diff *content* is ever rendered.

This is stated here because the codebase contains **increment-boundary comments from
an earlier observation-only phase** that read like permanent prohibitions and have
already misled one pass of this work:

| Comment you will encounter | What it actually means |
|---|---|
| `GuidedAttentionEvidence`: *"Interaction Content is intentionally refused… metadata-only request summary"* | Scopes **that one record**, from the observation-only slice. Not a system-wide ban. |
| `EventFamily`: *"only the families needed for an observation-only vertical slice"* | An early increment boundary — expected to grow. |
| `ClaudeLiveCallback`: *"neither Codable nor durable"* | A **security** property of action authority (anti-replay), not a display restriction. |

**The supported path already exists:** `PayloadClassification.interactionContent`
is a first-class category, `ClaudeCodeAdapter` already emits it, `SessionStore`
accepts it, and `SessionHistory.receivedContent` retains it per session.

**Rule for implementers:** if a mockup shows real content and a model can't carry it,
**extend the model** — do not downgrade the UI. Where that widens what a record holds,
write it up (see the ADR note below).

> ⚠ **`docs/adr/` does not exist**, though `CLAUDE.md` points at it for system-wide
> decisions. The content-in-attention change and the transcript-reading approval are
> both worth recording; someone needs to create that directory or say where ADRs live.

---

## Delivery phases — read this before picking up any section

**The split is by direction of communication, not by difficulty.**

> **Phase 2 is anything bidirectional** — where the person answers and Agent Island
> **sends a response back to the agent** (Claude / Codex / Cursor): permission
> Allow/Deny, question answers, multi-select, and free-text replies.
>
> **Phase 1 is everything else** — observing agent state and rendering it. **The
> overlay watches; it does not talk back.**

| Phase | Sections | ACs | Nature |
|-------|----------|-----|--------|
| **1 — Display** | §1.1 surface · §1.2 collapsed pills · §1.3 header · §1.4 usage stats · §1.5 empty state · §1.6 session rows · §1.9 (no-op) · §1.10 focused card · §1.12 menu-bar popover | **50** | Read-only. Renders observed state. |
| **1B — Onboarding** | §2.1–§2.4 | **11** | Not bidirectional, so Phase 1 by the rule — but a **secondary track**; do it after the overlay. |
| **2 — Bidirectional** | **§1.7 permission card** · **§1.13 AskUserQuestion wizard** | **19** | Person answers → response is sent back to the agent. |
| **CUT** | §1.8 trial banner · §1.11 paywall | — | No monetization ships. |

**Why §1.7 and §1.13 are both Phase 2:** each terminates in a write back to the agent
— `ClaudeTypedHookResponse.permission(...)` and `.preToolAllow(updatedInput:)`. Every
other section terminates at the screen. **These two ship together**; they share the
same action contract, the same ownership/staleness guards, and the same components.

### What a blocked session looks like in Phase 1

**Row-level status only — no card, no buttons.** A blocked session still reads clearly
in the list via §1.6:
- `Waiting to run curl -L …` in dim gray, or `💬 Claude is waiting for your input` in
  green (AC-1.6-d);
- the state-tinted pixel glyph — blue/steel when awaiting permission (AC-1.6-e);
- the `esc` hint at the row's trailing edge (AC-1.6-f).

That tells the person *which* session needs them; they act in the terminal. **Do not
build a card that shows a permission or question with no way to answer it** — a
buttonless card is worse than the row status, because it implies an action that isn't
there.

> ⚠ **Correction to an earlier draft:** it claimed the amber "PERMISSION REQUESTED"
> label and the elevated `$` code block were "Phase 1 anyway because §1.6 uses them."
> **They are not** — §1.6 uses only the activity row and glyph tints. Those two
> components belong entirely to §1.7, so they are **Phase 2**, and Phase 2 is real
> component work, not just wiring.

---

## Source to copy from: `agent-notch`

A sibling repo, **`/Users/abhishekthakur/Developer/agent-notch`**, already ships a
working overlay in this exact visual language — opaque black notch dropdown,
monospaced throughout, pixel-grid glyphs. **Copy from it rather than
reimplementing.** It is the closest thing we have to the design source, and its
values are *shipped and visually tested*, so where it disagrees with an eyeballed
`≈` value in this doc, prefer agent-notch (and note the deviation).

**What it is:** a single **933-line `main.swift`**, no package manifest — built with
`swiftc -O main.swift`. Everything lives in that one file; line references below are
into it.

**It is a different product.** agent-notch reads session state by polling CLI
transcript files (`~/.claude/projects/**/*.jsonl`, `~/.codex/sessions/**/*.jsonl`)
every 2s; Agent Island uses hooks. **Take only the presentation layer** — the
drawing, layout, typography, geometry, and animation. Do **not** port
`SessionScanner` (`:27–212`), `tailInfo`, `extractText`, `extractUserPrompt`, or
`codexMeta` — Agent Island already has a richer, source-proven session model.

### ⚠ The one integration constraint: AppKit vs SwiftUI

agent-notch's overlay is **pure AppKit** — `NSView.draw(_:)` with CoreGraphics, and
`NSStackView` for layout. Agent Island's overlay is **SwiftUI**, hosted in an
`NSHostingView<IslandOverlayView>` ([IslandOverlayPanel.swift:87](../../../src/Sources/AgentIslandApp/IslandOverlayPanel.swift#L87)).
So "copy" means two different things depending on the piece:

- **Pixel-drawing views** (`DitherIconView`, `IndicatorView`, `DitherSeparator`) —
  **copy the `draw(_:)` bodies verbatim** and wrap each in an `NSViewRepresentable`.
  Do not attempt to re-express dithered sub-pixel fills as SwiftUI shapes; the noise
  function, cell sizes, and alpha ramps are the look, and they are tuned.
- **Layout** (`SessionListController`, row builders) — **translate** the anatomy and
  the constants (sizes, weights, spacings, insets, colors) into SwiftUI. Don't port
  `NSStackView` trees.
- **Window/geometry/animation** (`AppDelegate`) — **reference**, and reconcile
  against Agent Island's existing `IslandOverlayModels`/`IslandOverlayController`,
  which already solve multi-display selection and hit-testing more thoroughly.

### Coverage map — what agent-notch does and does not give us

Triage index only. **Exact line numbers live in the `↩` callout inside each section
below — that is their single source of truth.** Don't copy them up here; they will
drift.

| Doc § | agent-notch symbols | Verdict |
|-------|--------------------|---------|
| **§1.1** surface | `NotchView.draw`, window setup | ✅ **Copy verbatim** (shape math) |
| **§1.1** open/close animation *(no AC today)* | `animatePanelLayer` | ✅ **Adopt** — see AC-1.1-f |
| **§1.2** pixel glyphs | `IndicatorView`: `mascotFrames`/`quadrants`, `drawCrab`, `drawGreenBlob`, `drawRing` | ✅ **Copy verbatim** behind `NSViewRepresentable` |
| **§1.2** notch geometry | `notchWidth`, `barHeight`, `collapsedFrame`, `expandedFrame`, `isFullscreenSpace` | 🔍 **Reference** — compare with our models |
| **§1.2** "N Sessions" text, wings | — | ❌ **Not present** — collapsed state is glyph-only, no text, no pill fill, no wings |
| **§1.3** header row | — | ❌ **Not present** — no header at all |
| **§1.4** usage stats cluster | — | ❌ **Not present** |
| **§1.5** empty state | `SessionListController` empty branch | ⚠ **Structure only** — copy is wrong; this doc's wording wins |
| **§1.6** row anatomy | `row(for:)`, mono `label()`, `DitherSeparator`, `relative()`, `DitherIconView` | ✅ **Copy** line 1 + helpers |
| **§1.6** metadata strip (line 2) | — | ❌ **Not present** — only model + relative time |
| **§1.6** subagent dropdown *(no AC today)* | disclosure toggle, `childRow` | ✅ **Adopt** — see AC-1.6-g |
| **§1.7** permission card | — | ❌ **Not present** |
| **§1.8** trial banner | — | ❌ **CUT** — no monetization |
| **§1.10** focused card | `"You: " + prompt` subtitle | ⚠ **Concept only** — one truncated line, no body/transcript |
| **§1.11** paywall | — | ❌ **CUT** — no monetization |
| **§1.12** menu-bar popover | — | ❌ **Not present** — agent-notch is `.accessory` with no status item |
| **§1.13** AskUserQuestion card | — | ❌ **Not present** — no interactive card at all; but our *action layer* already exists |
| **§2** onboarding | — | ❌ **Not present** |

**Bottom line: agent-notch covers the two make-or-break anchors** (opaque-black
notch surface, monospaced-everything) **plus the pixel-glyph vocabulary and the row
layout — roughly the whole "pure restyle" bucket.** Everything gated on data
(§1.4/§1.7/§1.10/§1.12) and all of Phase 2 is still net-new. §1.8 and §1.11 are cut.

### Harvested values (prefer these over the `≈` guesses above)

| Value | agent-notch | This doc's `≈` | Note |
|-------|-------------|----------------|------|
| Panel fill | `NSColor.black` `:666` | `#0A0A0C` | Near-identical; **pick one and put it in the theme file** |
| Panel radius | `16` `:657` | `≈20` | ✅ **RESOLVED: use `18`** — matches our existing hit-test path, so no hit-test change |
| Claude brand | `rgb(0.85, 0.47, 0.34)` = **`#D97857`** `:461` | `#E8794B` | ✅ **RESOLVED: `#D97857`** — agent-notch's, tuned against the real mascot art |
| Codex brand | `rgb(0.06, 0.64, 0.50)` = `#0FA380` (OpenAI teal) `:462` | **`#6E63E6`** (blue-violet) | ✅ **RESOLVED: `#6E63E6` blue-violet** — the mockups win; confirmed in live builds #14/#15. Retint agent-notch's glyph |
| Font | `NSFont.monospacedSystemFont(ofSize:weight:)` `:435` | `.monospaced` design | ✅ **Agrees — resolves Q2.** Use the system mono, not a licensed face |
| Row type scale | title 12/semibold, tag 10/regular, snippet 11/regular `:408–419` | 17/600, 13/500, 12/400 | Doc's scale is for the *header*; agent-notch's is the *row*. Not in conflict |
| Divider | `DitherSeparator` — sparse 2px gray pixels, alpha 0.06–0.16 | 1px `hairline` white 8–12% | ✅ **RESOLVED: adopt the dither.** Approved deviation from the mockups |
| Dark lock | `window.appearance = NSAppearance(named: .darkAqua)` `:742` | — | ✅ **Copy** — this is how AC-1.1-d is satisfied cheaply |

### ✅ Codex pet spritesheets — approved for bundling (Q8)

`drawCodexPet` (`:596–608`) renders **official OpenAI Codex Pets spritesheets** from
`pets/*.webp` — 8 files, ~0.5–1 MB each, "© OpenAI, from their public pets CDN"
(agent-notch README). **Bundling these is approved**, so port `drawCodexPet` as-is.
Two things to carry over with it:
- **Keep `drawRing` (`:611–637`) as the fallback.** agent-notch already degrades to it
  when a sprite fails to load; that path must survive the port.
- **Budget ~4–8 MB of app size**, and decide whether to port the pet-picker config
  (`~/.config/agent-notch/pet`, `refreshPetChoice` `:587–594`) or hardcode one pet.

---

## The single biggest anchor: the overlay is a *monospaced, opaque-black terminal surface*

Two facts drive almost every AC and are the things most likely to be "got wrong":

1. **Typeface.** In #2/#7/#8 the overlay text is **monospaced** (session counts,
   stats, status lines, the empty-state copy, the command). The
   current overlay uses the default SF Pro sans everywhere. The overlay must
   switch to a **monospaced font** (`.system(..., design: .monospaced)` / SF Mono)
   as its default. *(Onboarding #3–#6 is the opposite — polished SF Pro **sans**;
   do not make onboarding monospaced.)*
2. **Surface.** In #2/#7/#8 the panel is **solid near-black and opaque** (≈`#0A0A0C`),
   not translucent frosted glass. The current `IslandSurface` uses
   `.regularMaterial` (the frosted-gray look in #1). It must become an opaque near-black fill.

If a build shows frosted-gray glass or SF-Pro-sans in the overlay, it has failed
regardless of anything else.

---

## Design tokens (introduce these; there is no theme file today)

All overlay styling is currently inline literals plus one shared `IslandSurface`
`ViewModifier` — there is **no** theme/token file. Create one (e.g.
`IslandTheme.swift`) so colors/fonts/radii are defined once and every value below
is checkable in one place. Use **explicit** colors (not semantic `.primary` /
`.secondary`, which invert in Light Mode — the overlay must render dark in every
appearance).

### Overlay tokens (from #2/#7/#8)
| Token | ≈ Value | Used for |
|-------|--------|----------|
| `surface` | opaque `#0A0A0C` | panel + pill background |
| `surfaceElevated` | `#16161A` | code block, inset cards |
| `hairline` | `white @ 8–12%` | 1px borders/dividers |
| `textPrimary` | `#F4F5F6` | counts, titles, command text |
| `textSecondary` | `#9A9AA2` | status labels, stats, empty-state subline |
| `textDim` | `#6B6B73` | "esc", timestamps, disabled |
| `accentAttention` | `#FF9F0A` (amber) | "PERMISSION REQUESTED", attention |
| `allowGreen` | **`#34C759`** (finalized; revisit later if #16 proves too muted) | Allow button, Notifications toggle ON |
| `denyRed` | `#B23A34` (muted maroon) — confirmed against #16 | Deny button fill |
| `statusBlocked` | blue/steel — **sample from #16** | glyph tint when awaiting permission |
| ~~`notchEdge`~~ | — | **Not used** — red edges in #2/#7/#8 are the screen-recording indicator, not design (Q1 resolved) |
| ~~`trialAmber`~~ | — | **Not used** — trial banner cut (§1.8) |
| Brand marks | **Claude salmon-asterisk `#D97857`** (resolved, Q5); **Codex blue-violet `#6E63E6`** (resolved, Q7); Cursor mono cube; OpenCode mono square | stats row + cards |
| Font | **monospaced**, sizes ≈ 17/600 (counts), 13/500 (stats & status), 12/400 (sublines) | all overlay text |
| Radius | **dropdown bottom corners `18`** (resolved); pills capsule; cards `≈12`; buttons `≈10` | — |

### Onboarding tokens (from #3–#6)
| Token | ≈ Value | Used for |
|-------|--------|----------|
| Background | radial warm charcoal `#1E1613`→`#0C0908`, faint blue glow top-right | all onboarding screens |
| Card | `#1A1210` fill, `white @ 6%` border, radius `≈14` | agent/connect/pref rows |
| Primary button | glossy **white** pill, text `#1A1A1A`, subtle top highlight | "Get started" / "Continue" |
| Title / subtitle | title `#FFFFFF` bold ~44–56pt **sans**; subtitle `#B8B0AC` | headers |
| Toggle | ON green `#34C759`, OFF gray | preferences |

**AC-TOKENS-1:** A single theme file defines every value above; no overlay view
uses `.regularMaterial`, `.primary`, `.secondary`, or `Color.accentColor` for
color after the change. *(Verify by grep.)*

---

# PHASE 1 — Overlay: display (priority)

> §1.7 and §1.13 live below for continuity of numbering, but are **Phase 2** —
> see the delivery-phase table above.

Files: `IslandOverlayView.swift` (surface, pills, header, controls, usage row),
`HorizonMonitorView.swift` (session list + empty state + rows),
`UsagePresentation.swift` / `SessionDomain/UsageSnapshot.swift` (stats data),
`IslandOverlayPanel.swift` (hit-test radius), `IslandOverlayModels.swift` (geometry sizes).

---

## 1.1 🟢 **P1** · Surface / container — `IslandSurface` (`IslandOverlayView.swift:271–281`)

**Current:** `.regularMaterial` (frosted gray), `cornerRadius: 18`, white-18%
border, soft shadow → the glass look in #1.
**Target:** #2/#7/#8 — an **opaque near-black** dropdown that reads as one solid
dark surface, no translucency.

**Acceptance criteria**
- [ ] AC-1.1-a: Panel background is opaque `surface` (`≈#0A0A0C`); **no**
      `.regularMaterial` and no visible frost/blur of the wallpaper behind it (#2/#8).
- [ ] AC-1.1-b: The expanded panel reads as a dropdown hanging from the notch —
      **top edge flush/square** with the notch, **bottom corners rounded** `≈20`
      (#2/#8). Not a floating uniformly-rounded card.
- [ ] AC-1.1-c: Border is at most a 1px `hairline`; the heavy white-18% stroke
      from #1 is gone (#2/#8 have no bright rim).
- [ ] AC-1.1-d: Reduce-transparency path also renders the **same** opaque near-black
      (never `windowBackgroundColor` gray).
- [ ] AC-1.1-e **(RESOLVED: radius is `18`)**: The bottom corner radius is **18** —
      the value already in the AppKit hit-test path at
      `IslandOverlayPanel.swift:74` (`NSBezierPath(roundedRect:xRadius:18,yRadius:18)`).
      Define it once in the theme file and use it for the drawn shape; the hit-test
      path needs **no change**, and drawn shape and clickable shape must stay equal.
- [ ] AC-1.1-f *(from agent-notch, not from a mockup)*: Expanding/collapsing
      animates the **content layer**, never the window frame — scale from
      `(0.25, 0.06)` with `anchorPoint` at top-center, `0.22s`, `easeOut` opening /
      `easeIn` closing. This is what makes it read as unfolding *out of the notch*.

> ↩ **Copy from agent-notch.** `NotchView.draw` (`main.swift:653–670`) is the exact
> target shape: `NSBezierPath` from top-left down, arc at bottom-left, line across,
> arc at bottom-right, up and closed — square top, rounded bottom, `NSColor.black`
> fill. Port it to a SwiftUI `Shape` (or keep it as an AppKit backing layer).
> Window setup at `:735–743` gives AC-1.1-d for free via
> `window.appearance = NSAppearance(named: .darkAqua)`. AC-1.1-f is
> `animatePanelLayer` (`:863–890`) — note its comment that macOS interpolates
> borderless window frames unreliably, which is *why* it resizes instantly while
> invisible and animates the layer instead.
>
> ✅ **Radius RESOLVED: `18`.** agent-notch draws 16 and this doc estimated ≈20, but
> **18 is the decision** — it is what `IslandOverlayPanel.swift:74` already uses, so
> the hit-test path stays untouched. When porting `NotchView.draw`, change its `16`
> to the theme's radius constant.

---

## 1.2 🟢 **P1** · Collapsed notch pills — `collapsedSummary` (`:142–162`) + `rightWing` collapsed (`:92–100`)

**Current (#1):** left pill = cyan `sparkles` + count + `chevron.down` + a "…"
metadata line; right pill = `Label("Inspect / Expand", systemImage: "chevron.down")`.
**Target (#11 primary, #7):** one crisp opaque-black rounded pill spanning the
notch, with soft gray gradient "wings" fading to the screen edges (#11). Contents,
all monospaced:
- **Left:** a small **square pixel-grid glyph** (gray) · a **dynamic status** —
  either the active agent name (`Claude`, **amber**, #11) or an activity phrase
  (`Waiting on N subagents`, #7) · when a session is actively working, a **green
  pixel-grid activity glyph** (#11).
- **Right:** the session count **"N Sessions"** in `textPrimary` (#11 = "9 Sessions").

> Note on the notch: on a built-in display the overlay draws two wings around the
> physical notch. Map **left wing → status/agent + activity glyph**, **right wing →
> "N Sessions" count**. Do not keep the literal words "Inspect / Expand".

**Acceptance criteria**
- [ ] AC-1.2-a: Collapsed pill background is opaque near-black (`surface`) with soft
      gray gradient wings at the outer edges (#11), not translucent gray (#1).
- [ ] AC-1.2-b: The leading icon is a small **square pixel-grid glyph** (#11/#7) —
      **not** the cyan `sparkles` and **not** a colored circle.
- [ ] AC-1.2-c: Right side shows the literal session count as **"N Sessions"** in
      monospaced `textPrimary` (#11 = "9 Sessions"). The words "Inspect / Expand"
      (#1) no longer appear.
- [ ] AC-1.2-d: Left status is dynamic: the **active agent name** (`Claude`, amber,
      #11) or an activity phrase (`Waiting on N subagents`, #7), from real session
      state — monospaced, no `sparkles`, no "…" placeholder line.
- [ ] AC-1.2-e: When a session is actively working, a **green pixel-grid activity
      glyph** appears after the status text (#11).
- [ ] AC-1.2-f: Clicking the pill still expands/activates (behavior preserved even
      though the "Inspect / Expand" label is gone).

> ↩ **Copy from agent-notch — the glyphs, verbatim.** `IndicatorView`
> (`main.swift:456–638`) *is* the pixel-grid vocabulary this section describes, and
> it is the highest-value thing in the whole repo:
> - `mascotFrames` + `quadrants` (`:466–488`) — the Claude Code banner mascot encoded
>   as Unicode block characters, decomposed into 2×2 sub-pixel quadrants. Two frames
>   whose feet alternate, so it walks.
> - `drawCrab` (`:528–556`) — renders that mascot in Claude coral with a per-cell
>   noise shimmer; feet stay solid alpha, body shimmers `0.8–1.0`. Aspect is
>   deliberately `subW 1.6 × subH 3.2` because terminal cells are ~2× taller than
>   wide, "or he squishes".
> - `drawGreenBlob` (`:508–525`) — the 7×7 dithered green blob for *finished*.
>   **This is the green activity glyph of AC-1.2-e.**
> - `drawRing` (`:611–637`) — an original 9×9 rotating dithered ring. Keep it as the
>   runtime fallback when a pet sprite fails to load (bundling the sprites is
>   approved — Q8).
>
> Copy these `draw(_:)` bodies **unchanged** into `NSViewRepresentable` wrappers and
> drive the `t` property from a timer, as `AppDelegate.tick()`/`render()`
> (`:918–927`) does at `0.12s`.
>
> **What agent-notch does *not* give you here:** it has no collapsed pill background,
> no gradient wings, and **no text at all** in the collapsed state — the indicator is
> glyph-only, right-aligned toward the notch, one slot per agent (`draw` `:490–506`).
> The "N Sessions" label (AC-1.2-c), the amber agent name (AC-1.2-d), the `surface`
> pill fill and the wings (AC-1.2-a) are all still net-new from #11/#7.
>
> 🔍 **Geometry — reference, don't copy.** `notchWidth` (`:690–697`) derives the real
> notch from `safeAreaInsets.top` + `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`,
> falling back to a 180pt fake pill on notchless displays; `isFullscreenSpace`
> (`:706–708`) detects a hidden menu bar so the bar can own the whole top edge.
> Agent Island already handles multi-display selection in `IslandOverlayModels`/
> `IslandOverlayController` — compare, adopt the fullscreen-space trick if we lack
> it, but do not replace our geometry wholesale.
>
> 🔍 **Hit-testing — reference only, ours is better.** agent-notch keeps the collapsed
> window `ignoresMouseEvents = true` and catches clicks with a global
> `NSEvent` monitor against a hardcoded 66pt rect (`:770–782`, `:817–819`), because
> "routing to tiny borderless menu-bar windows is unreliable". Agent Island's
> `containsVisibleShape` region test ([IslandOverlayPanel.swift:73](../../../src/Sources/AgentIslandApp/IslandOverlayPanel.swift#L73))
> already does this properly, including accessibility. **Keep ours** — AC-1.2-f is
> satisfied by not regressing it.

---

## 1.3 🟢 **P1** · Expanded header — header block (`:106–123`) + `overlayControls` (`:193–231`)

**Current:** title "Agent Sessions" (17/semibold sans) + subtitle "N current
Agent Sessions on the selected display" (12/secondary) + a vertical stack of
**text** buttons "Keyboard", "Settings", "Collapse", plus status-announcement lines.
**Target (#2/#8):** a single header row — left **"N Sessions"** bold monospaced;
center the multi-agent stats cluster (see 1.4); right a single **gear** `⚙` icon,
muted gray (no hamburger — confirmed not required).

**Acceptance criteria**
- [ ] AC-1.3-a: Header left shows exactly **"N Sessions"** (literal count + the
      word "Sessions"), bold monospaced `textPrimary` (#2="0 Sessions", #8="3
      Sessions"). The wording "Agent Sessions" / "Focused Agent Session" is gone.
- [ ] AC-1.3-b: The subtitle "N current Agent Sessions on the selected display" is
      **removed** (absent from #2/#8).
- [ ] AC-1.3-c: Header right shows a **gear icon** (`textSecondary`, icon-only) at
      the right inset (#2/#8/#9). **No hamburger/menu icon** (per decision — even
      though #9 shows one). #10 shows a **speaker/sound-toggle** glyph immediately
      left of the gear — include it as a global mute toggle. The text buttons
      "Keyboard" / "Settings" / "Collapse" no longer appear in the header.
- [ ] AC-1.3-d: Gear opens Settings. Keyboard engagement and Collapse stay
      reachable & accessible (keyboard / Escape) even though their header text
      buttons are gone.
- [ ] AC-1.3-e: Header sits on the same opaque surface, single row, vertically
      centered, matching #2/#8 spacing (icons flush to the right edge inset).

---

## 1.4 🟢 **P1** · Multi-agent usage stats cluster — `UsageSnapshotHeader` (`:234–269`)  ⚠ NEW DATA

**Current:** one provider, one value — "Usage Snapshot · <provider>" + "Used: N%"
with a `chart.bar` icon. The model (`UsageSnapshot`) holds a single
`usedPercent`/`remainingPercent`.
**Target — two formats:**
- **Compact multi-provider** (#2/#8/#9, panel header): a refresh glyph `⟳`, then
  **per provider** brand mark + windowed percentages — Claude `5H: 24% 7D: 21%`,
  Codex `5H: -- 7D: 30%`, Cursor `MO: 0%` (#9). `--` = no data for that window.
- **Detailed single-provider** (#10, focused-session header): the active provider's
  brand mark in a rounded **orange badge**, then `5h 24% 2h14m │ 7d 21% 3d5h` —
  window label + **percent** + a **time value** (remaining/window), windows
  separated by a vertical bar. Percentages render **green** when healthy (#10).

> ⚠ This requires extending the data model (`UsageSnapshot` → multiple named
> windows `5H`/`7D`/`MO` per provider, multiple providers rendered together).
> The current single-value model cannot express it. **Blocked on data work** — do
> not fake numbers. Deliver the *layout/typography* to spec, wired to real
> multi-window data.

**Acceptance criteria**
- [ ] AC-1.4-a: Stats cluster renders **multiple providers side by side**, each
      preceded by its brand mark (Claude salmon asterisk, Codex blue-violet mark,
      Cursor mono cube), left-to-right as in #2/#8.
- [ ] AC-1.4-b: Each provider shows labeled windows in the form `5H: X%`,
      `7D: X%`, `MO: X%`; missing data renders as `--` (as `5H: --` in #2/#8), not
      `0%` and not hidden.
- [ ] AC-1.4-c: A refresh/sync glyph `⟳` precedes the cluster (#2/#8).
- [ ] AC-1.4-d: Monospaced, `textSecondary` for labels/values so columns align;
      matches the compact single-row density of #2/#8 (no "Usage Snapshot ·"
      title text, no state pill).
- [ ] AC-1.4-e **✅ CONFIRMED by #18**: In the **focused-session** header the active
      provider shows the detailed form — window label, percent, and a time value per
      window, separated by `│`. #18 renders `5h 53% 8m │ 7d 25% 3d3h` with the salmon
      brand mark leading, alongside a 🔊 mute toggle and ⚙.
      *(#18 shows a plain brand mark, not the rounded orange badge #10 suggested —
      prefer #18, it is the newer build.)*

> ### What these numbers actually are
>
> **`5h` and `7d` are the active agent's own subscription-plan quota windows** —
> Claude's / Codex's rolling **5-hour** limit and **weekly** limit. They are **not**
> Agent Island usage, not per-session accounting, and **not** anything to do with
> billing us (there is no paywall — §1.11).
>
> Each window renders as **percent consumed** plus the **time value** attached to that
> window (`8m`, `3d3h` — i.e. until the window resets). Only the **active agent's**
> provider appears in this focused header; the compact multi-provider form (AC-1.4-a)
> is what shows Claude + Codex + Cursor side by side.
>
> **Sourcing:** this is provider quota state, which is **not** in hooks, transcripts,
> or the statusline — see Q4 ④. It is the one genuinely unsourced input behind §1.4.
- [ ] AC-1.4-f **(RESOLVED — thresholds set)**: Quota percentages are color-coded by
      **consumption** of the agent's plan window:
      | Consumed | Color |
      |---|---|
      | **0–60%** | green (`allowGreen`) |
      | **60–80%** | orange (`accentAttention`) |
      | **80%+** | red |
      Confirmed against #18 (53% and 25%, both green). Applies everywhere a quota
      percentage renders — §1.4 compact + detailed, and §1.12/§1.12.1.
- [ ] AC-1.4-g: Hovering the stats cluster reveals a **"View usage details"**
      tooltip/affordance under it (#12) that opens the detailed usage view (§1.12).

---

## 1.5 🟢 **P1** · Empty "waiting for sessions" state — `HorizonMonitorView` empty branch (`:78–85`)

**Current:** `ContentUnavailableView("No Agent Sessions observed", systemImage:
"circle.dashed", description: "Horizon will show source-proven Agent Session
observations here.")`.
**Target (#2):** centered, two lines — heading **"Agent Island · waiting for
sessions"** (mockup shows "AgentPeek" → use the brand "Agent Island", with the brand
word slightly brighter than "· waiting for sessions"),
subline **"Run an agent session and it'll show up here."** in dimmer monospaced gray.

**Acceptance criteria**
- [ ] AC-1.5-a: Empty-state heading reads **"Agent Island · waiting for
      sessions"** (mockup shows "AgentPeek" — substitute the brand). Not "No Agent
      Sessions observed".
- [ ] AC-1.5-b: Subline reads exactly **"Run an agent session and it'll show up
      here."** (#2). Not the "source-proven observations" copy.
- [ ] AC-1.5-c: No SF Symbol glyph above the text (#2 has none — remove the
      `circle.dashed` icon). Monospaced, centered, vertically within the panel body.
- [ ] AC-1.5-d: The `HorizonSummaryBar` empty status text (`:142`, currently
      "Waiting for observations") is reconciled with the new empty state so the two
      don't contradict.

> ↩ **agent-notch: structure only, do not copy the copy.** `SessionListController`
> handles empty at `main.swift:320–322` with a single monospaced 12pt
> `secondaryLabelColor` line — **"No recent agent sessions"**. Take the shape (one
> plain mono line, no SF Symbol — confirming AC-1.5-c) but **not the wording**: #2's
> two-line "Agent Island · waiting for sessions" + "Run an agent session and it'll
> show up here." is the spec. Also note agent-notch uses `secondaryLabelColor`, which
> AC-TOKENS-1 forbids — use the explicit `textSecondary`/`textDim` tokens.

---

## 1.6 🟢 **P1** · Session activity rows — `HorizonMonitorView` list + `HorizonSessionRow` (`:215–247`)

**Now that the panel is populated (#9), each session row is dense.** Reproduce this
anatomy (all monospaced):

- **Line 1 (identity + activity):** a leading **square pixel-grid glyph** tinted by
  state/brand (salmon for Claude in #9; green when actively working in #10) · the
  **session/project name** bold `textPrimary` (`the-automator`, `agent-island`) ·
  then the **activity/status element**, which has two forms:
    - a **running command** — window glyph + `Ran rtk curl -s http://127…` in
      **violet** mono, truncated (#9); or
    - a **waiting status** — a `💬` glyph + `Claude is waiting for your input` in
      **green** (#12) when the session is waiting on you.
  · far right: **elapsed** (`58m`/`2m`) and the **launching-app icon** (e.g. Warp) ·
  a trailing `›` expand chevron.
- **Line 2 (metadata strip):** a compact run of stats, each with a small leading
  glyph, in `textSecondary` mono (from #9): **model** (`Opus 4.8`) · **git branch**
  (`main`) · **token counts** (`↑ 6.9M / 55.0k`) · **context %** (`12%`) · **memory**
  (`404.8 MB`) · **disk I/O** (`Zero KB/s`) · **cost** (`$6.30`) · a **count**
  (`▭ 3`) · **diff stat** (`+879 −44`, green/red) · a trailing status glyph.

> ⚠ **Most of this metadata is not in the session model today.** The current card
> carries lifecycle/owner/host/title only; model, branch, tokens, context %, memory,
> disk, cost, diff, launching app, and the live activity command are **new
> per-session data** (the Display settings already expose toggles like "Show AI
> Model" / "Show Worktree", but the code renders "unavailable" placeholders). Treat
> the row **layout/typography** as the spec now; the field values are blocked on the
> data projection (Q4).

**Acceptance criteria**
- [ ] AC-1.6-a **(RESOLVED: dithered divider)**: Rows render on the opaque near-black
      surface, monospaced, separated by agent-notch's **dithered pixel separator** —
      a sparse row of 2px gray cells, alpha `0.06–0.16`, deterministically seeded —
      **not** a flat 1px hairline. This is an intentional, approved deviation from
      #9. The frosted `Color.primary.opacity(0.035)` container is gone.
- [ ] AC-1.6-b: Line 1 order left→right: pixel-grid glyph, **bold session name**,
      window glyph, **violet truncated activity** (`Ran … http://127…`), then
      right-aligned **elapsed** (`2m`) + **launching-app icon** + `›` (#9).
- [ ] AC-1.6-c: Line 2 shows the metadata strip in the #9 order: model · branch ·
      tokens (`↑ 6.9M / 55.0k`) · context % · memory · disk I/O · cost · count ·
      diff (`+N −M`, green/red), each with its leading glyph. A field is omitted
      cleanly when its data is absent or its Display-settings toggle is off.
- [ ] AC-1.6-d: The activity/status element truncates on one line with a trailing
      `…` (never wraps). **Three variants**, each visually distinct from the gray
      metadata:
      | State | Copy | Color | Ref |
      |-------|------|-------|-----|
      | Running a command | `Ran rtk curl -s http://127…` | **violet** | #9 |
      | Waiting on you | `💬 Claude is waiting for your input` | **green** | #12 |
      | **Waiting on permission** | **`Waiting to run <command>`** | **dim gray** | **#16** |
- [ ] AC-1.6-e: The leading pixel-grid glyph is tinted by state: **salmon** = Claude
      idle/identity (#9), **green** = actively working (#10), **blue/steel** =
      blocked awaiting permission (#16). Sample the exact blue from #16.
- [ ] AC-1.6-f: In the waiting/permission state the row still shows the `esc`
      keyboard hint on the right (#8), consistent with this richer layout.
- [ ] AC-1.6-g *(from agent-notch, not from a mockup)*: A session with subagents
      shows a **`▸ N subagents` / `▾ N subagents`** disclosure under its row; expanded,
      each child renders as an indented, smaller row labelled by the task it was
      given. This is the populated form of #7's "Waiting on 2 subagents".

> ↩ **Copy from agent-notch — line 1 and the helpers.** `row(for:)`
> (`main.swift:400–431`) is already the AC-1.6-b anatomy: leading 16×16 pixel glyph ·
> bold title · flexible spacer · right-aligned tag · then a second line, one line
> only, `lineBreakMode = .byTruncatingTail`. Take with it:
> - **`label(_:size:color:bold:)` (`:433–441`)** — the single chokepoint that makes
>   *everything* monospaced. Its
>   `setContentCompressionResistancePriority(.defaultLow, for: .horizontal)` is what
>   makes rows truncate instead of forcing the borderless window wider — the exact
>   failure mode AC-1.6-d guards against. **Mirror this helper in the theme file.**
> - **`DitherSeparator` (`:271–288`)** — a sparse row of gray pixels standing in for a
>   rule, seeded deterministically. ✅ **APPROVED — this replaces the flat 1px
>   hairline** in AC-1.6-a. Copy it verbatim.
> - **`DitherIconView` (`:217–268`)** — the row-scale (18×16) glyph: mini walking
>   mascot while running, **green pixel checkmark** (`checkmark` `:224–226`) when
>   done. Maps to AC-1.6-e's state tinting.
> - **`relative(_:)` (`:443–448`)** — `now` / `Nm` / `Nh`, the elapsed format in
>   AC-1.6-b. Trivial, but copy it so the two apps read identically.
> - **Subagent disclosure** — toggle button `:332–348` (mono 10pt semibold, `▸`/`▾`,
>   count pluralised, 24pt indent) + `childRow` (`:365–394`, 28pt indent, 11pt/9pt
>   type, capped at 8 children). AC-1.6-g.
>
> **Still net-new:** the entire **line-2 metadata strip** (AC-1.6-c). agent-notch's
> tag is only `model · elapsed` (`:409`) — there is no branch, token count, context %,
> memory, disk I/O, cost, diff, or launching-app icon anywhere in it. Likewise the
> **violet running-command** and **green waiting-status** variants (AC-1.6-d) do not
> exist; agent-notch colors the tag `systemBlue` when running / `systemGreen` when
> done (`:410`), which is a *different* signal from what #9/#12 show.

---

## 1.7 Permission-request card — 🔵 **PHASE 2 (bidirectional)** — spec confirmed by #16

> **#16 is a live-build capture of this exact card, and it matches every AC below
> as originally written** (amber dot + "PERMISSION REQUESTED", `$`-prefixed wrapping
> command block, Deny-maroon-left / Allow-green-right with `⌘N`/`⌘A`, and the two dim
> secondary actions). Treat #16 as the primary reference and #8 as corroboration.
> Sample the exact button fills from #16 — its green reads **more muted than system
> `#34C759`**, so the `allowGreen` token likely needs adjusting.
>
> ⚠ Its header shows the **hamburger**, same as #14 — still **out** per Q11.

**Target (#16, #8):** below the activity row —
1. **"PERMISSION REQUESTED"** label: an amber dot `●` + uppercase, letter-spaced
   amber text (`accentAttention`).
2. A **code block**: rounded (`≈12`) `surfaceElevated` container with a hairline
   border, a leading `$ ` prompt, and the full command in monospaced `textPrimary`,
   **wrapping** across lines.
3. Two full-width action buttons side by side:
   - **"Deny  ⌘N"** — solid muted-maroon fill (`denyRed`), white bold text,
     radius `≈10`; the "⌘N" shortcut rendered lighter/inline.
   - **"Allow  ⌘A"** — solid green fill (`allowGreen`), white bold text, radius `≈10`.
4. Two secondary text actions under the buttons: **"Deny with feedback"** (left,
   `textDim`) and **"Open Terminal  ⌥T"** (right, `textDim`).

> ⚠ **CORRECTION — the action layer already exists.** An earlier draft of this doc
> claimed there was "no permission/command payload or Allow/Deny action in the
> session model". That is wrong at the adapter layer:
> [ClaudeLiveAction.swift](../../../src/Sources/ClaudeCodeAdapter/ClaudeLiveAction.swift)
> defines `ClaudePermissionDecision` (allow/deny), `ClaudeOfferedPermissionSuggestion`,
> `ClaudeLiveActionSemantic.permission` / `.permissionSuggestion`, and
> `ClaudeTypedHookResponse.permission(_:suggestionJSON:)`, with an ownership/staleness
> guard (`ClaudeLiveActionRejection`).
>
> **What is missing is the UI** — nothing under `Sources/AgentIslandApp/` consumes
> any of it. So §1.7 is **UI work over an existing action contract**, not net-new
> feature work.
>
> ### ✅ VERIFIED — showing the real command is supported, and is a product requirement
>
> *(An earlier draft of this doc claimed interaction content was "refused by design"
> and treated that as a constraint. **That was wrong** — corrected below.)*
>
> **Product requirement (authoritative):** Agent Island shows **what the agent is
> actually doing** — permission requests, questions, and code changes — from hooks,
> and lets the person **approve or reject**. This is the product; it is not
> negotiable against an internal abstraction. Prior art does the same.
>
> **The codebase already supports this.** There is a first-class interaction-content
> channel, and the Claude adapter already uses it:
> | Evidence | Meaning |
> |---|---|
> | `PayloadClassification.interactionContent` ([Envelope.swift:21](../../../src/Sources/SessionDomain/Envelope.swift#L21)) | content is a **classified, supported** category — not a forbidden one |
> | `ClaudeCodeAdapter.swift:251` sets `classification = .interactionContent` | the Claude adapter **already emits** interaction content |
> | `SessionStore.swift:410` accepts `.interactionContent` as valid | the store **accepts and persists** it |
> | `SessionHistory.receivedContent: [SessionHistoryContent]` | content is **retained per session**, with bounding/truncation |
>
> **What the "metadata-only" comment actually scopes.** That sentence is on
> `GuidedAttentionEvidence` — the *attention-evidence* record — not on the system.
> `EventFamily` is likewise documented as covering "only the families needed for an
> **observation-only vertical slice**". These are **increment boundaries from an
> earlier observation-only phase**, not a permanent architecture.
>
> **So the work is:** carry the command text into the attention path (via the existing
> `interactionContent` classification), rather than design around its absence.
> `ClaudeLiveCallback.nativeInput` already holds the raw tool input at action time.
> **Do not** water down AC-1.7-b — render the full command.

> ### ❌ VERIFIED — the Claude statusline output is never parsed
>
> `grep` for `total_cost`, `totalCost`, `exceeds_200k`, `lines_added`, `linesAdded`,
> `context_used` across all Swift sources returns **zero hits**.
> `ClaudeStatusLineBridge.swift` **installs and owns** the statusline entry; nothing
> ever reads what it emits. **The field names are therefore not answerable from this
> repo** — they must come from Claude Code's statusline documentation, and the
> consumer is net-new work. (Expected to include a `cost` object and a
> context/token indicator, but **treat that as unverified until checked against the
> docs**.)

**Acceptance criteria**
- [ ] AC-1.7-a: The label reads exactly **"PERMISSION REQUESTED"** in uppercase
      amber with a leading amber dot (#8).
- [ ] AC-1.7-b: The command sits in a distinct rounded `surfaceElevated` block with
      a `$ ` prompt and wraps to multiple lines (#8) — not truncated here (contrast
      with the one-line activity preview in 1.6).
- [ ] AC-1.7-c: Two side-by-side buttons: left **Deny** maroon, right **Allow**
      green, each with its shortcut label (`⌘N` / `⌘A`), matching #8 colors/order.
- [ ] AC-1.7-d: Secondary actions **"Deny with feedback"** (left) and **"Open
      Terminal ⌥T"** (right) appear below, dim and text-only (#8).
- [ ] AC-1.7-e: `⌘A` triggers Allow and `⌘N` triggers Deny while the card is shown.
- [ ] AC-1.7-f *(new, from #16)*: The two buttons are **equal-width, splitting the
      full card width** with a gap between them — not intrinsically sized. Each
      shortcut (`⌘N` / `⌘A`) sits inline after the label in a lighter weight.
- [ ] AC-1.7-g *(new, from #16)*: When the command is long, the **card body scrolls**
      (#16 shows a scrollbar at the right edge) — the command block itself keeps
      wrapping in full rather than truncating, and the action buttons stay reachable.
- [ ] AC-1.7-h *(new, from #16)*: The owning activity row above the card reads
      **"Waiting to run &lt;command&gt;"**, truncated to one line — a distinct third
      status phrasing (see AC-1.6-d). Its leading pixel glyph renders **blue/steel**,
      not salmon or green (see AC-1.6-e).

---

## 1.8 Trial banner — ❌ CUT (no monetization)

**Do not implement.** The trial banner in #2 ("Trial ends in 69h · 22 Jul 2026 at
12:30 AM") is **out of scope** — the product ships with no paywall, so there is no
trial to count down. Ignore it wherever it appears in a reference image.

> A trial exists only to convert to a paid tier; with §1.11 cut, this goes with it.
> If monetization is ever revisited, restore this section from git history.

---

## 1.9 Red notch edge strips — RESOLVED: do NOT implement

The thin **red** vertical strips at the panel edges in #2/#7/#8 are the macOS
**screen-recording indicator** bleeding into the capture, **not** part of the
design.
- [ ] AC-1.9-a: Do **not** add any red edge strips or notch accent. The panel's
      outer edges are the plain opaque `surface`.

---

## 1.10 🟢 **P1** · Focused single-session card — `HorizonFocusedSession` / `HorizonSelectedDetail` (`HorizonMonitorView.swift:182, 316`)  ⚠ NEW DATA

**Target (#10):** when one session is focused, the body is a single rich card:
- **Title row:** the **session/project name + first-prompt title**, truncated
  (`agent-island · [Image #1] this is how our ui look…`), then trailing pills —
  **agent** (`Claude`, salmon-tinted), **model** (`Opus 4.8`), **host** (`Warp`),
  **elapsed** (`3m`), and a **jump button** `⌃G ↗` (keyboard shortcut to jump to the
  session's terminal/IDE).
- **Status glyphs:** the leading pixel-grid glyph(s) render **green + animated**
  while working (#10).
- **Agent message body:** the agent's current message/summary as **multi-line body
  text** that wraps (#10).
- **"You:" sub-card:** the user's last prompt in a rounded inset (`You: 1. we will
  go with claude as first agent, rest …`) with a right-aligned **status** (`Done`).
- **Transcript excerpt:** a **scrollable** region (visible scrollbar) showing recent
  turn text (#10).

> ⚠ The current focused/selected views show only operational metadata plus the
> honest placeholder "No source-proven completion recap received" — there is **no
> agent message body, You-prompt text, or transcript** in the model. This card is
> **new data** (live message + transcript projection) + new layout; the jump button
> maps to the existing click-to-jump behavior. Blocked on data (Q4).

**Acceptance criteria**
- [ ] AC-1.10-a **✅ CONFIRMED by #18**: The focused card shows the
      `project · task` title truncated (`agent-island · Create sample multi-select
      question w…`) with trailing **agent / model / host / elapsed** pills — #18 shows
      `Claude` `Opus 4.8` `Cursor` `2m`, so **host = the launching app**.
      > ⚠ **#18 shows no `⌃G ↗` jump control because that build paywalled it.**
      > We ship **no paywall** (§1.11), so **the jump control always renders** — do
      > not copy #18's omission.
- [ ] AC-1.10-b: A **multi-line agent message body** renders under the title (#10),
      not a one-line status.
- [ ] AC-1.10-c: The user's last prompt appears in a **"You:" inset** with a
      right-aligned status (`Done` / working) (#10).
- [ ] AC-1.10-d: A **scrollable transcript excerpt** with a visible scrollbar sits
      below (#10).
- [ ] AC-1.10-e: Working state shows **green animated** pixel-grid glyph(s) (#10).

> ↩ **agent-notch: one idea worth taking, plus the glyph.** `row(for:)` at
> `main.swift:417` builds its subtitle as `s.prompt.isEmpty ? s.snippet : "You: " +
> s.prompt` — i.e. **the row is titled by *your* prompt, not the agent's chatter**
> (the agent-notch README calls this out as a deliberate product decision). That is
> the same instinct behind the "You:" inset in AC-1.10-c, and it should inform how we
> pick the focused card's headline. AC-1.10-e's green animated glyph is
> `drawGreenBlob`/`DitherIconView` from §1.2 — already covered.
>
> **Everything else here is still net-new.** agent-notch has one truncated 90-char
> line (`clean` caps at 90, `:209`); there is no multi-line agent message body, no
> scrollable transcript, and no trailing agent/model/host/elapsed pills.

## 1.11 "Unlock full control" upsell banner — ❌ CUT (no monetization)

**Do not implement.** **The product ships with no paywall.** The "Unlock full
control" banner in #10/#18, its "+N more sessions · $14.99" subline, and the
"+15 more sessions with a license" footer line are all **out of scope**.

**Consequences that matter elsewhere in this doc:**
- **No session cap.** "+N more sessions with a license" implies a limit on visible
  sessions. There is none — the list is bounded only by real session count.
- **Nothing is entitlement-gated.** **Jump, Approvals, and Shortcuts always render**
  for everyone. #18 shows no `⌃G ↗` jump control on its focused card; **that is a
  paywalled build, not the target** — AC-1.10-a's jump control is unconditional.
- **No trial banner** either (§1.8 is cut for the same reason).
- **No licensing/entitlement data model is needed** — this drops out of Q4 entirely.

> Ignore every paywall, trial, price, lock glyph, and "with a license" string in any
> reference image. They are artifacts of a monetized build that is not the target.

---

## 1.12 🟢 **P1** · Menu-bar usage popover — click the menu-bar icon (NSStatusItem)  ⚠ NEW DATA

**Target (#13):** clicking the Agent Island **menu-bar icon** opens a popover titled
**"Agent Island"** (mockup shows "AgentPeek") with a ⟳ refresh and ⚙ gear top-right,
then a **per-provider usage breakdown** — the same destination as the #12 "View
usage details" tooltip. Each provider = brand mark + name, then window rows, all
monospaced:
- **Claude:** `5H 25% used` — right: `Resets in 1h 24m` — with a **green progress
  bar**; `7D 21% used` — right: `refills Fri at 10:30 PM` — green bar.
- **Codex:** `5H --` (empty bar); `7D 30% used` — `refills Sat at 1:49 PM`; a
  `0 resets available` note.
- **Cursor:** `MO 0% used` — `refills Aug 14 at 10:42 AM`.
- **OpenCode:** `TOK 2.6M` — `26 req / 2.6M tokens / $0.16` (token/cost, no %).
- Footer: an **"Active" / "Metrics"** segmented toggle (Active selected).

> ⚠ Same data gap as §1.4, deeper: per-provider **windowed % + progress bar + reset/
> refill timestamps + token/req/cost**, plus an Active-vs-Metrics split. The current
> `UsageSnapshot` model holds one provider's single value. Blocked on data (Q4 ④).
> ✅ A menu-bar status item **already exists** (Q6) — this replaces its `NSMenu`.

**Acceptance criteria**
- [ ] AC-1.12-a: Clicking the menu-bar icon opens a popover titled **"Agent Island"**
      with ⟳ and ⚙ controls (#13).
- [ ] AC-1.12-b: Each provider (Claude, Codex, Cursor, OpenCode) shows its brand mark
      + name and its window rows in the #13 form: `<window> <N>% used` + a **green
      progress bar** + a right-aligned **reset/refill** string; `--` for no data.
- [ ] AC-1.12-c: Token-based providers (OpenCode) show `TOK <n>` and a
      `<req> req / <tokens> tokens / $<cost>` line instead of a percentage (#13).
- [ ] AC-1.12-d: A footer **"Active" / "Metrics"** segmented toggle is present,
      "Active" selected by default (#13); **"Metrics"** switches to the view in #15.

### 1.12.1 The "Metrics" tab (#15) — Q6 RESOLVED

Same popover shell (title, ⟳, ⚙, footer toggle), different body: **one card per
provider**, each with a selection radio at the trailing edge. Per card:

- **Headline figure**, large monospaced — a **token total** (`5.0B`, `1.0B`, `2.6M`)
  for token-metered providers, or a **percentage** (`0% monthly`) for quota-metered
  ones (Cursor).
- **A usage histogram** — a small bar chart of recent usage, drawn on a dashed
  baseline so an empty series still reads as a chart.
- **A composition breakdown**, colored-dot list: `input`, `output`, `cache write`,
  `cache read` as percentages (Claude: `<1% / 1% / 3% / 96%`). Rows are omitted when a
  provider doesn't report them (Codex shows no `cache write`).
- **A per-model split** beneath it — `Opus 4.8 72%`, `Opus 4.7 14%`, `other 14%`;
  Codex `GPT-5.6 Terra 60%`, `GPT-5.6 Sol 33%`, `other 8%`. An **`other` bucket
  always absorbs the tail** so the split sums to 100%.
- **Quota-metered providers substitute** a progress bar + refill date
  (`refills Aug 14`) and a `used / remaining` pair plus per-mode rows (`Auto`, `API`).

**Acceptance criteria**
- [ ] AC-1.12-f: Selecting **Metrics** replaces the body with per-provider cards while
      the title, ⟳/⚙, and footer toggle stay put (#15).
- [ ] AC-1.12-g: Each card shows a headline figure, a histogram, a dotted
      input/output/cache breakdown, and a per-model split ending in an **`other`**
      bucket (#15).
- [ ] AC-1.12-h: **Token-metered** providers (Claude/Codex/OpenCode) lead with a token
      total; **quota-metered** providers (Cursor) lead with a percentage plus a
      progress bar and refill date. Both forms coexist in one list (#15).
- [ ] AC-1.12-i: Breakdown rows absent from a provider's data are **omitted**, not
      rendered as `0%` (Codex has no `cache write` row in #15).

> ⚠ **This is the deepest data ask in the document** — per-provider, per-model,
> per-token-class accounting plus a time series. See Q4; nothing in the current
> `UsageSnapshot` can express any of it.
- [ ] AC-1.12-e: Monospaced; opaque dark popover consistent with the overlay's
      surface/type language; brand title reads **"Agent Island"**.

> ↩ **No help from agent-notch here** — it runs `.accessory` with **no status item at
> all**; its only menu is a right-click "Quit Agent Notch" on the indicator
> (`main.swift:647–651`).
>
> ✅ **Q6, first half — answered from our own code:** a menu-bar status item **does
> already exist** in Agent Island at
> [AppDelegate.swift:812–815](../../../src/Sources/AgentIslandApp/AppDelegate.swift#L812)
> — `NSStatusBar.system.statusItem(withLength: .variableLength)` with a
> `circle.hexagongrid.fill` symbol. It currently attaches an **`NSMenu`**, so this
> section is "replace the menu with a popover", not "add a status item".

---

## 1.13 `AskUserQuestion` blocking card — 🔵 **PHASE 2 (bidirectional)** — paginated wizard

When an agent calls `AskUserQuestion`, the overlay expands into an answerable card.

> ### ✅ Q10 RESOLVED — the paginated wizard wins
>
> **[`VIBE_ISLAND_FUNCTIONALITY.md`](../../../VIBE_ISLAND_FUNCTIONALITY.md)
> §"Verified Claude multi-question wizard" IS the specification for this section** —
> both behavior *and* visuals. Read it first; **it is authoritative and this section
> does not restate it.**
>
> ⚠ **Reference #14 shows a *stacked* form — that build is STALE. Do not implement
> it.** #14 renders all questions in one scroll with radio circles, "0 of 3
> answered", and a single Send. The target is instead **one question at a time**,
> with **Previous / Next**, a **"Question 1 of 3"** counter, progress dots, and
> **orange numbered option tiles** mapped to `⌃1`/`⌃2`/`⌃3`.
>
> **#14 is still useful for everything *around* the wizard** — the opaque surface,
> monospaced type, the owning-session activity row, and the amber attention label.
> Use it for the shell; use the functionality doc for the wizard itself.
>
> ### Where the card sits: #18 shell + #17 content
>
> **#18 is the overlay shell** — detailed usage header, focused session card with its
> trailing pills, and the "You:" prompt line. **The question renders directly beneath
> it, inside the same overlay** (never a separate window — the functionality doc is
> explicit that no macOS dialog opens).
>
> ⚠ **#17 is a *content* reference, not a styling one.** It is Claude Code's own IDE
> rendering — lighter chrome, sans-ish type, its own control shapes. Take from it
> **what** appears (checkboxes, the header chip, "Submit answers", "Esc to cancel",
> the "Other" option, the focused-row highlight) and render it in **this overlay's**
> monospaced, opaque-black, orange-attention language.

**What this section adds** (everything else: see the functionality doc):

- [ ] AC-1.13-a: The wizard is **paginated** — one question per page, **Previous**
      (left, disabled on Q1) and **Next** (right, disabled until the current question
      has a valid answer). **Not** a single stacked scroll.
- [ ] AC-1.13-b: Both progress indicators are present — the **dot row**
      (green answered / orange current / gray future) **and** the textual
      **"Question N of M"**. Neither is removed as redundant; they serve different
      scan patterns.
- [ ] AC-1.13-c: Each option is an **amber-brown rounded row** with a brighter orange
      **numbered tile** (from 1) at the leading edge and a trailing chevron. Holding
      the configured modifier swaps the chevron for `⌃1`/`⌃2`/`⌃3` **while keeping the
      number tile visible**. No option is preselected — including the recommended one.
- [ ] AC-1.13-d: `(Recommended)` renders **inline inside the option description**, not
      as a separate badge.
- [ ] AC-1.13-e: The question is introduced by an **orange bracketed category tag**
      (e.g. `[Branch]`) followed inline by the question in bold off-white.
- [ ] AC-1.13-f: **Attention orange replaces active blue throughout** — glyph, bell,
      question header, category tag, and option numbering — as one coherent
      blocking-state color.
- [ ] AC-1.13-g **(RESOLVED by #17): multi-select uses a square checkbox** at each
      option's leading edge, in place of the single-select numbered tile.
      `ClaudeQuestionGroup.allowsMultiple` already models the distinction, and the
      functionality doc maps Control-Return to submitting a multi-select answer.
- [ ] AC-1.13-i *(from #17)*: A multi-select question's footer action reads
      **"Submit answers"** with a leading numbered tile, and an **"Esc to cancel"**
      hint sits below it.
- [ ] AC-1.13-j *(from #17)*: The question's `header` renders as a **titled chip**
      above the question text ("Weekend"), with an **✕ dismiss** at the trailing edge
      of that row.
- [ ] AC-1.13-k *(from #17)*: The **focused option row is highlighted** with a lighter
      fill, so keyboard traversal is visible. An **"Other"** option is always appended
      and carries **no description**.
- [ ] AC-1.13-h: The flow **never opens a separate macOS dialog**; it stays inside the
      notch surface, and preserves the current question and entered answers when
      switching between focused and full-list modes.

> ↩ **No help from agent-notch** — it has no interactive card of any kind.
> **Reuse from within this doc instead:** §1.7's amber attention label and button
> row, and §1.6's activity row, are the same components. Build them once.

> ↩ **No help from agent-notch** — it has no interactive card of any kind.
> **Reuse from within this doc instead:** §1.7's amber attention label and button
> row, and §1.6's activity row, are the same components. Build them once.

> ### ✅ The answer path already exists — this is closer to shipping than it looks
>
> Unlike most of Phase 1, `AskUserQuestion` is **not** blocked on new adapter work:
> - `AskUserQuestion` is a recognized tool
>   ([ClaudeCodeAdapter.swift:134](../../../src/Sources/ClaudeCodeAdapter/ClaudeCodeAdapter.swift#L134))
>   and an interactive hook
>   ([ClaudeHookHelper.swift:450](../../../src/Sources/ClaudeCodeAdapter/ClaudeHookHelper.swift#L450)).
> - `ClaudeLiveActionSemantic.questionAnswers` and **`ClaudeQuestionGroup`**
>   (`questionIndex`, `choiceIDs`, **`allowsMultiple`**) already model an answer
>   submission ([ClaudeLiveAction.swift:61](../../../src/Sources/ClaudeCodeAdapter/ClaudeLiveAction.swift#L61)).
>   `allowsMultiple` confirms multi-select must be supported (AC-1.13-g).
>
> **What is missing is the UI, not the model** — `grep` finds **no** reference to
> `questionAnswers` / `ClaudeQuestionGroup` anywhere under `Sources/AgentIslandApp/`.
>
> ### ✅ VERIFIED — what actually reaches the app
>
> **Most of the render payload is already there, in Codable form.**
> `GuidedSemanticShape`
> ([GuidedAttention.swift:132](../../../src/Sources/SessionDomain/GuidedAttention.swift#L132))
> carries everything the wizard needs:
> | Model field | Drives |
> |---|---|
> | `choices: [GuidedChoice]` → `.label` | the option rows |
> | `GuidedChoice.recommended` | inline `(Recommended)` — AC-1.13-d |
> | `allowsMultipleSelection` | checkbox vs. numbered tile — AC-1.13-g |
> | `supportsFreeText` | the **"Other"** option — AC-1.13-k |
> | `minimumSelections` / `maximumSelections` | Submit-enabled rule |
> | `GuidedAttentionDraft.questionIndex` | **pagination** — independently confirms Q10 |
>
> Its doc comment — *"Choices start with an empty selection even when one is marked
> recommended"* — is exactly AC-1.13-c's no-preselection rule, already enforced.
>
> ⚠ **Two gaps, and one is architectural:**
> 1. **`GuidedChoice` has no `description` field** — only `id`, `label`,
>    `recommended`. #17 shows a description under every option. **Either extend
>    `GuidedChoice` or drop the descriptions.**
> 2. **The question's own prose** is not on `GuidedAttentionEvidence` (which exposes
>    only `displayTitle` / `sourceContext`). It must be carried through the existing
>    **`interactionContent`** channel, exactly as the command text in §1.7 — see the
>    corrected note there. This is plumbing to add, **not** a design refusal.

---

# PHASE 1B — Onboarding (secondary track; #3–#6)

None of these screens exist in code. `AtlasOnboarding.swift` is only a state
reducer over four *education concepts* (aggregation / completionAwareness /
hostFallback / setupAndDisplay) — a different model from the target flow
(welcome → agent grid → connect → preferences). This is a new windowed flow, **SF
Pro sans** (not monospaced), on the warm charcoal background token.

## 2.1 Welcome (#3)
- [ ] AC-2.1-a: Centered app icon (rounded-square blue-gradient mascot with the
      notch face), then **"Agent Island"** bold sans (~56pt), then subtitle **"Your
      coding agents, in the Mac notch"**, then a glossy **white** "Get started" pill.
- [ ] AC-2.1-b: Warm charcoal radial background (token), macOS traffic lights top-left,
      **no** back button on this first screen.

## 2.2 Which agents do you use? (#4)
- [ ] AC-2.2-a: Circular back button top-left; centered title **"Which agents do
      you use?"** + subtitle **"Select the agents Agent Island should set up now."**
- [ ] AC-2.2-b: **3-column** grid of agent cards in this order: Claude, Codex,
      Cursor / Grok, Kimi, Hermes / OpenCode, GitHub Co…, Kilo Code / Droid,
      Antigravity, Pi — each card = brand icon + name + trailing empty checkbox,
      dark card token.
- [ ] AC-2.2-c: Footer helper "Select at least one agent to continue." (gear glyph)
      + glossy white **"Continue"** pill; Continue disabled until ≥1 selected.

## 2.3 Connect an agent (#5)
- [ ] AC-2.3-a: Back button; title **"Connect an agent"** + subtitle **"One is
      enough to finish."**
- [ ] AC-2.3-b: **2-column** cards (only the agents chosen in 2.2), each with brand
      icon + name, a **spinner** top-right, and a second line **"Installing X
      hooks…"** during install.
- [ ] AC-2.3-c: Footer (shield glyph) **"Agent Island never receives agent provider
      credentials."**

## 2.4 A few preferences (#6)
- [ ] AC-2.4-a: Back button; title **"A few preferences"** + subtitle **"All
      optional. You can change these later in Settings."**
- [ ] AC-2.4-b: Two full-width dark rows: **"Notifications"** (green toggle, ON by
      default) and **"Launch at login"** (gray toggle, OFF by default).
- [ ] AC-2.4-c: Glossy white **"Continue"** pill completes onboarding.

---

## Open questions — resolve before/while building (do NOT guess)

- **Q1 — RESOLVED:** the red edge strips are the macOS screen-recording indicator,
  not design. Do **not** add red edges (see 1.9).
- **Q2 — RESOLVED (via agent-notch):** use the **system monospace**, not a licensed
  face. agent-notch renders the entire panel with
  `NSFont.monospacedSystemFont(ofSize:weight:)` (`main.swift:435`) and matches the
  mockups, so `.system(..., design: .monospaced)` is correct.
- **Q3 — RESOLVED:** no hamburger/menu button — the header right side is the gear
  (Settings) icon only.
- **Q4 — REFRAMED, not one question.** *"Don't we already have this from hooks, and
  isn't agent-notch's transcript reading a second source?"* — **largely yes, and the
  earlier framing of this question was too pessimistic.** Audited against the code,
  the data splits into four sources with very different maturity:

  **① Hooks — wired today.** `ClaudeCodeAdapter.swift:577` already parses **`model`**,
  `cwd`, session/turn/tool IDs, subagent lineage, timestamps, and background-task
  count from hook payloads. *Gap: `SessionProjection`
  ([Projection.swift:80–90](../../../src/Sources/SessionDomain/Projection.swift#L80))
  does **not** carry `model` through to the UI — so §1.6's model chip is **plumbing an
  existing value**, not acquiring new data.*

  **② Transcripts — not read at all; the biggest cheap win.** agent-notch proves how
  little it costs (`tailInfo`, `main.swift:136–168` — seek to the last 128 KB and
  parse backwards). Claude/Codex `.jsonl` transcripts carry per-message `usage`
  blocks and full message text, which would unblock §1.6 **token counts**, §1.10's
  **agent message body / You-prompt / transcript excerpt**, and historical charts.
  > ✅ **APPROVED — transcript reading is allowed.** Proceed. Two things still to
  > settle *while* building, not before: (a) how transcript-derived fields are
  > distinguished from hook-proven ones in the model, and (b) whether this warrants an
  > ADR, since it adds a second evidence path alongside "source-proven observations".
  > Copy agent-notch's `tailInfo` (`main.swift:136–168`) as the read strategy.

  **③ Claude statusline — install path exists, consumption doesn't.**
  `ClaudeStatusLineBridge.swift` manages installing/owning the statusline integration
  but never consumes its output. Claude Code's statusline JSON is the natural home for
  **cost, context %, and diff stats** (verify the exact field names). Finishing this
  path is the cleanest route to most of §1.6's line-2 strip.

  **④ Genuinely unsourced — real product work.** Nothing in hooks, transcripts, or the
  statusline provides: **the agents' subscription-plan quota** (`5H`/`7D`/`MO` percent
  consumed + reset/refill times, §1.4/§1.12 — that is provider quota state, not
  anything we observe locally); **memory / disk I/O** (§1.6 — OS process metrics); and
  the **per-model / per-token-class breakdown and histogram** (§1.12.1).
  *(Licensing/entitlement was previously listed here and is now **gone** — §1.8 and
  §1.11 are cut, so no monetization data model is needed at all.)*

  **Confirmed absent everywhere:** `grep` across `SessionDomain/`,
  `ClaudeCodeAdapter/`, `CodexCLIAdapter/` for `totalCost`, `inputTokens`,
  `contextWindow`, `gitBranch`, `linesAdded` returns **zero hits**. And `UsageSnapshot`
  ([UsageSnapshot.swift:7](../../../src/Sources/SessionDomain/UsageSnapshot.swift#L7))
  holds exactly one provider, one `usedPercent`/`remainingPercent`, one `resetsAt` —
  it cannot express §1.4 or §1.12 as drawn, regardless of source.

  **So the actionable question is no longer "who provides this data" but: do we
  approve reading transcripts (②) and finishing the statusline consumer (③)?** Those
  two decisions unblock most of §1.6 and §1.10. Only bucket ④ is true net-new work.
- **Q5 — RESOLVED.** Panel radius → **18** (AC-1.1-e). Claude brand salmon →
  **`#D97857`**, agent-notch's shipped value. **General rule established: where an
  `≈` estimate in this doc conflicts with a shipped agent-notch value, agent-notch
  wins** — its numbers are tuned against the real art. Remaining `≈` measures inherit
  that rule; no further sign-off needed.
- **Q6 — RESOLVED (both halves).** A menu-bar status item **already exists**
  ([AppDelegate.swift:812](../../../src/Sources/AgentIslandApp/AppDelegate.swift#L812)),
  currently backed by an `NSMenu` — §1.12 is a replacement, not an addition. And the
  **"Metrics" tab is now captured as #15** and specified in **§1.12.1**: per-provider
  cards with a headline token total (or % for quota-metered providers), a usage
  histogram, a dotted input/output/cache breakdown, and a per-model split ending in
  an `other` bucket. *(Its data is the deepest ask in the doc — see Q4 ④.)*
- **Q7 — RESOLVED: Codex brand = blue-violet `#6E63E6`.** Confirmed against the live
  build in #14 and #15, both of which render the Codex mark blue-violet. agent-notch's
  OpenAI teal `#0FA380` (`main.swift:462`) is **not** used — when porting its glyph
  code, retint. *(An earlier draft recorded teal; that decision was reversed.)*
- **Q8 — RESOLVED: bundling the Codex pet spritesheets is approved.** Port
  `drawCodexPet` and ship the `pets/*.webp` sheets. Keep `drawRing` as the runtime
  fallback for a missing/failed sprite load (agent-notch already degrades that way),
  and keep the sprite-selection config (`~/.config/agent-notch/pet` → an Agent Island
  equivalent) if we want the pet picker. Note the **~4–8 MB** app-size cost.
- **Q9 — RESOLVED: adopt the dithered pixel separator** (`DitherSeparator`, see
  §1.6) in place of the flat 1px hairline. This is an approved, deliberate deviation
  from the mockups — AC-1.6-a is amended accordingly.
- **Q10 — RESOLVED: the paginated wizard wins.**
  `VIBE_ISLAND_FUNCTIONALITY.md` §"Verified Claude multi-question wizard" is
  authoritative for §1.13 — one question at a time, Previous/Next, "Question N of M",
  progress dots, orange numbered option tiles. The **stacked** form in **#14**
  (radio circles, "0 of 3 answered", single Send) is a **stale build; do not build
  it.** No rewrite of the functionality doc is needed — it was right.
  > ✅ **Multi-select visual RESOLVED by #17: square checkboxes.** See AC-1.13-g.
- **Q11 — RESOLVED: hamburger stays OUT.** Q3 stands and AC-1.3-c is unchanged —
  the header right is the gear (plus §1.10's mute toggle) only. The hamburger visible
  in **#14** is a **stale build**, not a target. This is a standing reminder that #14
  must be read selectively (see the #14 note in the reference index).

## Work buckets — how to sequence Phase 1

*(Phase 2 is §1.7 + §1.13 together; see the delivery-phase table. These buckets
order the **Phase 1** work only.)*

**A — Port from agent-notch. Do this first; largest win, least risk.**
§1.1 surface + open/close animation · §1.2 pixel glyphs (`IndicatorView`) · §1.6 row
line-1 anatomy, the monospaced `label()` helper, `DitherSeparator`, `DitherIconView`,
`relative()`, the subagent disclosure · the `.darkAqua` appearance lock. Nearly all
copy-and-wrap, not design work.

**B — Net-new UI, fully specified, no data blocker.**
§1.2 collapsed-pill fill + wings + "N Sessions" text · §1.3 header row · §1.5 empty
state copy · the theme file itself (AC-TOKENS-1).

**C — Needs the data path finished first.**
§1.6 line-2 metadata strip · §1.10 focused-card body + transcript — **both unblocked
now that transcript reading is approved** (Q4 ②); §1.4 usage stats + §1.12 popover,
which still need provider **quota** state (Q4 ④ — the one genuinely unsourced input).

**Suggested order: A → B → C.** A+B alone land the two make-or-break anchors (opaque
black, monospaced) and are verifiable against #2/#7/#11 without any new data. C
follows as each data path lands.

**Then Phase 1B** (onboarding), **then Phase 2** (bidirectional).

**CUT — do not build.** §1.8 trial banner · §1.11 paywall · any diff/code-change
content. No monetization ships, so nothing is entitlement-gated and there is no
session cap.

## Definition of done — per phase

### Phase 1 — Display (50 ACs)
- [ ] The overlay renders **opaque near-black + monospaced** in every macOS
      appearance (Light/Dark/Increased-contrast/Reduce-transparency).
- [ ] Each **Phase-1** AC (§1.1–1.6, 1.9, 1.10, 1.12) is verified by side-by-side
      comparison to its cited reference image — **not** just by compiling.
- [ ] No overlay view references `.regularMaterial`, `.primary`, `.secondary`, or
      `Color.accentColor` for color (grep-clean); all values come from the theme file.
- [ ] `IslandOverlayPanel.swift:74` hit-test radius matches the drawn corner radius
      (both **18** — AC-1.1-e).
- [ ] Every ported piece is traceable to its `agent-notch/main.swift` source — the
      pixel-drawing `draw(_:)` bodies are copied **unchanged** (only wrapped in
      `NSViewRepresentable`), not reinterpreted as SwiftUI shapes.
- [ ] None of agent-notch's **session-scanning** code (`SessionScanner`, `:27–212`)
      was ported — hooks and (now-approved) transcript reads are the session sources.
- [ ] **A blocked session shows row status only** — no permission card, no question
      card, no action buttons anywhere in the build.
- [ ] Quota percentages honor the AC-1.4-f thresholds (green ≤60 / orange 60–80 /
      red 80+) everywhere a percentage renders.
- [ ] `swift build` succeeds from `src/`. (Note: `swift test` is unavailable in this
      environment — Command Line Tools only, no XCTest.)

### Phase 1B — Onboarding (11 ACs)
- [ ] Each §2.1–§2.4 AC matches its reference image (#3–#6).
- [ ] Onboarding renders in **SF Pro sans** on the warm charcoal background — it is
      deliberately **not** monospaced, unlike the overlay.

### Phase 2 — Bidirectional (19 ACs)
- [ ] The real command text (§1.7) and question prose + option labels (§1.13) are
      carried through the existing **`PayloadClassification.interactionContent`**
      path — the model was **extended**, not the UI downgraded.
- [ ] `GuidedChoice` carries a **description** (or descriptions were explicitly
      dropped with sign-off) — see §1.13.
- [ ] Allow/Deny and answer submission route through
      `ClaudeTypedHookResponse.permission(...)` / `.preToolAllow(updatedInput:)`,
      preserving the existing ownership/staleness guards
      (`ClaudeLiveActionRejection`).
- [ ] The wizard is **paginated** (Q10) and multi-select uses **checkboxes** (Q17) —
      no stacked form, per the stale #14 build.
- [ ] The flow **never opens a separate macOS dialog**; it stays in the notch surface.
- [ ] `swift build` succeeds from `src/`.

### Cross-cutting
- [ ] Nothing paywall-, trial-, licensing-, or entitlement-related exists anywhere
      in the build (§1.8/§1.11 are CUT).
- [ ] **No diff/code-change content** is rendered — the `+N −M` stat only.
