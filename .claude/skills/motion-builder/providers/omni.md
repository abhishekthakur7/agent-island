# Gemini Omni Video — provider notes (Kie.ai, verified 2026-07)

The default video model. Why it's the default for motion graphics: best-in-class
on-screen text rendering, native audio generation (steerable to pure SFX),
and true multimodal input — reference images AND a source video in one request.
**Kie-only** — not on FAL (see [fal.md](fal.md) for fallbacks).

## Endpoint & payload (params nest under `input` — unlike legacy Kie models)

```
POST https://api.kie.ai/api/v1/jobs/createTask
Authorization: Bearer $KIE_API_KEY
{
  "model": "gemini-omni-video",
  "input": {
    "prompt": "<assembled: style lock + SHOT + AUDIO + AVOID>",
    "image_urls": ["<sheet ref>", "<logo>", "..."],
    "video_list": [{ "url": "<source>", "start": 0, "ends": 5 }],
    "duration": "5"
  }
}
→ { "data": { "taskId": "..." } }
Poll: GET /api/v1/jobs/recordInfo?taskId=...   (pending→processing→completed)
```

Gotchas mg_gen.py already handles — listed so you don't "fix" them:

- **`duration` is a STRING** ("5"), not an int.
- **`video_list` uses `ends`** (not `end`), max ONE video per request.
- **Quota: 7 units** — image=1 each, video=2, character_id=1 (≤3).
  Sheet+logo+video = 4. mg_gen errors at >5 images with a video.
- **No documented `negative_prompt` param** → negative rides inline as the
  AVOID line (pack.py default).
- **No documented aspect param** → output follows the attached sheet's aspect.
  This is why the sheet renders at the delivery aspect. Extra/new params
  (seed etc.) can be passed via `mg_gen.py --extra-json '{...}'` if Kie adds
  them — check https://docs.kie.ai/market/gemini-omni-video for updates.
- Reference URLs must be **public** — mg_gen uploads local files first
  (Kie upload API: `https://kieai.redpandaai.co/api/file-stream-upload`,
  same Bearer key, ~24-72h retention — fine, we generate immediately).
- Result files expire (~14 days) — mg_gen downloads immediately; never store
  a Kie URL as the artifact.

## Related endpoints (not wired in — mention if the user asks)

`gemini-omni-audio` (audio generation → `audio_ids`) and
`gemini-omni-character` (persistent character ids). Character ids could lock a
recurring mascot/presenter across clips — a future upgrade; note it, don't
improvise it.

## Pricing

Not published per-clip at research time. Config default estimates $0.50/clip
(`config["pricing"]` overrides). Calibrate once: check
`mg_gen.py --type credit` before/after a clip, set the real number, and the
cost gates become accurate. Kie credit ≈ $0.005/credit.

## Polling & limits

Video poll 5s / timeout 600s (mg_gen defaults) · rate limit ~20 req/10s
(mg_gen sleeps 1s between submits) · 401 → re-enter key
(`setup.py --set-key kie <KEY>`) · task `failed` → read the error, diagnose
via failure-modes.md, don't blind-retry.
