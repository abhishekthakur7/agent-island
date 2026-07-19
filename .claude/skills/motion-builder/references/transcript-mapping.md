# Transcript Mapping — beats → blocks → priorities

The VO is the timeline (a beat maps to a visual — always). This file turns
`transcript.py` output into a pack that covers the whole video without
generating the whole video.

## 1. From segments to blocks

`transcript.py` gives you `<base>.segments.json`: beats (~5s, sentence-aligned),
pauses, keep-ranges. Walk the beats IN ORDER and give every one a decision:

| Decision | When | Pack entry |
|---|---|---|
| **generate** | the VO describes something abstract, structural, numeric, or metaphoric | block (t2v/ref2v) |
| **v2v** | real footage exists AND should stay visible (demo, talking head moment worth styling) | v2v block + `--cut-beats` clip |
| **talking head** | direct address, jokes, personal stories | coverage map row, no block |
| **screen recording** | live software walkthrough | coverage map row, no block |
| **reuse** | the idea repeats — an earlier clip or a P3 loop covers it | note "reuse B012" |

Rules of thumb: consecutive `generate` beats saying one idea → ONE block
spanning them (don't animate every sentence). A beat with a number in it
almost always wants a counter clip. A hard pause is a natural clip boundary —
never make a block straddle one. Emotional/personal beats resist graphics;
leave them on camera.

## 2. Priority rubric

**P1 — the edit cannot ship without it** (~15-25% of blocks):
opener + closer, every section title card, the recurring metaphor's
introduction, the core diagram of each section, any stat the video is built
around. Test: if this clip is missing, the section confuses people.

**P2 — support** (~40-50%): one-concept illustrations under explanatory VO,
secondary stats, comparison frames, v2v insets. Test: the section survives
on talking head, but the clip clearly earns its spot.

**P3 — texture** (rest): idle loops, buffers under long explanations,
transition wipes, recap tiles. Always `**LOOP:** yes` where possible — loops
get reused across the whole edit, which multiplies their value.

Budget for a 15-20 min explainer: 25-35 P1 · 40-60 P2 · 15-30 P3. If P1
exceeds ~35, you're calling everything essential and the tag stops meaning
anything — demote until it hurts.

## 3. The coverage map

Fill it segment by segment (segments = topic chunks, usually 30-90s each, not
individual beats). Every second of the timeline appears in exactly one row;
"plan" says generated / v2v / talking head / screen rec / reuse. This is what
lets the user say "render P1 only" and still know the whole video is covered —
coverage is a plan for every second, not a clip for every second.

Recommended mix (matches how these videos actually cut): 35-45% talking head +
screen rec, 35-45% generated, 10-20% loops/buffers/reuse.

## 4. VO lines in blocks

`**VO:**` carries the exact transcript sentence(s) the clip sits under —
trimmed to the relevant clause, no paraphrase. It's how the editor drops clips
onto the timeline without re-listening, and how you sanity-check that the
action visualizes THIS sentence, not the section's vibe.

## 5. Timing

Block `[t0–t1]` = the beat's span from segments.json, extended to the block's
real coverage when one block spans several beats. Clip duration stays the
pack default (5s) even when the span is longer — the editor loops/holds; you
don't stretch generation time to match VO length. When VO doesn't exist yet
(outline route): estimate at 150 wpm, mark `timing: draft`, re-map when the
recorded VO lands (`transcript.py` on the VO audio → update times, keep ids).

## 6. Worked mini-example

Segments S014-S016 (02:14-02:29):
> S014 "Level two is where tool calls come in." (pause 1.4s)
> S015 "Instead of guessing, the model asks your database first."
> S016 "So when a customer asks if something's in stock, it actually checks."

- S014 → **B012 · P1 · ref2v** — section title: card flips to "TOOL CALLS"
  (H2), staggered chips orbit in. Hard pause after = clean boundary.
- S015+S016 → one idea (lookup loop) → **B013 · P2 · ref2v** — wire draws
  from a chat bubble to a database tile and returns with a checkmark chip,
  counter reads "IN STOCK". Two beats, one block.
