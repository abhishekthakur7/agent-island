---
name: motion-builder
description: "Style-locked motion-graphics director for AI video models (Gemini Omni on Kie.ai default, FAL fallback, prompt-only always free). Builds a MOTION SHEET — one master style-reference image locking typography, palette, surfaces, motion — then turns transcripts into PROMPT PACKS: style written once, blocks are action-only, time-coded to the VO, tagged P1/P2/P3 to render only what matters. Includes a style-family library (Vox-style cutout collage with locked stage, zine collage, paint-over-photo, kinetic type, more), real-logo fetcher, Whisper transcript extractor with pause detection and ffmpeg auto-cut, and video-to-video modes (stylize/overlay/transition/inset). Use for explainer B-roll, YouTube motion graphics, animated diagrams, kinetic typography, transcript-to-prompts, style guide images. Trigger on: motion graphics, mograph, B-roll, prompt pack, style lock, motion sheet, Omni video, collage explainer. Not for Remotion (separate skill) or live-action cinematics (use shot-builder)."
---

# Motion Builder — Style-Locked Motion Graphics Director

One idea drives this skill: **AI writes the action, code locks the look.**

A 20-minute explainer needs ~150 clips. Writing full style text into 150 prompts
wastes tokens, drifts the look, and buries the one thing that changes per clip —
the choreography. So the skill locks style ONCE into a **motion sheet** (a master
style-reference image + a short STYLE LOCK text), and every clip prompt is just an
**action block**. Scripts stack `STYLE LOCK + SHOT + AUDIO + AVOID` mechanically at
generation time. You never rewrite the look; you only direct the motion.

```
MOTION SHEET (image + style lock, made once)
        ↓ attached as reference to every clip
PROMPT PACK (.pack.md — style lock ×1, negative ×1, N action blocks,
             each time-coded to the VO, tagged P1/P2/P3, mode t2v/ref2v/v2v)
        ↓ pack.py assembles, mg_gen.py dispatches
CLIPS (Kie Omni default · FAL fallback · prompt-only free path)
```

---

## HARD RULES (READ FIRST, NEVER VIOLATE)

1. **NEVER skip the scripts.** If `setup.py`, `transcript.py`, `pack.py`, or
   `mg_gen.py` exists at `$SKILL_DIR/scripts/`, run it instead of doing the same
   job by hand. Scripts write canonical formats; hand-work drifts.
2. **NEVER put style words in an action block.** No colors, hex codes, fonts,
   materials, render adjectives ("glassy", "cream", "cinematic"). Style lives in
   the sheet + style lock only. An action block that says "dark-glass card"
   is a bug — say "a card". `pack.py --check` warns on hex codes; you enforce
   the rest. This is the #1 drift source and the whole point of the system.
3. **NEVER paraphrase or re-type the STYLE LOCK per clip.** It is written once
   in the pack; `pack.py` inlines it. Paraphrase = drift.
4. **No music, no narration in generated clips — ever — unless the user
   explicitly overrides.** Clips sit under the user's own voice-over. Audio is
   sound design only (whooshes, ticks, hums). The default NEGATIVE enforces it;
   don't remove those lines.
5. **NEVER batch-render without the review gate** (§STEP 4): show block count +
   cost estimate, ask which provider (config is `ask`-per-batch) and which
   scope (P1 / P1+P2 / all / cherry-pick). Never pass `--confirm-cost` without
   explicit user approval in this conversation.
6. **NEVER regenerate a locked motion sheet silently.** Regenerating changes
   every future clip. Confirm first, version it (`<SHEET>-ref_v2.png`), never
   overwrite.
7. **NEVER hand-edit INDEX.md** (state dir hot cache). Scripts manage it.
8. **NEVER delete files under the state dir or output dir** without explicit
   user confirmation in this turn.
9. **When stuck on format or naming, run a script — don't debate.**
   `pack.py --check` answers most arguments in one call.

---

## SCRIPT LOCATIONS

Set once per session:

```bash
SKILL_DIR="$HOME/.claude/skills/motion-builder"   # adjust to where this file lives
```

| Script | What it does |
|---|---|
| `"$SKILL_DIR/scripts/setup.py"` | Setup gate + project management (non-interactive flags supported) |
| `"$SKILL_DIR/scripts/transcript.py"` | Media/SRT/VTT → timestamped beats, pauses, auto-cuts |
| `"$SKILL_DIR/scripts/pack.py"` | Validate / list / stats / assemble prompt packs |
| `"$SKILL_DIR/scripts/mg_gen.py"` | Generate clips + sheet images via Kie / FAL / prompt-only |
| `"$SKILL_DIR/scripts/logos.py"` | Fetch real brand logos (Clearbit/SimpleIcons, no keys) as reference assets |

**State lives at `~/.frmwrkd/motion-builder/`** (or `$MOTION_BUILDER_HOME`) —
config.json, INDEX.md, `projects/<slug>/{sheets,packs,transcripts}/`. NOT inside
the skill directory: skill caches can be read-only. API keys are shared with
shot-builder at `~/.frmwrkd/.env` (`KIE_API_KEY`, `FAL_KEY`).

---

## STEP 0 — SETUP GATE (once)

Check config; if missing, gather answers and run setup **with flags** (there is
no TTY in most agent environments):

```bash
python "$SKILL_DIR/scripts/setup.py" --check || \
python "$SKILL_DIR/scripts/setup.py" --provider ask \
    --output-dir "<ask user — e.g. ~/Generated/motion-builder>" \
    --video-model gemini-omni-video --image-model nano-banana-pro \
    --aspect 16:9 --duration 5
```

Defaults worth defending: `gemini-omni-video` (best on-screen text + native SFX,
accepts image AND video input — Kie-only), `nano-banana-pro` for sheet images
(best typography rendering), 16:9 · 5s, audio = sound design without music.
Provider `ask` = user chooses kie / fal / prompt_only per render batch.
Keys: `python setup.py --set-key kie <KEY>` (chmod-600 to `~/.frmwrkd/.env`).
Re-run with `--reset` when the user says "switch provider", "change defaults".

## STEP 0.5 — PROJECT GATE (per session)

```bash
python "$SKILL_DIR/scripts/setup.py" --current   # empty? then:
python "$SKILL_DIR/scripts/setup.py" --list-projects
python "$SKILL_DIR/scripts/setup.py" --new-project "<name>" --switch
```

One video = one project, usually. Sheets are per-project; a sheet meant for a
whole channel can be copied between projects deliberately (say so when doing it).
Read `~/.frmwrkd/motion-builder/INDEX.md` at session start — it lists existing
sheets, packs, and recent renders so returning sessions skip straight to work.

---

## STEP 1 — MOTION SHEET GATE (the load-bearing step)

**Before composing anything, ask: "Do you already have a style reference image,
or do we build the motion sheet first?"** Every clip inherits its look from this
one image — a weak sheet makes 150 weak clips.

**REQUIRED READING before any sheet work:** [references/motion-sheet.md](references/motion-sheet.md)
AND [references/style-families.md](references/style-families.md). The first defines
the sheet file + master image prompt; the second gives the named style families
(paper-editorial, glass-dark, print-collage, blueprint, terminal-neon, soft-3d,
kinetic-type, grain-docu, iso-diagram) used to seed the interview.

Three routes:

- **(A) User has a reference image** → study it, transcribe the visual system
  into a sheet file (typography roles, palette, surfaces, component language,
  lighting, motion bias). Mirror back. Confirm. The image becomes `<SHEET>-ref`.
- **(B) Build from a style family** → pick family + brand inputs (logo? palette?
  tone?), fill the master-image prompt template, render via
  `mg_gen.py --type image`, review with the user, iterate max twice, lock.
- **(C) From scratch** → run the interview in motion-sheet.md (7 questions:
  family, surface, palette, type voice, logo, stage, energy), then as (B).

Two sheet-time decisions that shape everything downstream: **the stage**
(locked persistent background world = Vox-style "one continuous shot"
continuity; or free backgrounds per clip) and **the logo** (if the video shows
real brands, fetch exact marks now: `python "$SKILL_DIR/scripts/logos.py"
--brand slack --brand notion` — models drawing logos from memory produce
gibberish marks).

Save to `~/.frmwrkd/motion-builder/projects/<slug>/sheets/<SHEET>.md`. The file
contains the canonical description, the master image prompt, the **STYLE LOCK
block** (≤120 words — copied verbatim into every pack), the **NEGATIVE block**,
audio identity, and the ref image path. Sheet not approved = do not proceed.

## STEP 2 — INPUT GATE (what are we covering?)

Three input types, auto-detected from what the user gives you:

- **Film segment / media file** → run the extractor. It transcribes (Whisper),
  finds pauses, builds ~5s beats, and can cut the source for v2v use:
  ```bash
  python "$SKILL_DIR/scripts/transcript.py" --input talk.mp4 [--cut] [--cut-beats]
  ```
  Existing transcript? `--input talk.srt` or `--input talk.mp4 --transcript talk.vtt`
  (skips transcription, keeps media available for cutting).
- **Pasted transcript with timestamps** → save as `.srt`/`.vtt`/whisper-`.json`
  first, then run the extractor on it. No timestamps at all → treat as outline.
- **Outline / topic list (no VO yet)** → skip the extractor; author beats
  directly, timecodes approximate, mark the pack `timing: draft`.

Read [references/transcript-mapping.md](references/transcript-mapping.md) before
mapping beats to blocks — it holds the priority rubric and coverage rules.

## STEP 3 — COMPOSE THE PROMPT PACK

**REQUIRED READING:** [references/pack-format.md](references/pack-format.md) (exact
file grammar — `pack.py` parses it) AND [references/action-grammar.md](references/action-grammar.md)
(how to write blocks that don't drift). For any v2v block also read
[references/video2video.md](references/video2video.md).

You write ONE file: `projects/<slug>/packs/<video>.pack.md` containing
frontmatter (sheet, sheet_ref, model, aspect, duration) → STYLE LOCK (pasted
verbatim from the sheet) → NEGATIVE (sheet negative + family additions) →
COVERAGE MAP table → blocks. Per block you author ONLY:

- header: `### B012 · [02:14–02:19] · P1 · ref2v` (v2v adds `· video: <path>`)
- `**VO:**` the transcript line the clip sits under
- `**SFX:**` 2-4 sound-design cues (no music)
- `**REF:**` extra reference images for this block (logos, product shots) —
  optional; a pack-wide logo goes in `logo_ref:` frontmatter instead
- a fenced action block: pure choreography, ≤90 words, no style words

Priorities (full rubric in transcript-mapping.md): **P1** = section titles, core
diagrams, recurring metaphors, opener/closer — the clips the edit cannot live
without. **P2** = one-concept support beats. **P3** = idle loops, buffers,
transitions. A 15-min video lands around 25-35 P1 / 40-60 P2 / rest P3.
Cover the FULL timeline in the coverage map even where the plan is "talking
head" or "screen recording" — coverage means every second has a decision, not
that every second gets a generated clip.

Then validate — non-negotiable:

```bash
python "$SKILL_DIR/scripts/pack.py" --pack <file> --check
python "$SKILL_DIR/scripts/pack.py" --pack <file> --stats
```

## STEP 4 — REVIEW GATE (before ANY spend)

Show the user, bullet-form:

```
Pre-flight:
- **Sheet:** <SHEET> (ref: <path>) — locked <date>
- **Pack:** <file> — N blocks (P1 xx / P2 xx / P3 xx), modes: ref2v xx, v2v xx
- **Model:** gemini-omni-video · 16:9 · 5s · audio: SFX only
- **Est cost:** P1 only ≈ $X · P1+P2 ≈ $Y · all ≈ $Z  (from pack.py --stats)

Which provider for this batch — kie / fal / prompt_only?
And scope — P1 / P1+P2 / all / specific blocks?
```

Wait for both answers. `prompt_only` is always free and always available.
Skip the gate only for a single-block re-roll the user just asked for.

## STEP 5 — GENERATE

```bash
python "$SKILL_DIR/scripts/mg_gen.py" --pack <file> --priority P1 --provider kie
python "$SKILL_DIR/scripts/mg_gen.py" --pack <file> --blocks B003,B017 --provider fal --model <fal-video-model>
python "$SKILL_DIR/scripts/mg_gen.py" --pack <file> --all --provider prompt_only
```

The script uploads the sheet ref (and any v2v source clips) automatically,
nests Omni params under `input` (`image_urls`, `video_list`, duration-as-string),
polls, downloads to `<output_dir>/<date>/<project>/clips/`, writes a `.md`
sidecar per clip (prompt + block + cost — the audit trail), appends INDEX.md,
and enforces the cost gate (>$1/clip or >$2/batch refuses without
`--confirm-cost`). `--dry-run` prints payloads for free — use it when unsure.
Omni is **Kie-only**; a FAL batch needs a FAL model id
(see [providers/fal.md](providers/fal.md)). Details: [providers/omni.md](providers/omni.md).

Report results as: N saved, paths, failures with the failure-modes fix if any.

## STEP 6 — VIDEO-TO-VIDEO (footage in, styled motion out)

When the user wants their real footage transformed or decorated — read
[references/video2video.md](references/video2video.md), then pick the sub-mode in
the block header: `v2v-stylize` (restyle the footage), `v2v-overlay` (graphics
on top, footage untouched), `v2v-transition` (footage hands off to graphics),
`v2v-inset` (footage lives inside a styled card next to graphics). Source clips
come from `transcript.py --cut-beats`. Omni quota per request: sheet image (1) +
video (2) = 3 of 7 units — always fits.

---

## UNIVERSAL PROMPT RULES

1. **Action blocks: choreography only.** Objects by role (card, chip, line,
   panel, meter), one camera behavior, enter → transform → settle within the
   clip duration. See action-grammar.md.
2. **Text on screen is quoted and budgeted.** `TEXT ON SCREEN: "TOOL CALLS"
   (H2)` — exact string, ≤4 words, role from the sheet's type system. Unquoted
   text = the model invents gibberish.
3. **The sheet is a language, not a layout.** Style lock always contains the
   line "do NOT copy the sheet's layout"; never remove it.
4. **Audio = sound design.** Per-block SFX cues; never "music", never "voice".
5. **Real logos are attached, never described.** When clips show real brands,
   fetch the mark (`logos.py`), attach via `**REF:**`/`logo_ref:`, and prompt
   "the attached <brand> logo, flat, unmodified". Never let the model draw a
   logo from memory. Trademark clearance is the user's — mention once per
   project.
6. **One fenced code block per assembled prompt** when showing prompts in chat.
7. **Aspect is a parameter, not prompt text.** Omni inherits aspect from the
   attached sheet (another reason the sheet is 16:9 — or 9:16 for a Shorts
   project: match the sheet to the delivery format).

---

## REFERENCES (load on demand — pairings matter)

| File | Load when | Pair with |
|---|---|---|
| [references/motion-sheet.md](references/motion-sheet.md) | Any sheet work | style-families.md |
| [references/style-families.md](references/style-families.md) | Sheet interview, negatives | motion-sheet.md |
| [references/pack-format.md](references/pack-format.md) | Writing/editing any pack | action-grammar.md |
| [references/action-grammar.md](references/action-grammar.md) | Writing any block | audio-grammar.md |
| [references/transcript-mapping.md](references/transcript-mapping.md) | Beats → blocks, priorities | pack-format.md |
| [references/video2video.md](references/video2video.md) | Any v2v block | action-grammar.md |
| [references/audio-grammar.md](references/audio-grammar.md) | SFX lines, audio defaults | — |
| [references/failure-modes.md](references/failure-modes.md) | A render came back wrong | — |
| [providers/omni.md](providers/omni.md) | Omni params, quota, Kie API | — |
| [providers/fal.md](providers/fal.md) | FAL batches, fallback models | — |

---

## WHAT THIS SKILL DOES NOT DO

- **No Remotion / code-rendered animation** — that's the user's separate
  motion-graphics-code skill. This skill generates via video models.
- **No live-action cinematics, cast, locations** — that's shot-builder. If the
  request is about characters/scenes/photorealism, hand over.
- **No music generation, no voice-over** — VO is the user's own; music is post.
- **No editing timeline decisions** — the pack proposes coverage; the edit is
  the user's. transcript.py cuts source segments, it doesn't assemble edits.
- **No prompts over ~350 words assembled** — style lock ≤120, action ≤90,
  negative ≤80. If assembly balloons past that, the sheet is bloated: trim it.

## ERROR HANDLING

| Symptom | Fix |
|---|---|
| `No config` | STEP 0 with flags (non-interactive) |
| No active project | STEP 0.5 |
| `provider is 'ask'` error from mg_gen | You skipped the review gate — ask the user, pass `--provider` |
| Cost-gate refusal | Show the estimate, get approval, re-run with `--confirm-cost` |
| `No transcription backend` | `pip install faster-whisper --break-system-packages`, or ask for an SRT/VTT |
| ffmpeg missing on `--cut` | Install ffmpeg, or skip cutting (beats still work) |
| Kie 401 | Key invalid — `setup.py --set-key kie <KEY>` |
| Kie task hangs > timeout | Cancel; retry once; offer FAL fallback model or prompt_only |
| Upload fails on both providers | Check keys; files >100MB — cut a shorter segment |
| Render looks wrong | [references/failure-modes.md](references/failure-modes.md) — symptom→cause→fix, don't silently re-roll |
| Pack won't parse | `pack.py --check` line numbers; fix the pack, not the parser |

## SESSION FLOW (typical)

```
User: turn this talk into motion graphics  [drops talk.mp4]
  1. setup --check → ok. --current → empty → ask project → new "build-a-tool-2" --switch
  2. INDEX.md → no sheets. Ask: "style reference image already, or build the
     motion sheet first?" → user picks family "paper-editorial", has logo
  3. motion-sheet.md + style-families.md → interview → sheet file → mg_gen
     --type image → user approves v1 → locked <MG-EDITORIAL>
  4. transcript.py --input talk.mp4 --cut-beats → 142 beats, 12 hard pauses
  5. transcript-mapping + pack-format + action-grammar → write pack: 28 P1 /
     52 P2 / 21 P3, 9 v2v-inset blocks on demo moments → pack.py --check ✓
  6. Review gate: stats + cost → user: "kie, P1 only" → mg_gen --pack …
     --priority P1 --provider kie → 28 clips + sidecars, INDEX updated
  7. Report paths; offer P2 batch or re-rolls.
```
