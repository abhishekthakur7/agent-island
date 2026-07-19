#!/usr/bin/env python3
"""
Motion Builder — generation dispatcher (Kie.ai / FAL.ai / prompt-only).

Renders prompt-pack blocks (or ad-hoc prompts) as motion-graphics clips, and
sheet images. Handles reference/sheet upload, video-to-video sources, cost
gates, polling, download, sidecars, and INDEX logging.

Batch from a pack (the normal path):
    python mg_gen.py --pack build-a-tool.pack.md --priority P1 --provider kie
    python mg_gen.py --pack build-a-tool.pack.md --blocks B001,B007 --provider fal
    python mg_gen.py --pack build-a-tool.pack.md --all --provider prompt_only
    python mg_gen.py --pack build-a-tool.pack.md --priority P1 --dry-run

Sheet image (master style reference):
    python mg_gen.py --type image --provider kie --model nano-banana-pro \\
        --prompt "<master sheet prompt>" --aspect 16:9 --resolution 2k --label MG-EDITORIAL-ref

Utilities:
    python mg_gen.py --type upload --file sheet.png --provider kie   # → hosted URL
    python mg_gen.py --type credit --provider kie                    # → balance

Notes:
  - `gemini-omni-video` uses Kie's jobs API with params nested under `input`
    (prompt, image_urls, video_list [{url,start,ends}], duration as STRING).
    Omni quota: images=1 unit, video=2, ≤7 total, max 1 video. Sheet + v2v = 3. OK.
  - Omni is Kie-only. If --provider fal is picked for a batch, pass a FAL video
    model via --model (see providers/fal.md fallbacks).
  - Cost gate: > $1.00/clip or > $2.00/batch estimated → refuses without
    --confirm-cost. Ask the user first; never pass it on your own.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (  # noqa: E402
    GATE_THRESHOLDS,
    MotionBuilderError,
    append_index_render,
    download_to_local,
    get_active_project,
    load_api_key,
    load_config,
    log_session_cost,
    price_for,
    resolve_output_dir,
    slugify,
    touch_index_modified,
    unique_path,
    upload_file,
    write_render_sidecar,
)

KIE_CREATE = "https://api.kie.ai/api/v1/jobs/createTask"
KIE_INFO = "https://api.kie.ai/api/v1/jobs/recordInfo"
KIE_CREDIT = "https://api.kie.ai/api/v1/chat/credit"
FAL_RUN = "https://fal.run"
FAL_QUEUE = "https://queue.fal.run"

# Kie models whose payload nests under "input" (modern jobs API)
KIE_INPUT_NESTED_PREFIXES = ("gemini-omni",)
# FAL endpoints that need the queue API
FAL_QUEUE_PREFIXES = ("fal-ai/kling-video/", "fal-ai/veo-", "fal-ai/bytedance/",
                      "fal-ai/runway", "fal-ai/minimax")


# -------------------------------------------------------------------- http

def _post(url: str, payload: dict, auth: str, timeout: int = 120) -> dict:
    req = urllib.request.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Authorization": auth, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise MotionBuilderError(f"{url} → HTTP {e.code}: {e.read().decode(errors='replace')}") from e


def _get(url: str, auth: str, params: dict | None = None) -> dict:
    if params:
        from urllib.parse import urlencode
        url = f"{url}?{urlencode(params)}"
    req = urllib.request.Request(url, headers={"Authorization": auth}, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:  # noqa: S310
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise MotionBuilderError(f"{url} → HTTP {e.code}: {e.read().decode(errors='replace')}") from e


# --------------------------------------------------------------------- kie

def kie_generate(model: str, params: dict, api_key: str,
                 poll: float, timeout: float) -> str:
    nested = any(model.startswith(p) for p in KIE_INPUT_NESTED_PREFIXES)
    payload = {"model": model, "input": params} if nested else {"model": model, **params}
    print(f"  payload: {json.dumps(payload)[:400]}", file=sys.stderr)
    body = _post(KIE_CREATE, payload, f"Bearer {api_key}")
    task_id = (body.get("data") or {}).get("taskId")
    if not task_id:
        raise MotionBuilderError(f"Kie createTask returned no taskId: {body}")
    print(f"  taskId: {task_id}", file=sys.stderr)

    deadline = time.time() + timeout
    while time.time() < deadline:
        info = _get(KIE_INFO, f"Bearer {api_key}", {"taskId": task_id})
        data = info.get("data") or {}
        status = (data.get("status") or data.get("state") or "").lower()
        if status in ("completed", "success"):
            return _kie_url(data)
        if status in ("failed", "fail", "error"):
            raise MotionBuilderError(f"Kie task {task_id} failed: {data.get('error') or data}")
        print(f"  status: {status or 'pending'}", file=sys.stderr)
        time.sleep(poll)
    raise MotionBuilderError(f"Kie task {task_id} timed out after {timeout}s")


def _kie_url(data: dict) -> str:
    result = data.get("result") or data.get("resultJson") or {}
    if isinstance(result, str):
        try:
            result = json.loads(result)
        except json.JSONDecodeError:
            if result.startswith("http"):
                return result
            result = {}
    if isinstance(result, dict):
        for key in ("url", "videoUrl", "video_url", "imageUrl", "image_url", "outputUrl"):
            if result.get(key):
                return result[key]
        for key in ("resultUrls", "result_urls", "urls", "files"):
            v = result.get(key)
            if isinstance(v, list) and v:
                return v[0]["url"] if isinstance(v[0], dict) else v[0]
    raise MotionBuilderError(f"no artifact URL in Kie result: {json.dumps(data)[:600]}")


# --------------------------------------------------------------------- fal

def fal_generate(model: str, params: dict, api_key: str,
                 poll: float, timeout: float) -> str:
    print(f"  payload: {json.dumps(params)[:400]}", file=sys.stderr)
    auth = f"Key {api_key}"
    if any(model.startswith(p) for p in FAL_QUEUE_PREFIXES):
        sub = _post(f"{FAL_QUEUE}/{model}", params, auth)
        rid = sub.get("request_id")
        if not rid:
            raise MotionBuilderError(f"FAL queue returned no request_id: {sub}")
        print(f"  queued: {rid}", file=sys.stderr)
        deadline = time.time() + timeout
        while time.time() < deadline:
            st = _get(f"{FAL_QUEUE}/{model}/requests/{rid}/status", auth)
            s = (st.get("status") or "").upper()
            if s == "COMPLETED":
                return _fal_url(_get(f"{FAL_QUEUE}/{model}/requests/{rid}", auth))
            if s == "FAILED":
                raise MotionBuilderError(f"FAL task failed: {st}")
            print(f"  status: {s}", file=sys.stderr)
            time.sleep(poll)
        raise MotionBuilderError(f"FAL queue timed out after {timeout}s")
    return _fal_url(_post(f"{FAL_RUN}/{model}", params, auth, timeout=int(timeout)))


def _fal_url(result: dict) -> str:
    for k in ("images", "videos"):
        if result.get(k):
            return result[k][0]["url"]
    for k in ("image", "video", "audio"):
        if isinstance(result.get(k), dict) and result[k].get("url"):
            return result[k]["url"]
    if isinstance(result.get("url"), str):
        return result["url"]
    raise MotionBuilderError(f"no artifact URL in FAL response: {list(result.keys())}")


# ----------------------------------------------------------- param builders

def video_params(provider: str, model: str, prompt: str, *, image_urls: list[str],
                 video_url: str | None, video_ends: float | None, duration: int,
                 aspect: str | None, negative: str | None,
                 extra: dict | None) -> dict:
    if provider == "kie" and model.startswith("gemini-omni"):
        p: dict[str, Any] = {"prompt": prompt, "duration": str(duration)}
        if image_urls:
            p["image_urls"] = image_urls  # quota: 1 unit each (sheet + logo + extra refs)
        if video_url:
            p["video_list"] = [{"url": video_url, "start": 0,
                                "ends": round(video_ends or duration, 2)}]
        # aspect: Omni follows the attached sheet's aspect; extra fields via --extra-json
    elif provider == "kie":
        p = {"prompt": prompt, "duration": duration}
        if image_urls:
            p["imageUrl"] = image_urls[0]  # legacy Kie video models take one reference
        if aspect:
            p["aspectRatio"] = aspect
    else:  # fal
        p = {"prompt": prompt, "duration": str(duration)}
        if image_urls:
            p["image_url"] = image_urls[0]
        if aspect:
            p["aspect_ratio"] = aspect
        if negative:
            p["negative_prompt"] = negative
    if extra:
        p.update(extra)
    return p


def image_params(provider: str, model: str, prompt: str, *, aspect: str | None,
                 resolution: str | None, refs: list[str] | None, extra: dict | None) -> dict:
    if provider == "kie":
        p: dict[str, Any] = {"prompt": prompt}
        if resolution:
            p["resolution"] = resolution
        if aspect:
            p["aspectRatio"] = aspect
        if refs:
            p["referenceImages"] = refs
    else:
        p = {"prompt": prompt}
        if aspect:
            p["aspect_ratio"] = aspect
        if refs:
            p["image_urls"] = refs
    if extra:
        p.update(extra)
    return p


# ------------------------------------------------------------------- runner

def ensure_hosted(path_or_url: str, provider: str, config: dict,
                  cache: dict[str, str], base_dir: Path,
                  dry_run: bool = False) -> str:
    if path_or_url.startswith(("http://", "https://")):
        return path_or_url
    p = Path(path_or_url).expanduser()
    if not p.is_absolute():
        p = (base_dir / p).resolve()
    if dry_run:
        return f"file://{p}"  # no upload, no existence check — payload preview only
    key = str(p)
    if key not in cache:
        print(f"  uploading {p.name}…", file=sys.stderr)
        cache[key] = upload_file(p, provider, config)
    return cache[key]


def run_block(block: dict, provider: str, config: dict, args: argparse.Namespace,
              upload_cache: dict[str, str]) -> Path:
    model = args.model or block.get("model") or config["defaults"]["video_model"]
    duration = args.duration or block.get("duration") or config["defaults"]["duration"]
    aspect = args.aspect or block.get("aspect") or config["defaults"]["aspect"]
    pack_dir = Path(block["pack"]).expanduser().parent if block.get("pack") else Path.cwd()

    image_urls: list[str] = []
    if block.get("mode") != "t2v" and block.get("sheet_ref"):
        image_urls.append(ensure_hosted(block["sheet_ref"], provider, config,
                                        upload_cache, pack_dir, args.dry_run))
    for ref in ([block.get("logo_ref")] + list(block.get("refs") or [])):
        if ref:
            image_urls.append(ensure_hosted(ref, provider, config, upload_cache,
                                            pack_dir, args.dry_run))
    video_url = None
    video_ends = None
    if block.get("mode", "").startswith("v2v"):
        video_url = ensure_hosted(block["video"], provider, config, upload_cache,
                                  pack_dir, args.dry_run)
        video_ends = min(float(duration), block["t1"] - block["t0"]) or duration
        if len(image_urls) > 5:  # Omni quota: images + video×2 ≤ 7
            raise MotionBuilderError(
                f"{block['id']}: {len(image_urls)} image refs + 1 video exceeds Omni's "
                f"7-unit quota (video costs 2). Drop refs to ≤5.")

    params = video_params(
        provider, model, block["prompt"], image_urls=image_urls, video_url=video_url,
        video_ends=video_ends, duration=int(duration), aspect=aspect,
        negative=block.get("negative"), extra=json.loads(args.extra_json) if args.extra_json else None)

    label = slugify(f"{block['id']}_{Path(block['pack']).stem if block.get('pack') else args.label}")
    out_dir = resolve_output_dir("clips", config, project=args.project)
    target = unique_path(out_dir, label, "mp4")

    if args.dry_run:
        print(f"[dry-run] {block['id']} → {provider}/{model}\n"
              f"{json.dumps(params, indent=2)[:800]}\n", file=sys.stderr)
        return target

    api_key = load_api_key(provider, config)
    poll, timeout = 5.0, args.timeout or 600.0
    if provider == "kie":
        url = kie_generate(model, params, api_key, poll, timeout)
    else:
        url = fal_generate(model, params, api_key, poll, timeout)
    download_to_local(url, target)
    print(f"  saved: {target}", file=sys.stderr)

    cost = price_for(model, config)
    project = args.project or get_active_project(config) or "_unsorted"
    write_render_sidecar(
        target, provider=provider, model=model, render_type="video", project=project,
        prompt=block["prompt"], cost_usd=cost, block_id=block["id"],
        sheet=block.get("sheet"),
        settings={"duration": duration, "aspect": aspect, "mode": block.get("mode"),
                  "video_source": block.get("video"), "vo": block.get("vo")})
    append_index_render({"date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                         "provider": provider, "model": model, "project": project,
                         "block": block["id"], "format": "video",
                         "cost": f"${cost:.2f}" if cost else "—", "path": str(target)})
    touch_index_modified()
    if cost:
        log_session_cost({"provider": provider, "model": model, "type": "video",
                          "cost_usd": cost, "block": block["id"], "path": str(target)})
    return target


def run_prompt_only(block: dict, config: dict, args: argparse.Namespace) -> Path:
    out_dir = resolve_output_dir("prompts", config, project=args.project)
    label = slugify(f"{block['id']}_{Path(block['pack']).stem if block.get('pack') else 'prompt'}")
    base = unique_path(out_dir, label, "md").with_suffix("")
    project = args.project or get_active_project(config) or "_unsorted"
    sidecar = write_render_sidecar(
        base, provider="prompt-only", model=block.get("model") or "—", render_type="video",
        project=project, prompt=block["prompt"], cost_usd=0.0, block_id=block["id"],
        sheet=block.get("sheet"),
        settings={"duration": block.get("duration"), "aspect": block.get("aspect"),
                  "mode": block.get("mode"), "video_source": block.get("video")})
    return sidecar


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", choices=["video", "image", "upload", "credit"], default="video")
    ap.add_argument("--provider", choices=["kie", "fal", "prompt_only"])
    ap.add_argument("--model")
    ap.add_argument("--prompt", help="ad-hoc prompt (bypasses --pack)")
    ap.add_argument("--label", default="clip")
    # pack batch
    ap.add_argument("--pack", help="prompt pack .md")
    ap.add_argument("--priority", help="P1 or P1,P2")
    ap.add_argument("--blocks", help="B001,B004")
    ap.add_argument("--all", action="store_true")
    # generation params
    ap.add_argument("--aspect")
    ap.add_argument("--duration", type=int)
    ap.add_argument("--resolution", help="image only: 1k/2k/4k")
    ap.add_argument("--image-url", help="ad-hoc reference image URL/path")
    ap.add_argument("--video-url", help="ad-hoc v2v source URL/path")
    ap.add_argument("--refs", nargs="+", help="image-gen reference URLs/paths")
    ap.add_argument("--extra-json", help='merge extra fields into params, e.g. \'{"seed":42}\'')
    ap.add_argument("--timeout", type=float)
    ap.add_argument("--project")
    ap.add_argument("--confirm-cost", action="store_true",
                    help="bypass cost gate (only after explicit user approval)")
    ap.add_argument("--dry-run", action="store_true", help="print payloads, no API calls")
    ap.add_argument("--file", help="--type upload: local file")
    args = ap.parse_args()

    config = load_config()
    provider = args.provider or (config["provider"]["primary"]
                                 if config["provider"]["primary"] not in ("ask",) else None)
    if not provider and args.type != "credit":
        raise MotionBuilderError(
            "provider is 'ask' — pass --provider kie|fal|prompt_only for this batch "
            "(ask the user which one).")

    if args.type == "credit":
        key = load_api_key("kie", config)
        print(json.dumps(_get(KIE_CREDIT, f"Bearer {key}"), indent=2))
        return 0

    if args.type == "upload":
        if not args.file:
            ap.error("--type upload requires --file")
        print(upload_file(Path(args.file), provider or "kie", config))
        return 0

    if args.type == "image":
        if not args.prompt:
            ap.error("--type image requires --prompt")
        model = args.model or config["defaults"]["image_model"]
        refs = None
        cache: dict[str, str] = {}
        if args.refs:
            refs = [ensure_hosted(r, provider, config, cache, Path.cwd()) for r in args.refs]
        params = image_params(provider, model, args.prompt, aspect=args.aspect or "16:9",
                              resolution=args.resolution or "2k", refs=refs,
                              extra=json.loads(args.extra_json) if args.extra_json else None)
        out_dir = resolve_output_dir("sheets", config, project=args.project)
        target = unique_path(out_dir, slugify(args.label), "png")
        if args.dry_run:
            print(json.dumps(params, indent=2))
            return 0
        api_key = load_api_key(provider, config)
        url = (kie_generate(model, params, api_key, 2.0, args.timeout or 180.0)
               if provider == "kie" else
               fal_generate(model, params, api_key, 2.0, args.timeout or 180.0))
        download_to_local(url, target)
        cost = price_for(model, config)
        project = args.project or get_active_project(config) or "_unsorted"
        write_render_sidecar(target, provider=provider, model=model, render_type="image",
                             project=project, prompt=args.prompt, cost_usd=cost,
                             settings={"aspect": args.aspect, "resolution": args.resolution})
        append_index_render({"date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                             "provider": provider, "model": model, "project": project,
                             "block": "—", "format": "image",
                             "cost": f"${cost:.2f}" if cost else "—", "path": str(target)})
        touch_index_modified()
        print(str(target))
        return 0

    # ---- video
    blocks: list[dict]
    if args.pack:
        import pack as packmod
        parsed = packmod.parse_pack(Path(args.pack).expanduser())
        errors = packmod.check_pack(parsed)
        if errors:
            for e in errors:
                print(f"error: {e}", file=sys.stderr)
            return 2
        if not (args.priority or args.blocks or args.all):
            raise MotionBuilderError("pick a render scope: --priority P1 / --blocks B001,… / --all")
        selected = packmod.filter_blocks(parsed, args.priority, args.blocks, None)
        inline_neg = provider != "fal"  # FAL models take negative_prompt as a param
        blocks = packmod.emit_blocks(parsed, selected, inline_negative=inline_neg)
    elif args.prompt:
        blocks = [{"id": "ADHOC", "prompt": args.prompt, "mode": "ref2v" if args.image_url else "t2v",
                   "sheet_ref": args.image_url, "video": args.video_url,
                   "t0": 0, "t1": args.duration or config["defaults"]["duration"],
                   "negative": None, "sheet": None, "model": args.model,
                   "aspect": args.aspect, "duration": args.duration, "pack": None,
                   "vo": None, "sfx": None, "loop": False, "refs": args.refs or [],
                   "logo_ref": None}]
        if args.video_url:
            blocks[0]["mode"] = "v2v"
    else:
        ap.error("--type video needs --pack or --prompt")
        return 1

    if not blocks:
        print("no blocks matched the filter", file=sys.stderr)
        return 1

    # cost gate
    model = args.model or (blocks[0].get("model")) or config["defaults"]["video_model"]
    unit = price_for(model, config) or 0.5
    total = unit * len(blocks)
    print(f"→ {len(blocks)} clip(s) via {provider}/{model} — est ${total:.2f} "
          f"(~${unit:.2f}/clip)", file=sys.stderr)
    if provider != "prompt_only" and not args.dry_run and not args.confirm_cost:
        if unit > GATE_THRESHOLDS["clip"] or total > GATE_THRESHOLDS["batch"]:
            raise MotionBuilderError(
                f"estimated ${total:.2f} exceeds gate (clip ${GATE_THRESHOLDS['clip']:.2f} / "
                f"batch ${GATE_THRESHOLDS['batch']:.2f}). Get explicit user approval, then "
                f"re-run with --confirm-cost.")

    upload_cache: dict[str, str] = {}
    results: list[Path] = []
    failures: list[str] = []
    for i, block in enumerate(blocks):
        print(f"\n[{i + 1}/{len(blocks)}] {block['id']} ({block.get('mode')})", file=sys.stderr)
        try:
            if provider == "prompt_only":
                results.append(run_prompt_only(block, config, args))
            else:
                results.append(run_block(block, provider, config, args, upload_cache))
                if i + 1 < len(blocks):
                    time.sleep(1.0)  # stay under rate limits
        except MotionBuilderError as e:
            failures.append(f"{block['id']}: {e}")
            print(f"  FAILED: {e}", file=sys.stderr)

    for r in results:
        print(str(r))
    if failures:
        print(f"\n{len(failures)} failed:", file=sys.stderr)
        for f in failures:
            print(f"  {f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MotionBuilderError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
