#!/usr/bin/env python3
"""
Motion Builder — real-logo fetcher.

Motion graphics constantly reference real products (Slack, Notion, OpenAI…).
Asking a video model to DRAW a logo from memory produces near-logos and
gibberish marks. The fix: fetch the real mark as a file, attach it as a
reference image, and let the prompt say "use the attached logo exactly, flat,
unmodified". This script pulls official marks from public logo endpoints —
no API keys needed.

Sources (auto mode tries in this order):
  clearbit      https://logo.clearbit.com/<domain>          color PNG, by domain
  simpleicons   https://cdn.simpleicons.org/<slug>[/<hex>]  brand-mark SVG, 3000+ brands
  favicon       https://www.google.com/s2/favicons?...      last-resort small PNG

Usage:
    python logos.py --brand slack --brand notion --brand openai
    python logos.py --brand "trigger.dev" --domain trigger.dev
    python logos.py --brand x --source simpleicons --color white
    python logos.py --url https://example.com/press/logo.png --brand example

Output: <out-dir>/<brand>.<png|svg> + a LOGOS.md manifest row per file.
Default out-dir: ~/.frmwrkd/motion-builder/projects/<active>/assets/logos/
(SVGs are converted to PNG when cairosvg is installed — video APIs want raster.)

Trademarks belong to their owners; clearing usage is the user's responsibility.
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (  # noqa: E402
    MotionBuilderError,
    get_active_project,
    load_config,
    projects_dir,
)

UA = {"User-Agent": "motion-builder/1.0 (+local asset fetch)"}


def fetch(url: str, timeout: int = 30) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:  # noqa: S310
        return r.read()


def slugify_brand(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def guess_domain(brand: str) -> str:
    b = brand.lower().strip()
    return b if "." in b else f"{re.sub(r'[^a-z0-9-]', '', b)}.com"


def try_clearbit(brand: str, domain: str | None, size: int) -> tuple[bytes, str] | None:
    url = f"https://logo.clearbit.com/{domain or guess_domain(brand)}?size={size}"
    try:
        data = fetch(url)
        if data[:8].startswith(b"\x89PNG") or data[:3] == b"\xff\xd8\xff":
            return data, "png"
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return None


def try_simpleicons(brand: str, color: str | None) -> tuple[bytes, str] | None:
    slug = slugify_brand(brand)
    url = f"https://cdn.simpleicons.org/{slug}"
    if color:
        url += f"/{color.lstrip('#')}"
    try:
        data = fetch(url)
        if b"<svg" in data[:200]:
            return data, "svg"
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return None


def try_favicon(brand: str, domain: str | None, size: int) -> tuple[bytes, str] | None:
    url = (f"https://www.google.com/s2/favicons?domain={domain or guess_domain(brand)}"
           f"&sz={min(size, 256)}")
    try:
        data = fetch(url)
        if len(data) > 200:  # tiny generic globe = miss
            return data, "png"
    except (urllib.error.HTTPError, urllib.error.URLError):
        pass
    return None


def svg_to_png(svg_bytes: bytes, size: int) -> bytes | None:
    try:
        import cairosvg  # type: ignore
    except ImportError:
        return None
    return cairosvg.svg2png(bytestring=svg_bytes, output_width=size, output_height=size)


def default_out_dir() -> Path:
    try:
        config = load_config()
        project = get_active_project(config)
    except MotionBuilderError:
        project = None
    if project:
        d = projects_dir() / project / "assets" / "logos"
    else:
        d = Path.cwd() / "logos"
    d.mkdir(parents=True, exist_ok=True)
    return d


def append_manifest(out_dir: Path, brand: str, path: Path, source: str) -> None:
    manifest = out_dir / "LOGOS.md"
    if not manifest.exists():
        manifest.write_text(
            "# Logo assets\n\nFetched by logos.py. Attach as reference images; prompt "
            "with: `use the attached <brand> logo exactly — flat, unmodified, correct "
            "proportions`. Trademark clearance is on you.\n\n"
            "| Brand | File | Source | Fetched |\n|---|---|---|---|\n")
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with manifest.open("a") as f:
        f.write(f"| {brand} | `{path.name}` | {source} | {ts} |\n")


def get_logo(brand: str, *, domain: str | None, source: str, color: str | None,
             size: int, url: str | None, out_dir: Path) -> Path:
    result: tuple[bytes, str] | None = None
    used = source
    if url:
        data = fetch(url)
        ext = "svg" if b"<svg" in data[:200] else "png"
        result, used = (data, ext), "direct-url"
    elif source == "clearbit":
        result = try_clearbit(brand, domain, size)
    elif source == "simpleicons":
        result = try_simpleicons(brand, color)
    elif source == "favicon":
        result = try_favicon(brand, domain, size)
    else:  # auto
        for name, fn in (("clearbit", lambda: try_clearbit(brand, domain, size)),
                         ("simpleicons", lambda: try_simpleicons(brand, color)),
                         ("favicon", lambda: try_favicon(brand, domain, size))):
            result = fn()
            if result:
                used = name
                break

    if not result:
        raise MotionBuilderError(
            f"no logo found for '{brand}' (tried {source}). Options: pass --domain, "
            f"try --source simpleicons, or give a --url to the official press asset.")

    data, ext = result
    if ext == "svg":
        png = svg_to_png(data, size)
        if png:
            data, ext = png, "png"
        else:
            print(f"  note: {brand} is SVG — `pip install cairosvg --break-system-packages` "
                  f"to auto-convert (video APIs want PNG)", file=sys.stderr)

    path = out_dir / f"{slugify_brand(brand)}.{ext}"
    path.write_bytes(data)
    append_manifest(out_dir, brand, path, used)
    print(f"  {brand}: {path}  ({used}, {len(data) // 1024}KB)", file=sys.stderr)
    return path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--brand", action="append", required=True,
                    help="brand name (repeatable)")
    ap.add_argument("--domain", help="override domain for clearbit/favicon (single-brand runs)")
    ap.add_argument("--url", help="direct URL to an official asset (single-brand runs)")
    ap.add_argument("--source", choices=["auto", "clearbit", "simpleicons", "favicon"],
                    default="auto")
    ap.add_argument("--color", help="simpleicons tint, e.g. white or FFFFFF")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--out-dir")
    args = ap.parse_args()

    if (args.domain or args.url) and len(args.brand) > 1:
        raise MotionBuilderError("--domain/--url work with a single --brand")

    out_dir = Path(args.out_dir).expanduser() if args.out_dir else default_out_dir()
    out_dir.mkdir(parents=True, exist_ok=True)

    failures = []
    for brand in args.brand:
        try:
            print(str(get_logo(brand, domain=args.domain, source=args.source,
                               color=args.color, size=args.size, url=args.url,
                               out_dir=out_dir)))
        except (MotionBuilderError, urllib.error.URLError) as e:
            failures.append(f"{brand}: {e}")
            print(f"  FAILED {brand}: {e}", file=sys.stderr)
    if failures:
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MotionBuilderError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
