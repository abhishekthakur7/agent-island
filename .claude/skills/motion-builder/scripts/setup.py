#!/usr/bin/env python3
"""
Motion Builder — setup gate + project management.

State lives at ~/.frmwrkd/motion-builder/ (or $MOTION_BUILDER_HOME), NOT inside
the skill directory — skill caches can be read-only (Cowork).

Two ways to run:

  Interactive (terminal with a TTY):
      python setup.py

  Non-interactive (agent-driven — Cowork/Claude Code pass answers as flags):
      python setup.py --provider ask --output-dir "~/Generated/motion-builder" \
          --video-model gemini-omni-video --image-model nano-banana-pro \
          --aspect 16:9 --duration 5

  Keys (optional here — usually already in ~/.frmwrkd/.env, shared with shot-builder):
      python setup.py --set-key kie <KEY>       # writes to ~/.frmwrkd/.env, chmod 600

  Projects:
      python setup.py --new-project "Build a Tool Part 2" [--switch]
      python setup.py --set-project build-a-tool-part-2
      python setup.py --list-projects
      python setup.py --current

  Inspect / reset:
      python setup.py --check
      python setup.py --reset [flags...]
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (  # noqa: E402
    MotionBuilderError,
    config_path,
    ensure_project_scaffold,
    get_active_project,
    index_path,
    list_projects,
    load_config,
    save_config,
    set_active_project,
    slugify_project,
    state_dir,
)

DEFAULT_ENV = Path.home() / ".frmwrkd" / ".env"

DEFAULTS = {
    "provider": "ask",            # kie | fal | ask | prompt_only
    "video_model": "gemini-omni-video",
    "image_model": "nano-banana-pro",
    "aspect": "16:9",
    "duration": 5,
    "resolution": "1080p",
    "audio": "sfx_no_music",      # sound design yes, music no, narration no
    "beat_length": 5.0,           # transcript segmentation target (s)
}


def has_tty() -> bool:
    return sys.stdin.isatty()


def prompt(question: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default else ""
    answer = input(f"{question}{suffix}: ").strip()
    return answer or (default or "")


def write_env_key(env_path: Path, key_name: str, key_value: str) -> None:
    env_path.parent.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    if env_path.exists():
        lines = [ln for ln in env_path.read_text().splitlines()
                 if not ln.startswith(f"{key_name}=")]
    lines.append(f"{key_name}={key_value}")
    env_path.write_text("\n".join(lines) + "\n")
    env_path.chmod(0o600)


def seed_index(config: dict[str, Any]) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    d = config["defaults"]
    content = f"""# Motion Builder — Hot Cache (INDEX.md)

<!--
LOCKED TEMPLATE — DO NOT EDIT BY HAND.
Auto-managed by setup.py / mg_gen.py / transcript.py.
Routing lives in SKILL.md, never here.
Sections: Setup, Active project, Projects, Sheets, Packs, Recent renders, Notes.
-->

> Hot cache for the motion-builder skill. Sections labeled `[auto]` are updated
> by scripts; `[manual]` is for the user. Agents edit neither by hand.

**Last updated:** {now}

---

## Setup `[auto]`

| Setting | Value |
|---|---|
| Provider | `{config['provider']['primary']}` (ask = choose per batch) |
| Video model | `{d['video_model']}` |
| Image model (sheets) | `{d['image_model']}` |
| Aspect / duration | `{d['aspect']}` / `{d['duration']}s` |
| Audio default | `{d['audio']}` (sound design only — no music, no narration) |
| Output dir | `{config['paths']['output_dir']}` |
| State dir | `{state_dir()}` |

## Active project `[auto]`

`{config.get('active_project') or '—'}`

## Projects `[auto]`

*None yet.*

## Sheets `[auto]`

*No motion sheets locked yet.*

## Packs `[auto]`

*No prompt packs yet.*

## Recent renders `[auto]`

*No renders yet.*

## Active gotchas / notes `[manual]`

*(user notes here)*
"""
    index_path().write_text(content)


def refresh_index_lists() -> None:
    """Rewrite the Projects/Sheets/Packs sections from what's on disk."""
    p = index_path()
    if not p.exists():
        return
    text = p.read_text()
    projects = list_projects()

    def section(text: str, header: str, body: str) -> str:
        import re
        pattern = rf"(## {re.escape(header)} `\[auto\]`\n\n)(.*?)(?=\n## )"
        return re.sub(pattern, rf"\g<1>{body}\n", text, flags=re.DOTALL)

    proj_body = "\n".join(f"- `{s}`" for s in projects) if projects else "*None yet.*"
    sheets: list[str] = []
    packs: list[str] = []
    from _common import projects_dir
    for slug in projects:
        for f in sorted((projects_dir() / slug / "sheets").glob("*.md")):
            sheets.append(f"- `<{f.stem}>` — {slug}")
        for f in sorted((projects_dir() / slug / "packs").glob("*.md")):
            packs.append(f"- `{f.name}` — {slug}")
    text = section(text, "Projects", proj_body)
    text = section(text, "Sheets", "\n".join(sheets) if sheets else "*No motion sheets locked yet.*")
    text = section(text, "Packs", "\n".join(packs) if packs else "*No prompt packs yet.*")
    p.write_text(text)


def build_config(args: argparse.Namespace, existing: dict[str, Any] | None) -> dict[str, Any]:
    base = existing or {
        "version": "1.0",
        "created": datetime.now(timezone.utc).isoformat(),
        "provider": {"primary": DEFAULTS["provider"], "fallback": None,
                     "fal_key_path": str(DEFAULT_ENV), "kie_key_path": str(DEFAULT_ENV)},
        "defaults": dict(DEFAULTS),
        "paths": {"output_dir": "", "state_dir": str(state_dir())},
        "pricing": {},
        "active_project": None,
    }
    d = base["defaults"]
    if args.provider:
        base["provider"]["primary"] = args.provider
    if args.output_dir:
        base["paths"]["output_dir"] = args.output_dir
    if args.video_model:
        d["video_model"] = args.video_model
    if args.image_model:
        d["image_model"] = args.image_model
    if args.aspect:
        d["aspect"] = args.aspect
    if args.duration:
        d["duration"] = args.duration
    if args.resolution:
        d["resolution"] = args.resolution
    if args.beat_length:
        d["beat_length"] = args.beat_length
    return base


def interactive_fill(config: dict[str, Any]) -> None:
    print("\n— Motion Builder setup —")
    config["provider"]["primary"] = prompt(
        "Provider (kie / fal / ask / prompt_only)", config["provider"]["primary"])
    config["paths"]["output_dir"] = prompt(
        "Output directory for renders", config["paths"]["output_dir"] or
        str(Path.home() / "Movies" / "motion-builder"))
    d = config["defaults"]
    d["video_model"] = prompt("Default video model", d["video_model"])
    d["image_model"] = prompt("Default image model (sheet renders)", d["image_model"])
    d["aspect"] = prompt("Default aspect", d["aspect"])
    d["duration"] = int(prompt("Default clip duration (s)", str(d["duration"])))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="print config and exit")
    ap.add_argument("--reset", action="store_true", help="rebuild config from flags/defaults")
    ap.add_argument("--provider", choices=["kie", "fal", "ask", "prompt_only"])
    ap.add_argument("--output-dir")
    ap.add_argument("--video-model")
    ap.add_argument("--image-model")
    ap.add_argument("--aspect")
    ap.add_argument("--duration", type=int)
    ap.add_argument("--resolution")
    ap.add_argument("--beat-length", type=float)
    ap.add_argument("--set-key", nargs=2, metavar=("PROVIDER", "KEY"),
                    help="write FAL_KEY / KIE_API_KEY to ~/.frmwrkd/.env (chmod 600)")
    ap.add_argument("--new-project", metavar="NAME")
    ap.add_argument("--switch", action="store_true", help="with --new-project: set active")
    ap.add_argument("--set-project", metavar="SLUG")
    ap.add_argument("--clear-project", action="store_true")
    ap.add_argument("--list-projects", action="store_true")
    ap.add_argument("--current", action="store_true")
    args = ap.parse_args()

    # --- key management (works before config exists)
    if args.set_key:
        provider, key = args.set_key
        name = {"fal": "FAL_KEY", "kie": "KIE_API_KEY"}.get(provider)
        if not name:
            raise MotionBuilderError("--set-key provider must be fal or kie")
        write_env_key(DEFAULT_ENV, name, key)
        print(f"wrote {name} to {DEFAULT_ENV}")
        return 0

    exists = config_path().exists()

    # --- project subcommands (require config)
    if args.list_projects:
        for s in list_projects():
            print(s)
        return 0
    if args.current:
        print(get_active_project() or "")
        return 0
    if args.new_project:
        config = load_config()
        slug = slugify_project(args.new_project)
        ensure_project_scaffold(slug)
        if args.switch:
            set_active_project(slug, config)
        refresh_index_lists()
        print(slug)
        return 0
    if args.set_project:
        set_active_project(args.set_project)
        print(args.set_project)
        return 0
    if args.clear_project:
        set_active_project(None)
        print("cleared")
        return 0

    # --- check
    if args.check:
        if not exists:
            print("NO CONFIG — run setup (see SKILL.md STEP 0)")
            return 1
        print(json.dumps(load_config(), indent=2))
        return 0

    # --- setup / reset
    if exists and not args.reset:
        print(f"config already exists at {config_path()} — use --check or --reset")
        return 0

    existing = load_config() if exists else None
    config = build_config(args, existing if args.reset else None)

    if not config["paths"]["output_dir"]:
        if has_tty():
            interactive_fill(config)
        else:
            print(
                "MISSING REQUIRED VALUES (non-interactive run).\n"
                "Ask the user, then re-run with flags, e.g.:\n"
                '  python setup.py --provider ask --output-dir "<dir>" '
                "--video-model gemini-omni-video --image-model nano-banana-pro "
                "--aspect 16:9 --duration 5\n"
                "Required: --output-dir. Everything else has defaults.",
                file=sys.stderr,
            )
            return 1

    save_config(config)
    seed_index(config)
    print(f"config: {config_path()}")
    print(f"index:  {index_path()}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MotionBuilderError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
