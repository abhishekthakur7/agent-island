# Audio Grammar — sound design without music

Omni generates native audio. Undirected, it defaults to library-music beds and
random ambience — which collide with the user's VO and get muted in the edit
(wasted signal). Directed, it produces motion-synced SFX that make graphics
feel physical. So: every block carries an `**SFX:**` line, and the NEGATIVE
always ends with `no music, no soundtrack, no voice-over, no narration, no
lyrics`.

## The rule

**Sound follows choreography 1:1.** Each motion verb in the action gets at
most one cue; nothing sounds that didn't move. 2-4 cues per clip + one bed of
room tone. More cues than motions = noise.

## Palette by family bias

| Family | Entrances | Data/counters | Bed |
|---|---|---|---|
| paper-editorial | soft whoosh, paper slide | UI tick, gentle pulse | low room hum |
| vox-collage | paper pop, thwip, stamp | counter tick-tick | newsroom air |
| zine-collage | tape rip, slap, crumple | shutter click | print-shop rumble |
| ink-sport-vector | whip whoosh, impact thud | riser, hit | crowd air (no chants) |
| paint-over-photo | brush swipe, splat | marker squeak | stadium/street air |
| type-punch | deep thud, air riser | inversion snap | near-silence |
| flat-duotone | soft pop, bloop | light tick | airy tone |
| glass-dark | synthetic tick, data chirp | pulse, shimmer | server hum |
| blueprint | pencil scratch, ruler slide | stamp thunk | drafting-room quiet |
| terminal-neon | key clack, relay click | beep (short) | CRT hum |
| soft-3d | felt tap, boop | soft click | studio silence |

## Writing the SFX line

Bind cues to motions, order them like the action: `**SFX:** paper pop on each
card entrance, tick-tick as the counter climbs, low hum bed`. Loudness words
help (`soft`, `sharp`, `deep`); tempo words help (`sparse`, `on each`).
"Percussive, not musical" is the escape hatch when a family flirts with pitch
(soft-3d marimba taps): rhythm yes, melody never.

## Silence is valid

P3 loops and beds under dense VO often want `**SFX:** room tone only`. And v2v
blocks where the source's own audio will be used in the edit: `**SFX:** none —
original audio used in edit`.

## The assembly (automatic)

pack.py appends: `AUDIO: <your SFX line> — sound design only, no music, no
narration.` and the negative repeats the ban. Belt and suspenders — models
treat music as the default; two fences keep it out.

## User overrides

"Actually give this one music" → per-block: replace the SFX line with the
request and add `**REF:**`-style note in VO? No — simpler: the user override
goes in the action's AUDIO intent via SFX line (`**SFX:** driving percussion
bed`) AND remove the music lines from that pack's NEGATIVE copy for that
render (`--no-inline-negative` + FAL negative param without music terms, or a
one-off pack copy). Flag the collision with VO once; then do it.
