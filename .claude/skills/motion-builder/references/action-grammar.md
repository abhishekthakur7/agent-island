# Action Grammar — writing blocks that don't drift

An action block is pure choreography: WHO enters, WHAT it does, WHEN it settles.
The sheet + style lock already answered every "what does it look like" question.
Every style word you add fights the reference image and bloats 150 prompts.

**The test:** could this block render in ANY style family unchanged? If yes,
it's clean. "A card labeled 'TOOL CALLS' springs up" works on cream paper, on a
zine poster, in glass-dark. "A dark-glass card on cream paper springs up" only
works in one — and now it's fighting the sheet in the other ten.

---

## 1. Block shape (≤90 words, 3 moves)

Every clip is an arc that survives being cut mid-edit:

1. **ENTER** (0-1.5s) — elements arrive: spring up, slide in, draw on, tape down.
2. **TRANSFORM/HOLD** (middle) — the one idea happens: connect, split, count,
   compare, reveal. ONE idea. Two ideas = two blocks.
3. **SETTLE** (last 1s) — motion eases to a stable frame (cuttable) or returns
   to the first frame (`**LOOP:** yes`).

One camera behavior per clip, stated once: `slow push-in`, `static camera`,
`gentle drift left`, `whip to the right panel`. Multiple camera moves in 5s
reads as AI soup.

## 2. Vocabulary

**Objects by ROLE** (the sheet defines how each looks): card, panel, chip,
pill, tile, label, connector line, wire, node, meter, counter, chart, cutout,
sticker, tape strip, stroke, badge, stage.

**Layers** (matters for collage/stage families — the model composes better
when you name them):
- `BG` / "the stage" — never redescribed, it's locked in the style lock
- `MG` — cutouts, characters, the subjects
- `FG` — charts, counters, labels, props that sit in front

Example: `On the stage, MG: a halftone cutout of a container ship slides in
from the right. FG: a counter chip pops above it and ticks from $80 to $116.`

**Motion verbs** — pick from the family's bias (style-families.md):
springs up (overshoot) · slides in · pops · drops with a bounce · tapes down ·
stamps · draws on · writes on stroke-by-stroke · ticks up/down · fills ·
drains · snaps together · splits · flips · peels · sweeps · orbits · settles.

**Stagger rule:** elements never arrive simultaneously — `A, then B, then C,
staggered` is the single highest-value phrase in this system (it's what makes
motion feel designed rather than generated).

## 3. Text on screen

The model renders text it's told EXACTLY, and invents gibberish otherwise.

- Quote the exact string: `TEXT ON SCREEN: "TOOL CALLS"` — ≤4 words, ≤2 strings
  per clip.
- Bind it to a type role from the sheet: `as H1`, `as a label chip`, `as a
  counter`.
- Numbers are text: `the counter reads "$116"`.
- If no text is wanted: say `no text in frame` — silence invites the model to
  decorate with fake labels.
- Logos are never text: attach the file (`**REF:**`) and write `the attached
  <brand> logo, flat, unmodified`.

## 4. SFX line (2-4 cues, diegetic to the motion)

Sounds follow the choreography 1:1 — `**SFX:** paper pop on each entrance,
tick-tick on the counter, low room hum`. Never "music", "soundtrack", "voice".
Full palette in [audio-grammar.md](audio-grammar.md).

## 5. Worked examples

**BAD (style leaked in, from a real pack):**
> A cream-paper editorial desk fills the frame. Three dark-glass image cards
> slide in labeled "CODE," "AI," and "AGENTS." Thin blue/violet connector lines
> try to connect them. Premium tech-explainer style.

**GOOD (same clip, clean):**
```text
Three cards slide in from different edges, staggered, labeled "CODE", "AI",
"AGENTS" (label style). Connector lines start drawing between them, then pause
mid-route, leaving a readable tangle. Slow push-in. Settle on the tangle.
```
Everything removed (cream, dark-glass, blue/violet, premium style) is carried
by the sheet. Everything kept is choreography.

**BAD (two ideas, no arc):**
> A token meter drains while a warning appears, then a green path bypasses the
> AI and the meter refills and a checklist appears and gets checked off.

**GOOD (split into two blocks):**
```text
FG: a meter drains fast while a warning chip pops beside it, reading "TOO
EARLY" (label style). Static camera. Settle on the drained meter.
```
```text
A route line draws around a central node instead of through it; the meter
beside it refills. TEXT ON SCREEN: "CODE FIRST" (H2). Gentle drift right.
```

**GOOD (vox-collage, layers + stagger + logo):**
```text
On the stage, MG: halftone cutouts of two figures spring up left and right,
staggered, each with an offset stroke. FG: the attached handshake-treaty
document cutout drops between them with a bounce. TEXT ON SCREEN: "THE DEAL"
(headline). Static camera, slow 2% drift. Settle.
```

**GOOD (loopable buffer, P3):**
```text
FG: a meter idles at three-quarters full; every second a small chip detaches
and files itself into a slot below, staggered. No text in frame. Static camera.
```
`**LOOP:** yes` — last frame matches first.

## 6. Length discipline

≤90 words. `pack.py --check` warns at 120 — but 120 is failure, not budget.
Long blocks re-describe style (cut it), stack ideas (split it), or micro-manage
easing curve minutiae the model ignores anyway (delete it). The style lock +
action + SFX + negative assemble to ~300 words; that's the sweet spot where
Omni follows instructions instead of averaging them.
