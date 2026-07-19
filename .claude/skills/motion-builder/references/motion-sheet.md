# The Motion Sheet — one image that locks the whole look

A motion sheet is to a motion-graphics video what a character sheet is to a cast:
the single reference every generation anchors to. It replaces ~1,000 words of
repeated style text with **one attached image + a ≤120-word STYLE LOCK**. The
image carries what words describe badly (texture, weight, spacing, glow); the
text carries what images can't enforce (rules, negatives, audio).

Pair this file with [style-families.md](style-families.md) — families seed
every route below.

---

## 1. Sheet file anatomy

Save to `~/.frmwrkd/motion-builder/projects/<slug>/sheets/<SHEET>.md`:

```markdown
---
sheet: MG-EDITORIAL
family: paper-editorial
created: 2026-07-02
ref_image: /path/to/MG-EDITORIAL-ref_001.png   # filled after render
logo: /path/to/assets/logos/frmwrkd.png        # optional, via logos.py
stage: locked                                   # locked | free (see §5)
---

# <SHEET> — canonical description
(6-10 lines of prose: surface, palette, type roles, component language,
lighting, texture. This is the human-readable source of truth.)

## Master image prompt
```text
(the prompt that generates/regenerates the ref image — §3)
```

## STYLE LOCK
```text
(≤120 words — copied VERBATIM into every pack — §4)
```

## NEGATIVE
```text
(base negative + family additions — audio lines are non-negotiable)
```

## Audio identity
(3-5 line SFX palette — see audio-grammar.md)

## Gotchas
(observed failure modes for THIS sheet — append as renders come back)
```

## 2. The interview (routes B and C)

Route A (user brings a reference image): don't interview — **transcribe**. Study
the image, write the canonical description, derive STYLE LOCK + NEGATIVE, mirror
back, confirm. The user's image becomes the ref; you may offer a cleanup render.

Otherwise ask, in one message, only what the family preset doesn't answer:

1. **Family** — show 3-4 candidates from style-families.md that fit the topic.
2. **Surface** — what is the world made of? (paper, void, glass, print, stage set)
3. **Palette** — brand colors to honor? Or adopt the family's.
4. **Typography voice** — shouty grotesk / editorial serif-mono mix / clean UI.
5. **Logo** — attach one? (fetch via `logos.py --brand <name>` if they name brands)
6. **Stage** — one persistent background world across all clips (Vox-style
   continuity, §5), or free backgrounds per clip?
7. **Energy** — calm-premium ↔ punchy-kinetic (sets motion verbs + SFX bias).

Mirror the answers as a draft canonical description. Confirm before rendering.

## 3. Master image prompt — template

Fill the slots; keep the whole prompt **400-600 words**. Past ~600 the image
model starts ignoring instructions — resist the urge to over-specify. The sheet
must read as a designed reference board, not a mood-board collage.

```text
MASTER STYLE SHEET — <project> visual system, one 16:9 reference board.
A single polished art-direction sheet that defines the visual language for a
video series. Editorial grid, consistent margins, section labels. Baked-in
typography is intentional here (this is a style guide).

SURFACE & MOOD: <family surface block — e.g. warm cream paper with subtle
fiber texture / flat cobalt print field with spray grain>. Mood: <3-4 adjectives>.

TYPE SPECIMEN PANEL: H1 sample "<2-3 word phrase>" in <family H1 treatment>;
H2 sample "<phrase>" in <treatment>; label and mono samples. Typography aligned,
sharp, no warped or melting letters.

PALETTE STRIP: labeled swatches — <named hex list>. <One line of semantic
rules, e.g. accent = AI concepts, green = automation>.

COMPONENT ZOO PANEL: <4-6 components from the family, each drawn once — e.g.
image card with label bar / stat chip / connector line / cutout with rough
keyline / tape strip / halftone portrait>. All share one construction logic.

MINI-SCENE PANEL: 3 small example frames showing the components composed:
<scene a>, <scene b>, <scene c>. Same lighting and finish in all three.

MOTION THUMBNAILS: 4 tiny storyboard frames with arrows only: <family motion
verbs — e.g. card springs up with overshoot / cutout slides in / line draws on /
counter ticks>.

<LOGO block if attached: "Use the attached logo exactly — flat, unmodified,
correct proportions, placed once in the header at ~6% width, generous clear
space. Never repeat it, never restyle it.">

<STAGE block if stage=locked: "One panel shows THE STAGE: the persistent
background world every clip lives on — <stage description>. Empty, pre-lit,
ready for elements to enter.">

FINISH: <family lighting/texture line — e.g. soft paper shadows, light film
grain, crisp edges>. No watermarks, no lorem ipsum, no unrelated logos, no
random gibberish text — every visible word is one of the samples above.
```

Render: `mg_gen.py --type image --provider <kie|fal> --model nano-banana-pro
--prompt "<...>" --aspect 16:9 --resolution 2k --label <SHEET>-ref`
(+ `--refs <logo.png>` when a logo is attached; match `--aspect` to the
delivery format — 9:16 project → 9:16 sheet, because Omni inherits aspect
from the attached reference).

**Approval loop:** show the render, ask what's off, fix ONLY those slots,
re-render. Two iterations is the norm; more means the family choice is wrong —
step back rather than sanding forever.

## 4. Writing the STYLE LOCK (≤120 words, exact job)

It rides above every action block, so every word is paid for N times. Structure:

1. **Anchor** (always first): `Use the attached style sheet as the strict
   visual system — match its <surface>, <palette summary>, <type voice>,
   <component language>, and <finish>. Do NOT copy the sheet's layout; it
   defines the language, not the composition.`
2. **Motion language** (one sentence): the family's verbs —
   `Motion: <springs with slight overshoot, staggered entrances, drawn-on
   lines; no chaotic camera>.`
3. **Stage** (if locked): `Every clip lives on the same <stage description>;
   the camera never cuts away from this world.`
4. **Audio rule** (always last): `Audio: sound design only — <family SFX bias>.
   No music. No voice-over.`

What does NOT belong: hex codes (the strip is in the image), font names (the
specimen is in the image), region layouts, per-clip anything.

## 5. The locked stage (Vox continuity)

The trick that makes 30 clips feel like one continuous take instead of 30 cuts:
**a persistent background world**. The background never changes; only midground
and foreground elements enter, act, and exit. Declare it in the sheet
(`stage: locked`), describe it once in the STYLE LOCK, and action blocks then
direct only the layers: "on the stage, a cutout of X springs up; a stat chip
pops beside it." Families built for this: vox-collage, paper-editorial,
type-punch. Free-stage families (grain-docu, glass-dark) change worlds per clip
— both are valid; it's decided at sheet time, not per block.

## 6. Real logos

When clips must show real product marks (Slack, Notion, OpenAI…), never let the
model draw them from memory — you get near-logos with mangled letterforms. Flow:

```bash
python "$SKILL_DIR/scripts/logos.py" --brand slack --brand notion
```

Then attach per block via `**REF:** assets/logos/slack.png` (or pack-wide via
`logo_ref:` frontmatter) and say in the action: `the attached <brand> logo,
flat and unmodified, on a <component role>`. Quota note: each ref image costs
1 Omni unit — sheet + 2 logos + video source = 5 of 7, still fine.
Trademark clearance is the user's call; mention it once per project, not per clip.

## 7. Versioning & regeneration

A locked sheet is load-bearing: regenerating it re-styles every future clip.
Never overwrite `<SHEET>-ref_001.png` — new renders get `_002`, `_003`, and the
sheet file's `ref_image:` pointer moves only on explicit user approval. Mid-video
sheet swaps make the edit visibly inconsistent; warn once, then obey.
