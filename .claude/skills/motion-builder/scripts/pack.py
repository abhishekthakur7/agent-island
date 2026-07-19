#!/usr/bin/env python3
"""
Motion Builder — prompt-pack parser / validator / assembler.

The pack (.pack.md) is the single deliverable the AI writes: STYLE LOCK once,
NEGATIVE once, then action-only blocks. This script is the "code writes the
look" half of the system — it mechanically stacks
    STYLE LOCK + SHOT (action) + AUDIO (sfx) + AVOID (negative)
so no style text is ever rewritten per shot.

Block header grammar (parsed):
    ### B001 · [00:00–00:05] · P1 · ref2v
    ### B002 · [00:05–00:12] · P2 · v2v-overlay · video: segments/talk_beat_S002.mp4
Separators: " · " or " | ". Time range dash: – or -. Modes:
    t2v | ref2v | v2v | v2v-stylize | v2v-overlay | v2v-transition | v2v-inset
Optional lines between header and the fenced action block:
    **VO:** "..."      **SFX:** ...      **LOOP:** yes

Usage:
    python pack.py --pack <file> --check
    python pack.py --pack <file> --list [--priority P1] [--mode v2v]
    python pack.py --pack <file> --stats
    python pack.py --pack <file> --assemble B001 [--inline-negative]
    python pack.py --pack <file> --emit [--priority P1,P2] [--blocks B001,B002]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import MotionBuilderError, parse_ts, price_for  # noqa: E402

MODES = {"t2v", "ref2v", "v2v", "v2v-stylize", "v2v-overlay", "v2v-transition", "v2v-inset"}
HEADER_RE = re.compile(r"^###\s+(B\d{3})\s*[·|]\s*\[([^\]–-]+)[–-]([^\]]+)\]"
                       r"\s*[·|]\s*(P[123])\s*[·|]\s*([a-z2-]+)(?:\s*[·|]\s*video:\s*(.+?))?\s*$")
FENCE_RE = re.compile(r"^```")
HEX_RE = re.compile(r"#[0-9a-fA-F]{6}\b")


def _frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    meta: dict = {}
    for line in text[3:end].strip().splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip('"')
    return meta, text[end + 4:]


def _fenced_section(body: str, heading: str) -> str | None:
    m = re.search(rf"^##\s+{re.escape(heading)}\s*\n+```[a-z]*\n(.*?)\n```",
                  body, re.MULTILINE | re.DOTALL)
    return m.group(1).strip() if m else None


def parse_pack(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    meta, body = _frontmatter(text)
    style = _fenced_section(body, "STYLE LOCK")
    negative = _fenced_section(body, "NEGATIVE")

    blocks: list[dict] = []
    lines = body.splitlines()
    i = 0
    while i < len(lines):
        m = HEADER_RE.match(lines[i])
        if not m:
            i += 1
            continue
        bid, t0s, t1s, prio, mode, video = m.groups()
        block: dict = {
            "id": bid,
            "t0": parse_ts(t0s.strip()),
            "t1": parse_ts(t1s.strip()),
            "priority": prio,
            "mode": mode,
            "video": video.strip() if video else None,
            "vo": None, "sfx": None, "loop": False, "refs": [], "action": None,
            "line": i + 1,
        }
        i += 1
        # metadata lines until fence
        while i < len(lines) and not FENCE_RE.match(lines[i]):
            ln = lines[i].strip()
            if ln.startswith("**VO:**"):
                block["vo"] = ln[7:].strip().strip('"“”')
            elif ln.startswith("**SFX:**"):
                block["sfx"] = ln[8:].strip()
            elif ln.startswith("**LOOP:**"):
                block["loop"] = ln[9:].strip().lower() in ("yes", "true", "1")
            elif ln.startswith("**REF:**"):
                block["refs"] = [r.strip() for r in ln[8:].split(",") if r.strip()]
            elif ln.startswith("### "):
                break
            i += 1
        # fenced action
        if i < len(lines) and FENCE_RE.match(lines[i]):
            i += 1
            action_lines = []
            while i < len(lines) and not FENCE_RE.match(lines[i]):
                action_lines.append(lines[i])
                i += 1
            i += 1  # closing fence
            block["action"] = "\n".join(action_lines).strip()
        blocks.append(block)

    return {"path": str(path), "meta": meta, "style": style,
            "negative": negative, "blocks": blocks}


# ------------------------------------------------------------------ checks

def check_pack(pack: dict) -> list[str]:
    errors: list[str] = []
    warns: list[str] = []
    if not pack["style"]:
        errors.append("missing `## STYLE LOCK` fenced section")
    if not pack["negative"]:
        errors.append("missing `## NEGATIVE` fenced section")
    if not pack["blocks"]:
        errors.append("no blocks parsed — check `### B### · [t0–t1] · P# · mode` headers")

    seen: set[str] = set()
    for b in pack["blocks"]:
        where = f"{b['id']} (line {b['line']})"
        if b["id"] in seen:
            errors.append(f"duplicate id {where}")
        seen.add(b["id"])
        if b["mode"] not in MODES:
            errors.append(f"{where}: unknown mode '{b['mode']}'")
        if b["mode"].startswith("v2v") and not b["video"]:
            errors.append(f"{where}: v2v block without `video:` path")
        if not b["action"]:
            errors.append(f"{where}: no fenced action block")
        elif len(b["action"].split()) > 120:
            warns.append(f"{where}: action is {len(b['action'].split())} words — "
                         f"actions should stay ≤ ~90 (style lives in the lock, not here)")
        if b["action"] and HEX_RE.search(b["action"]):
            warns.append(f"{where}: hex color in action — palette belongs to the STYLE LOCK")
        if b["t1"] <= b["t0"]:
            errors.append(f"{where}: time range ends before it starts")
    for w in warns:
        print(f"warn: {w}", file=sys.stderr)
    return errors


# ---------------------------------------------------------------- assembly

def assemble(pack: dict, block: dict, inline_negative: bool = True) -> str:
    parts = [pack["style"].strip(), "", "SHOT:", block["action"].strip()]
    if block.get("sfx"):
        parts += ["", f"AUDIO: {block['sfx']} — sound design only, no music, no narration."]
    if block.get("loop"):
        parts += ["", "This clip must loop seamlessly: last frame matches first frame."]
    if inline_negative and pack["negative"]:
        parts += ["", f"AVOID: {pack['negative'].strip()}"]
    return "\n".join(parts)


def emit_blocks(pack: dict, blocks: list[dict], inline_negative: bool) -> list[dict]:
    meta = pack["meta"]
    out = []
    for b in blocks:
        out.append({
            **{k: b[k] for k in ("id", "t0", "t1", "priority", "mode", "video",
                                 "vo", "sfx", "loop", "refs", "action")},
            "prompt": assemble(pack, b, inline_negative=inline_negative),
            "negative": pack["negative"],
            "sheet": meta.get("sheet"),
            "sheet_ref": meta.get("sheet_ref"),
            "logo_ref": meta.get("logo_ref"),
            "model": meta.get("model"),
            "aspect": meta.get("aspect"),
            "duration": int(meta.get("duration", 5)),
            "pack": pack["path"],
        })
    return out


def filter_blocks(pack: dict, priority: str | None, block_ids: str | None,
                  mode: str | None) -> list[dict]:
    blocks = pack["blocks"]
    if block_ids:
        wanted = {x.strip() for x in block_ids.split(",")}
        blocks = [b for b in blocks if b["id"] in wanted]
        missing = wanted - {b["id"] for b in blocks}
        if missing:
            raise MotionBuilderError(f"blocks not in pack: {sorted(missing)}")
    if priority:
        prios = {p.strip().upper() for p in priority.split(",")}
        blocks = [b for b in blocks if b["priority"] in prios]
    if mode:
        blocks = [b for b in blocks if b["mode"] == mode or b["mode"].startswith(mode)]
    return blocks


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", required=True)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--assemble", metavar="BLOCK_ID")
    ap.add_argument("--emit", action="store_true", help="JSON blocks for mg_gen.py")
    ap.add_argument("--priority", help="filter: P1 or P1,P2")
    ap.add_argument("--blocks", help="filter: B001,B004")
    ap.add_argument("--mode", help="filter: t2v | ref2v | v2v")
    ap.add_argument("--inline-negative", action="store_true", default=True,
                    help="fold NEGATIVE into the prompt as AVOID: (default on — Omni has "
                         "no negative_prompt param; FAL callers can pass it separately)")
    ap.add_argument("--no-inline-negative", dest="inline_negative", action="store_false")
    args = ap.parse_args()

    pack = parse_pack(Path(args.pack).expanduser())

    if args.check:
        errors = check_pack(pack)
        if errors:
            for e in errors:
                print(f"error: {e}", file=sys.stderr)
            return 2
        print(f"OK — {len(pack['blocks'])} blocks, style lock "
              f"{len(pack['style'].split())} words, negative {len(pack['negative'].split())} words")
        return 0

    selected = filter_blocks(pack, args.priority, args.blocks, args.mode)

    if args.list:
        for b in selected:
            vid = f"  video={b['video']}" if b["video"] else ""
            print(f"{b['id']}  [{b['t0']:>7.1f}–{b['t1']:>7.1f}]  {b['priority']}  "
                  f"{b['mode']:<14}{vid}")
        print(f"-- {len(selected)} blocks", file=sys.stderr)
        return 0

    if args.stats:
        from collections import Counter
        by_p = Counter(b["priority"] for b in pack["blocks"])
        by_m = Counter(b["mode"] for b in pack["blocks"])
        model = pack["meta"].get("model", "gemini-omni-video")
        price = price_for(model) or 0.5
        total_secs = sum(b["t1"] - b["t0"] for b in pack["blocks"])
        print(f"blocks: {len(pack['blocks'])}   covers ≈ {total_secs / 60:.1f} min of timeline")
        print("priorities: " + ", ".join(f"{k}={v}" for k, v in sorted(by_p.items())))
        print("modes:      " + ", ".join(f"{k}={v}" for k, v in sorted(by_m.items())))
        for label, prio in (("P1 only", ("P1",)), ("P1+P2", ("P1", "P2")),
                            ("everything", ("P1", "P2", "P3"))):
            n = sum(1 for b in pack["blocks"] if b["priority"] in prio)
            print(f"est cost {label:<11} {n:>3} clips × ~${price:.2f} ≈ ${n * price:.2f}")
        print(f"(pricing is an estimate for `{model}` — override in config['pricing'])")
        return 0

    if args.assemble:
        matches = [b for b in pack["blocks"] if b["id"] == args.assemble]
        if not matches:
            raise MotionBuilderError(f"block {args.assemble} not found")
        print(assemble(pack, matches[0], inline_negative=args.inline_negative))
        return 0

    if args.emit:
        errors = check_pack(pack)
        if errors:
            for e in errors:
                print(f"error: {e}", file=sys.stderr)
            return 2
        print(json.dumps(emit_blocks(pack, selected, args.inline_negative), indent=2))
        return 0

    ap.error("pick one of --check / --list / --stats / --assemble / --emit")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MotionBuilderError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
