# FAL.ai — fallback provider notes

FAL does NOT host Gemini Omni. A FAL batch means a different video model —
pass it explicitly (`mg_gen.py --provider fal --model <endpoint>`); there is
no silent substitution. When to use FAL: Kie is down/hanging, the user prefers
it, or a FAL-exclusive model fits the clip.

## Fallback video models (verify at https://fal.ai/models before big batches —
catalog moves fast; update this table when it drifts)

| Endpoint | Notes for motion graphics |
|---|---|
| `fal-ai/veo-3` | Closest to Omni output quality + native audio; higher cost; no video input |
| `fal-ai/kling-video/v2.1/master` | Strong image-to-video motion; takes `negative_prompt` param; text rendering weaker than Omni — keep on-screen text minimal |
| `fal-ai/bytedance/seedance/v1/pro/image-to-video` | Smooth cinematic moves; weakest text |

Capability loss vs Omni to flag at the review gate: **no v2v** on these
endpoints (v2v blocks stay on Kie or go prompt_only) and single reference
image (`image_url` — the sheet; logos can't ride along, so avoid logo blocks
on FAL batches).

## API pattern (mg_gen.py implements)

- Auth header: `Authorization: Key $FAL_KEY`
- Long-running models → queue: `POST https://queue.fal.run/<endpoint>` →
  `request_id` → poll `/requests/<id>/status` → fetch `/requests/<id>`.
  Short models → sync `https://fal.run/<endpoint>`.
- Video params: `prompt`, `image_url`, `duration` (string), `aspect_ratio`,
  `negative_prompt` (pack NEGATIVE goes here — pack.py skips the inline AVOID
  for FAL automatically via mg_gen).
- Storage: `POST https://fal.run/storage/upload` (multipart) → hosted URL.
  mg_gen uses this for uploads when FAL is the batch provider (and as fallback
  host when a Kie upload fails).

## Sheet images on FAL

`fal-ai/flux-pro/v1.1-ultra` renders good boards but weaker in-image
typography than nano-banana-pro (Kie). If the user is FAL-only, warn once
about type fidelity on the sheet, then proceed.
