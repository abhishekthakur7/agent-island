# Video-to-Video — putting the style ON footage

Omni accepts a video input (`video_list`) alongside the style sheet
(`image_urls`) — so real footage can be restyled, decorated, or framed inside
the visual system instead of living outside it. Source clips come from
`transcript.py --cut-beats` (per-beat) or `--cut` (pause-free keeps).

Quota per request: video = 2 units, each image = 1, cap 7, max ONE video.
Sheet + logo + video = 4 → always fits. mg_gen.py errors past the cap.

## The four sub-modes (pick in the block header)

### v2v-stylize — the footage becomes the graphic
The source is re-rendered inside the family (halftone, vector, painted). Use
for: b-roll that should feel native to the system, archival-look treatments,
title-sequence shots of the presenter.
```text
Re-render the source footage in the sheet's visual language: the subject
becomes a halftone cutout with an offset stroke, background replaced by the
stage. Keep the subject's motion and timing exactly. TEXT ON SCREEN: "PART 2"
(headline) slides in low. Settle.
```
Caution: faces survive stylization; fine detail (small UI text in the footage)
does not. Don't stylize screen recordings people must read.

### v2v-overlay — footage untouched, graphics on top
The source plays as-is; FG elements annotate it. Use for: callouts on demos,
stat chips over talking head, painted energy on real footage (paint-over-photo
family's home turf).
```text
The source footage plays unchanged. FG: a label chip pops top-left reading
"STEP 2", an arrow draws toward the cursor's path, staggered. No other
elements. Static camera (inherit the footage).
```

### v2v-transition — footage hands off to graphics (or back)
First half source, second half system — the bridge between talking head and
graphics sections. Use ~1 per section boundary.
```text
The source footage plays for the first two seconds, then the frame tears away
like paper revealing the stage; MG: a cutout of the presenter springs up where
they stood. TEXT ON SCREEN: "THE PLAN" (H2). Settle on the stage.
```

### v2v-inset — footage framed inside the system
The source lives inside a component (card, monitor, torn-edge window) while
graphics act around it. Use for: screen recordings that must stay readable,
picture-in-picture explanations.
```text
The source footage plays inside a card, MG center. FG: three label chips file
in beside it, staggered, reading "INPUT", "PROMPT", "OUTPUT". Slow push-in
toward the card. Settle with all three chips set.
```

## Block mechanics

Header: `### B031 · [04:05–04:10] · P2 · v2v-inset · video: segments/talk_beat_S049.mp4`
— path relative to the pack file; mg_gen.py uploads it and passes
`video_list: [{url, start: 0, ends: <clip len>}]`. Trim decisions happen in
`transcript.py` (cut the beat you want), not in the block.

In the action, call it **"the source footage"** — never describe its content
at length (the model can see it; describing it invites re-invention). Describe
only what CHANGES: the treatment, the additions, the handoff.

## Audio in v2v

Default (pack negative) still applies: generated audio is SFX only. When the
source's own audio matters (a demo's clicks, the presenter's voice), the edit
uses the ORIGINAL clip's audio track — tell the user to mute the generated
track for that clip rather than trying to make Omni preserve speech. Add
`**SFX:** none — original audio used in edit` to make it explicit in the
sidecar.

## When NOT to v2v

Readable UI text under stylize (use inset) · beats that work better fully
generated (v2v costs the same but constrains the result) · long segments —
one v2v clip covers one beat (~5s), not a 40s demo; for those the coverage
map says "screen recording" and the edit uses the raw footage.
