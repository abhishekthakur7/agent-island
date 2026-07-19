# Pack Format — the .pack.md grammar (pack.py parses this exactly)

One pack per video. The pack is self-contained: someone with only this file and
the sheet image can generate every clip. Save to
`~/.frmwrkd/motion-builder/projects/<slug>/packs/<video>.pack.md`.

## Template

````markdown
---
project: build-a-tool-2
video: Build a Tool Part 2
sheet: MG-EDITORIAL
sheet_ref: ../sheets/MG-EDITORIAL-ref_001.png
logo_ref: ../assets/logos/frmwrkd.png        # optional — attached to EVERY block
model: gemini-omni-video
aspect: 16:9
duration: 5
timing: final            # final = from transcript · draft = outline guesses
created: 2026-07-02
---

# Prompt Pack — Build a Tool Part 2

## STYLE LOCK
```text
(≤120 words, VERBATIM from the sheet file — never paraphrased)
```

## NEGATIVE
```text
(sheet negative incl. family additions; always ends with:
no music, no soundtrack, no voice-over, no narration, no lyrics)
```

## COVERAGE MAP

| Segment | Time | VO gist | Plan | Blocks |
|---|---|---|---|---|
| Intro | 00:00–00:41 | why agents confuse people | generated | B001–B006 |
| Demo | 00:41–02:10 | storyboard app walkthrough | screen rec + v2v insets | B007–B009 |
| … | … | … | talking head | — |

## BLOCKS

### B001 · [00:00–00:05] · P1 · ref2v
**VO:** "The US and Iran are signing a peace deal."
**SFX:** paper pop on each entrance, low hum
```text
(action — see action-grammar.md)
```

### B007 · [00:41–00:46] · P2 · v2v-inset · video: segments/talk_beat_S009.mp4
**VO:** "…so here's the interface doing exactly that."
**SFX:** soft whoosh, UI tick
**REF:** ../assets/logos/slack.png
```text
(action referencing "the source footage" — see video2video.md)
```

### B014 · [03:10–03:15] · P3 · ref2v
**LOOP:** yes
**SFX:** gentle ticks
```text
(idle buffer action, no text in frame)
```
````

## Parse rules (what pack.py actually reads)

- **Frontmatter**: `key: value` lines. `sheet_ref`/`logo_ref`/`video:` paths
  resolve relative to the pack file. `duration` int, `aspect` string.
- **`## STYLE LOCK`** and **`## NEGATIVE`**: first fenced code block after each
  heading. Both REQUIRED — `--check` fails without them.
- **Block header**: `### B001 · [00:00–00:05] · P1 · ref2v` —
  id `B###` (unique, three digits) · `[t0–t1]` in `mm:ss` or `h:mm:ss`
  (en-dash or hyphen) · priority `P1|P2|P3` · mode
  `t2v|ref2v|v2v|v2v-stylize|v2v-overlay|v2v-transition|v2v-inset`.
  Any v2v mode REQUIRES ` · video: <path>`. Separators `·` or `|`.
- **Optional lines** between header and fence: `**VO:**`, `**SFX:**`,
  `**LOOP:** yes`, `**REF:** path1, path2` (extra reference images for this
  block — logos, product shots).
- **Action**: the fenced block. Required, ≤90 words target (warn at 120).
- The COVERAGE MAP is for humans; the parser ignores it — but the skill treats
  a pack without one as unfinished.

## Assembly (what the model receives — code does this, never you)

```
<STYLE LOCK>

SHOT:
<action>

AUDIO: <SFX line> — sound design only, no music, no narration.

AVOID: <NEGATIVE>            ← inlined for Omni; FAL gets negative_prompt param
```

Plus attachments resolved by mg_gen.py: sheet_ref (+logo_ref, +REFs) as
`image_urls`, block video as `video_list`. Aspect rides on the sheet image.

## Validation & inspection

```bash
python "$SKILL_DIR/scripts/pack.py" --pack <f> --check          # errors + lint warns
python "$SKILL_DIR/scripts/pack.py" --pack <f> --stats          # counts + cost tiers
python "$SKILL_DIR/scripts/pack.py" --pack <f> --list --priority P1
python "$SKILL_DIR/scripts/pack.py" --pack <f> --assemble B001  # paste-ready prompt
```

`--check` before showing the user, every time. It catches: duplicate ids, bad
modes, v2v without video, missing fences, hex codes smuggled into actions,
time ranges that run backwards.

## Numbering & editing etiquette

Ids are stable once written — the edit references them ("re-roll B017").
Insert late blocks as B017b? No: renumber only before first render; after any
render, new blocks take the next free number (B090+ region is fine for adds).
Priorities may be re-tagged anytime (it's just a render filter). Timing column
`draft` → `final` once a real transcript lands; update times, keep ids.
