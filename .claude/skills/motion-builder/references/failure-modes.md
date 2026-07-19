# Failure Modes — symptom → cause → fix

Diagnose before re-rolling. A re-roll with the same prompt re-rolls the same
failure ~70% of the time; a diagnosed one-line fix usually lands. Log new
sheet-specific failures to the sheet file's Gotchas section.

| Symptom | Cause | Fix |
|---|---|---|
| Gibberish / melted text | text not quoted, too long, or not bound to a type role | Quote exact string ≤4 words, add `(H1/H2/label)`, or remove text from the clip |
| Fake labels appear everywhere | block never mentioned text, model decorates | Add `no text in frame` to the action |
| Clip copies the sheet's LAYOUT (grid board look) | anchor line weakened or removed | Restore "do NOT copy the sheet's layout" in STYLE LOCK; make the action name a single composition |
| Style drifts from sheet | style words in the action fighting the ref | Strip every material/color/font word from the action (action-grammar §test) |
| Look flips between clips | sheet_ref missing on some blocks (t2v snuck in) or two sheets mixed | `pack.py --list` — check modes; one sheet per pack, ref2v default |
| Music appears | negative trimmed, or FAL run without negative param | Restore the five audio-ban terms; on FAL confirm `negative_prompt` is sent |
| A voice speaks over the clip | model narrates the VO line | Keep `**VO:**` OUT of the action text (pack.py never sends it); check you didn't paste VO into the fence |
| Chaotic camera / whip soup | multiple camera verbs, or none | Exactly one camera behavior per block, stated once |
| Everything moves at once | no stagger instruction | Add "staggered" / "A, then B, then C" |
| Motion feels floaty/weightless | no arrival language | Use landing verbs: springs with overshoot, drops with a bounce, snaps, settles |
| Clip unusable mid-edit (no clean out) | no settle beat | End actions with "settle on…" or mark `**LOOP:** yes` |
| Loop pops at the seam | loop flag missing (assembler adds seam line only then) | `**LOOP:** yes`, action returns to opening state |
| Logo redrawn wrong | logo described in words, not attached | `logos.py` fetch → `**REF:**` attach → "attached logo, flat, unmodified" |
| Wrong aspect out of Omni | sheet aspect ≠ delivery aspect | Regenerate sheet at the delivery aspect (9:16 project = 9:16 sheet) |
| v2v ignores the footage | video described at length so model re-invented it | Call it "the source footage", describe only the treatment/additions |
| v2v mangles readable UI text | stylize used on a screen recording | Switch to v2v-inset (footage stays raw inside a component) |
| Faces uncanny after stylize | family too photoreal-adjacent for face work | Use halftone/vector families for people, or v2v-overlay (face untouched) |
| Omni quota error | too many refs + video | ≤5 images when a video is attached (mg_gen enforces) |
| Kie task hangs >10 min | queue congestion | Cancel, retry once, then FAL fallback model or prompt_only |
| Upload rejected | file >100MB segment | Cut a shorter beat (`--cut-beats` spans one beat only) |
| Batch half-failed | rate limit / transient | mg_gen lists failures; re-run those ids with `--blocks` — never re-run `--all` |
| Everything renders but looks "AI-ish" | family physics mixed (glass glow in a paper world) | One family per sheet; strip off-family components from actions |

Re-roll etiquette: change exactly one thing per re-roll (the diagnosed fix).
If two re-rolls don't land, the block is fighting the family — rewrite the
choreography instead of sanding the words.
