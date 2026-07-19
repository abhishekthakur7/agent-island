"""
Shared helpers for motion-builder scripts.

Motion-builder state lives OUTSIDE the skill directory (skill caches can be
read-only in Cowork). Resolution order for the state dir:
  1. $MOTION_BUILDER_HOME
  2. ~/.frmwrkd/motion-builder/

Provides:
  - state_dir() / config / INDEX paths
  - load_config() / save_config()
  - load_api_key()          — FAL_KEY / KIE_API_KEY from env or .env files
  - project helpers         — slug, list, scaffold, active
  - resolve_output_dir()    — <output_dir>/<YYYY-MM-DD>/<project>/<kind>/
  - upload_file()           — host a local file (Kie upload API or FAL storage)
  - write_render_sidecar()  — .md audit trail next to every artifact
  - append_index_render()   — INDEX.md recent-renders log
  - price_for()             — per-clip/per-image cost estimates (config-overridable)
"""

from __future__ import annotations

import json
import mimetypes
import os
import re
import secrets
import shutil
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent


class MotionBuilderError(RuntimeError):
    pass


# ---------------------------------------------------------------- state dir

def state_dir() -> Path:
    env = os.environ.get("MOTION_BUILDER_HOME")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".frmwrkd" / "motion-builder"


def config_path() -> Path:
    return state_dir() / "config.json"


def index_path() -> Path:
    return state_dir() / "INDEX.md"


def projects_dir() -> Path:
    return state_dir() / "projects"


PROJECT_KINDS = ("sheets", "packs", "transcripts")


# ------------------------------------------------------------------ config

def load_config() -> dict[str, Any]:
    p = config_path()
    if not p.exists():
        raise MotionBuilderError(
            f"No config at {p}. Run `python scripts/setup.py` first (see SKILL.md STEP 0)."
        )
    return json.loads(p.read_text())


def save_config(config: dict[str, Any]) -> None:
    config["modified"] = datetime.now(timezone.utc).isoformat()
    state_dir().mkdir(parents=True, exist_ok=True)
    config_path().write_text(json.dumps(config, indent=2))


# -------------------------------------------------------------------- keys

def _read_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def load_api_key(provider: str, config: dict[str, Any] | None = None) -> str:
    """Key lookup: process env → config'd key_path → ~/.frmwrkd/.env → <state>/.env"""
    if config is None:
        config = load_config()

    if provider == "fal":
        env_names = ("FAL_KEY", "FAL_API_KEY")
        key_path_field = "fal_key_path"
    elif provider == "kie":
        env_names = ("KIE_API_KEY",)
        key_path_field = "kie_key_path"
    else:
        raise MotionBuilderError(f"unknown provider: {provider}")

    for name in env_names:
        if os.environ.get(name):
            return os.environ[name]

    candidates: list[Path] = []
    cfg_path = (config.get("provider") or {}).get(key_path_field)
    if cfg_path:
        candidates.append(Path(cfg_path).expanduser())
    candidates.append(Path.home() / ".frmwrkd" / ".env")
    candidates.append(state_dir() / ".env")

    for path in candidates:
        env = _read_env_file(path)
        for name in env_names:
            if env.get(name):
                return env[name]

    raise MotionBuilderError(
        f"No {provider.upper()} API key found. Checked env ({', '.join(env_names)}) "
        f"and: {[str(p) for p in candidates]}. Run setup.py --reset to re-enter."
    )


# ---------------------------------------------------------------- projects

def slugify_project(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return s[:60] or "untitled"


def slugify(s: str) -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s.strip())
    return s[:60] or "untitled"


def get_active_project(config: dict[str, Any] | None = None) -> str | None:
    if config is None:
        try:
            config = load_config()
        except MotionBuilderError:
            return None
    return config.get("active_project") or None


def set_active_project(slug: str | None, config: dict[str, Any] | None = None) -> dict[str, Any]:
    if config is None:
        config = load_config()
    if slug is not None:
        slug = slugify_project(slug)
        if not (projects_dir() / slug).exists():
            raise MotionBuilderError(
                f"project '{slug}' not found under {projects_dir()}. "
                f"Create it: `python scripts/setup.py --new-project <name>`."
            )
    config["active_project"] = slug
    save_config(config)
    return config


def list_projects() -> list[str]:
    d = projects_dir()
    if not d.exists():
        return []
    return sorted(p.name for p in d.iterdir() if p.is_dir() and not p.name.startswith("."))


def ensure_project_scaffold(slug: str) -> Path:
    slug = slugify_project(slug)
    root = projects_dir() / slug
    for kind in PROJECT_KINDS:
        (root / kind).mkdir(parents=True, exist_ok=True)
    return root


# ------------------------------------------------------------- output dirs

def resolve_output_dir(kind: str, config: dict[str, Any] | None = None,
                       project: str | None = None) -> Path:
    """<output_dir>/<YYYY-MM-DD>/<project|_unsorted>/<kind>/  (kind: clips|sheets|prompts|segments)"""
    if config is None:
        config = load_config()
    project_slug = slugify_project(project) if project else get_active_project(config) or "_unsorted"
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    out = Path(config["paths"]["output_dir"]).expanduser() / date / project_slug / kind
    out.mkdir(parents=True, exist_ok=True)
    return out


def unique_path(directory: Path, base: str, ext: str) -> Path:
    n = 1
    while True:
        p = directory / f"{base}_{n:03d}.{ext.lstrip('.')}"
        if not p.exists():
            return p
        n += 1


def download_to_local(url: str, target: Path) -> Path:
    target.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url) as response, target.open("wb") as f:  # noqa: S310
        shutil.copyfileobj(response, f)
    return target


# ------------------------------------------------------------------ upload

def upload_file(local_path: Path, provider_hint: str, config: dict[str, Any]) -> str:
    """
    Host a local file so Kie/FAL model APIs can fetch it by URL.
      provider_hint "kie" → Kie upload API (tempfile, ~24-72h retention — fine, we
                            generate immediately after upload)
      provider_hint "fal" → FAL storage CDN
    Falls back to the other provider's storage if the hinted key is missing.
    """
    local_path = local_path.expanduser()
    if not local_path.exists():
        raise MotionBuilderError(f"file not found: {local_path}")

    order = ["kie", "fal"] if provider_hint == "kie" else ["fal", "kie"]
    last_err: Exception | None = None
    for prov in order:
        try:
            key = load_api_key(prov, config)
        except MotionBuilderError as e:
            last_err = e
            continue
        try:
            if prov == "kie":
                return _upload_kie(local_path, key)
            return _upload_fal(local_path, key)
        except Exception as e:  # surface after trying fallback
            last_err = e
    raise MotionBuilderError(f"upload failed on all providers: {last_err}")


def _multipart(fields: dict[str, str], file_field: str, local_path: Path) -> tuple[bytes, str]:
    mime, _ = mimetypes.guess_type(local_path.name)
    mime = mime or "application/octet-stream"
    boundary = f"----motionbuilder{secrets.token_hex(8)}"
    parts: list[bytes] = []
    for k, v in fields.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(
        f'Content-Disposition: form-data; name="{file_field}"; filename="{local_path.name}"\r\n'.encode()
    )
    parts.append(f"Content-Type: {mime}\r\n\r\n".encode())
    parts.append(local_path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), boundary


def _upload_kie(local_path: Path, api_key: str) -> str:
    """POST https://kieai.redpandaai.co/api/file-stream-upload → data.downloadUrl"""
    body, boundary = _multipart({"uploadPath": "motion-builder"}, "file", local_path)
    req = urllib.request.Request(
        "https://kieai.redpandaai.co/api/file-stream-upload",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:  # noqa: S310
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise MotionBuilderError(f"Kie upload → HTTP {e.code}: {e.read().decode(errors='replace')}") from e
    url = (data.get("data") or {}).get("downloadUrl") or (data.get("data") or {}).get("fileUrl")
    if not url:
        raise MotionBuilderError(f"Kie upload returned no URL: {data}")
    return url


def _upload_fal(local_path: Path, api_key: str) -> str:
    """POST https://fal.run/storage/upload → url"""
    body, boundary = _multipart({}, "file", local_path)
    req = urllib.request.Request(
        "https://fal.run/storage/upload",
        data=body,
        headers={
            "Authorization": f"Key {api_key}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:  # noqa: S310
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise MotionBuilderError(f"FAL upload → HTTP {e.code}: {e.read().decode(errors='replace')}") from e
    if "url" not in data:
        raise MotionBuilderError(f"FAL upload returned no URL: {data}")
    return data["url"]


# -------------------------------------------------------------------- cost

# Estimates only — real prices drift. Override any entry via config["pricing"].
DEFAULT_PRICING: dict[str, float] = {
    # per video clip (≈5s)
    "gemini-omni-video": 0.50,
    "kling-2.6": 0.55,
    "veo-3.1": 1.50,
    "fal-ai/veo-3": 1.50,
    "fal-ai/kling-video/v2.1/master": 0.55,
    # per image
    "nano-banana-pro": 0.05,
    "nano-banana-2": 0.06,
    "flux-2": 0.06,
    "fal-ai/flux-pro/v1.1-ultra": 0.05,
}

GATE_THRESHOLDS = {"clip": 1.00, "batch": 2.00}


def price_for(model: str, config: dict[str, Any] | None = None) -> float | None:
    table = dict(DEFAULT_PRICING)
    if config:
        table.update(config.get("pricing") or {})
    return table.get(model)


def session_log_path() -> Path:
    return state_dir() / "session_costs.jsonl"


def log_session_cost(entry: dict[str, Any]) -> None:
    p = session_log_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    entry = {"ts": datetime.now(timezone.utc).isoformat(), **entry}
    with p.open("a") as f:
        f.write(json.dumps(entry) + "\n")


# ---------------------------------------------------------------- sidecars

def write_render_sidecar(
    artifact_path: Path,
    *,
    provider: str,
    model: str,
    render_type: str,
    project: str | None,
    prompt: str,
    cost_usd: float | None,
    block_id: str | None = None,
    sheet: str | None = None,
    settings: dict[str, Any] | None = None,
    extra: dict[str, Any] | None = None,
) -> Path:
    """Write <artifact>.md next to every render — prompt, cost, sheet, settings. The audit trail."""
    sidecar = artifact_path.with_suffix(artifact_path.suffix + ".md")
    now_iso = datetime.now(timezone.utc).isoformat()
    settings = settings or {}
    extra = extra or {}

    fm = [
        "---",
        f"created: {now_iso}",
        "type: render",
        f"artifact: {artifact_path.name}",
        f"provider: {provider}",
        f"model: {model}",
        f"render_type: {render_type}",
        f"project: {project or '_unsorted'}",
    ]
    if block_id:
        fm.append(f"block: {block_id}")
    if sheet:
        fm.append(f"sheet: {sheet}")
    if cost_usd is not None:
        fm.append(f"cost_usd: {cost_usd:.4f}")
    for k, v in extra.items():
        if v in (None, "", [], {}):
            continue
        fm.append(f"{k}: {v if isinstance(v, str) else json.dumps(v)}")
    fm.append(f"tags: [render, {render_type}, motion-builder]")
    fm.append("---")

    cost_line = f"${cost_usd:.4f} — {provider} {model}" if cost_usd is not None else f"{provider} {model}"
    body = [
        "",
        f"# {artifact_path.stem}",
        "",
        f"**Path:** `{artifact_path}`",
        f"**Cost:** {cost_line}",
    ]
    if block_id:
        body.append(f"**Block:** `{block_id}`")
    if sheet:
        body.append(f"**Sheet:** `{sheet}`")
    body.extend(["", "## Prompt", "", "```", prompt.strip(), "```"])
    if settings:
        body.extend(["", "## Settings", ""])
        for k, v in settings.items():
            if v in (None, ""):
                continue
            body.append(f"- **{k}:** `{v}`")
    body.extend(["", "## Regenerate", "",
                 "Re-run the block through mg_gen.py, or paste the prompt above anywhere.", ""])

    sidecar.write_text("\n".join(fm) + "\n" + "\n".join(body))
    return sidecar


# ------------------------------------------------------------------- INDEX

def append_index_render(row: dict[str, Any]) -> None:
    p = index_path()
    if not p.exists():
        return
    text = p.read_text()
    header = "## Recent renders"
    table_header = (
        "| Date | Provider | Model | Project | Block | Type | Cost | Path |\n"
        "|---|---|---|---|---|---|---|---|"
    )
    new_row = (
        f"| {row['date']} | {row['provider']} | {row['model']} | {row.get('project', '—')} | "
        f"{row.get('block', '—')} | {row['format']} | {row.get('cost', '—')} | `{row['path']}` |"
    )
    if header not in text:
        return
    start = text.index(header)
    end = text.find("\n## ", start + len(header))
    if end == -1:
        end = len(text)
    block = text[start:end]
    if "*No renders yet.*" in block:
        new_text = text.replace(block, f"{header}\n\n{table_header}\n{new_row}\n")
    else:
        lines = block.splitlines()
        last = max((i for i, ln in enumerate(lines) if ln.startswith("|")), default=None)
        if last is None:
            return
        lines.insert(last + 1, new_row)
        new_text = text.replace(block, "\n".join(lines) + "\n")
    p.write_text(new_text)


def touch_index_modified() -> None:
    p = index_path()
    if not p.exists():
        return
    text = p.read_text()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    p.write_text(re.sub(r"\*\*Last updated:\*\* .+", f"**Last updated:** {now}", text))


# --------------------------------------------------------------- timestamps

def parse_ts(ts: str) -> float:
    """'m:ss', 'mm:ss', 'h:mm:ss', or float seconds → seconds."""
    ts = ts.strip()
    if re.fullmatch(r"\d+(\.\d+)?", ts):
        return float(ts)
    parts = [float(x) for x in ts.split(":")]
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    if len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    raise MotionBuilderError(f"bad timestamp: {ts}")


def fmt_ts(seconds: float) -> str:
    seconds = max(0.0, seconds)
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = seconds % 60
    if h:
        return f"{h}:{m:02d}:{s:04.1f}" if s % 1 else f"{h}:{m:02d}:{int(s):02d}"
    return f"{m:02d}:{s:04.1f}" if s % 1 else f"{m:02d}:{int(s):02d}"
