#!/usr/bin/env python3
"""
Motion Builder — transcript extractor / segmenter / cutter.

Turns a film segment (or an existing transcript) into timestamped BEATS the
prompt pack maps onto, finds the PAUSES, and can CUT the source video into
pause-free segments ready for video-to-video generation.

Input auto-detect:
  media file (.mp4 .mov .mkv .webm .wav .mp3 .m4a) → transcribe locally
      (faster-whisper preferred, openai-whisper fallback) with word timestamps
  transcript file (.srt .vtt .json)                → parse timestamps directly
      (.json accepts whisper-style {"segments":[{start,end,text,words?}]})
  --transcript <file> alongside media               → skip transcription, keep
      the media available for --cut

Usage:
    python transcript.py --input talk.mp4 [--project <slug>]
    python transcript.py --input talk.srt
    python transcript.py --input talk.mp4 --transcript talk.vtt --cut
    python transcript.py --input talk.mp4 --cut --cut-beats

Key flags:
    --beat-length 5.0     target beat duration (s); beats break at sentence ends
    --soft-pause 0.6      gap flagged as a pause (s)
    --hard-pause 1.2      gap that forces a beat break + cut candidate (s)
    --cut                 export pause-free KEEP segments via ffmpeg
    --cut-beats           export one clip per beat (for v2v blocks)
    --whisper-model small faster-whisper / whisper model size

Outputs (next to the input, and listed on stdout):
    <base>.segments.json  machine-readable beats + pauses + keep ranges
    <base>.segments.md    human-readable beat table + cutlist
    segments/<base>_keep_NN.mp4      (--cut)
    segments/<base>_beat_S001.mp4    (--cut-beats)
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import MotionBuilderError, fmt_ts  # noqa: E402

MEDIA_EXT = {".mp4", ".mov", ".mkv", ".webm", ".wav", ".mp3", ".m4a", ".aac", ".flac"}
SENT_END = re.compile(r"[.!?…]['\")\]]*$")


# ------------------------------------------------------------ transcription

def transcribe(media: Path, model_size: str) -> list[dict]:
    """Return whisper-style segments with word timestamps. Tries faster-whisper, then whisper."""
    try:
        from faster_whisper import WhisperModel  # type: ignore
    except ImportError:
        return _transcribe_openai_whisper(media, model_size)

    print(f"→ faster-whisper ({model_size}) on {media.name}", file=sys.stderr)
    model = WhisperModel(model_size, device="auto", compute_type="auto")
    segments, _info = model.transcribe(str(media), word_timestamps=True, vad_filter=True)
    out = []
    for seg in segments:
        words = [{"w": w.word, "t0": w.start, "t1": w.end} for w in (seg.words or [])]
        out.append({"start": seg.start, "end": seg.end, "text": seg.text.strip(), "words": words})
    return out


def _transcribe_openai_whisper(media: Path, model_size: str) -> list[dict]:
    if shutil.which("whisper") is None:
        raise MotionBuilderError(
            "No transcription backend. Install one:\n"
            "  pip install faster-whisper --break-system-packages   (recommended)\n"
            "  pip install openai-whisper --break-system-packages\n"
            "…or pass an existing transcript via --transcript file.srt"
        )
    print(f"→ openai-whisper ({model_size}) on {media.name}", file=sys.stderr)
    outdir = media.parent / ".whisper_tmp"
    outdir.mkdir(exist_ok=True)
    subprocess.run(
        ["whisper", str(media), "--model", model_size, "--word_timestamps", "True",
         "--output_format", "json", "--output_dir", str(outdir)],
        check=True,
    )
    data = json.loads((outdir / f"{media.stem}.json").read_text())
    out = []
    for seg in data.get("segments", []):
        words = [{"w": w.get("word", ""), "t0": w.get("start"), "t1": w.get("end")}
                 for w in seg.get("words", [])]
        out.append({"start": seg["start"], "end": seg["end"],
                    "text": seg["text"].strip(), "words": words})
    return out


# ----------------------------------------------------------------- parsers

_TS = r"(\d{1,2}):(\d{2}):(\d{2})[.,](\d{3})"


def _ts_to_s(h: str, m: str, s: str, ms: str) -> float:
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def parse_srt_vtt(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8", errors="replace")
    out = []
    for m in re.finditer(rf"{_TS}\s*-->\s*{_TS}\s*\n(.*?)(?=\n\s*\n|\Z)", text, re.DOTALL):
        g = m.groups()
        seg_text = re.sub(r"<[^>]+>", "", g[8]).replace("\n", " ").strip()
        if not seg_text:
            continue
        out.append({"start": _ts_to_s(*g[0:4]), "end": _ts_to_s(*g[4:8]),
                    "text": seg_text, "words": []})
    if not out:
        raise MotionBuilderError(f"no cues parsed from {path}")
    return out


def parse_json_transcript(path: Path) -> list[dict]:
    data = json.loads(path.read_text())
    segs = data.get("segments") if isinstance(data, dict) else data
    if not isinstance(segs, list) or not segs:
        raise MotionBuilderError(f"{path}: expected whisper-style {{'segments': [...]}}")
    out = []
    for seg in segs:
        words = [{"w": w.get("word", w.get("w", "")), "t0": w.get("start", w.get("t0")),
                  "t1": w.get("end", w.get("t1"))} for w in seg.get("words", [])]
        out.append({"start": float(seg["start"]), "end": float(seg["end"]),
                    "text": str(seg["text"]).strip(), "words": words})
    return out


# -------------------------------------------------------------- word stream

def to_word_stream(segments: list[dict]) -> list[dict]:
    """Flatten to words. If a segment has no word timing, synthesize evenly spaced words."""
    words: list[dict] = []
    for seg in segments:
        if seg.get("words"):
            words.extend(w for w in seg["words"] if w.get("t0") is not None)
        else:
            toks = seg["text"].split()
            if not toks:
                continue
            span = (seg["end"] - seg["start"]) / len(toks)
            for i, tok in enumerate(toks):
                words.append({"w": " " + tok,
                              "t0": seg["start"] + i * span,
                              "t1": seg["start"] + (i + 1) * span})
    return words


# ------------------------------------------------------------- segmentation

def find_pauses(words: list[dict], soft: float, hard: float) -> list[dict]:
    pauses = []
    for a, b in zip(words, words[1:]):
        gap = b["t0"] - a["t1"]
        if gap >= soft:
            pauses.append({"t0": round(a["t1"], 2), "t1": round(b["t0"], 2),
                           "dur": round(gap, 2), "hard": gap >= hard})
    return pauses


def build_beats(words: list[dict], pauses: list[dict], target: float) -> list[dict]:
    """
    Group words into beats near `target` seconds. A beat closes when:
      - a hard pause follows the current word, or
      - we're past ~80% of target AND the word ends a sentence, or
      - we hit 1.35 × target (hard ceiling — break at next soft pause or word).
    """
    hard_starts = {p["t0"] for p in pauses if p["hard"]}
    soft_starts = {p["t0"] for p in pauses}
    beats: list[dict] = []
    cur: list[dict] = []

    def close(pause_after: float = 0.0) -> None:
        if not cur:
            return
        text = "".join(w["w"] for w in cur).strip()
        beats.append({
            "id": f"S{len(beats) + 1:03d}",
            "t0": round(cur[0]["t0"], 2),
            "t1": round(cur[-1]["t1"], 2),
            "text": re.sub(r"\s+", " ", text),
            "pause_after": round(pause_after, 2),
            "sentence_end": bool(SENT_END.search(text)),
        })
        cur.clear()

    for i, w in enumerate(words):
        cur.append(w)
        dur = cur[-1]["t1"] - cur[0]["t0"]
        nxt_gap = (words[i + 1]["t0"] - w["t1"]) if i + 1 < len(words) else 99.0
        at_hard = round(w["t1"], 2) in hard_starts or nxt_gap >= 99.0
        at_soft = round(w["t1"], 2) in soft_starts
        sent = bool(SENT_END.search(w["w"].strip()))
        if at_hard:
            close(pause_after=nxt_gap if nxt_gap < 99 else 0.0)
        elif dur >= target * 0.8 and sent:
            close(pause_after=nxt_gap if nxt_gap < 99 else 0.0)
        elif dur >= target * 1.35 and (at_soft or sent or dur >= target * 1.7):
            close(pause_after=nxt_gap if nxt_gap < 99 else 0.0)
    close()
    return beats


def keep_ranges(duration: float, pauses: list[dict], cut_threshold: float,
                pad: float = 0.15) -> list[list[float]]:
    """Ranges to KEEP when removing pauses ≥ cut_threshold. Keeps `pad` s of breath each side."""
    cuts = [p for p in pauses if p["dur"] >= cut_threshold]
    ranges: list[list[float]] = []
    cursor = 0.0
    for c in cuts:
        k0, k1 = cursor, c["t0"] + pad
        if k1 - k0 > 0.2:
            ranges.append([round(k0, 2), round(k1, 2)])
        cursor = max(cursor, c["t1"] - pad)
    if duration - cursor > 0.2:
        ranges.append([round(cursor, 2), round(duration, 2)])
    return ranges


# ------------------------------------------------------------------ ffmpeg

def ffmpeg_cut(media: Path, t0: float, t1: float, out: Path) -> None:
    if shutil.which("ffmpeg") is None:
        raise MotionBuilderError("ffmpeg not found on PATH — required for --cut")
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t0:.2f}", "-i", str(media),
         "-t", f"{t1 - t0:.2f}", "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
         "-c:a", "aac", "-movflags", "+faststart", str(out)],
        check=True,
    )


def media_duration(media: Path) -> float:
    if shutil.which("ffprobe") is None:
        return 0.0
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(media)],
        capture_output=True, text=True,
    )
    try:
        return float(r.stdout.strip())
    except ValueError:
        return 0.0


# ----------------------------------------------------------------- outputs

def write_outputs(base: Path, media: Path | None, beats: list[dict], pauses: list[dict],
                  keeps: list[list[float]], duration: float) -> tuple[Path, Path]:
    jpath = base.with_suffix(".segments.json")
    jpath.write_text(json.dumps({
        "source_media": str(media) if media else None,
        "duration": round(duration, 2),
        "beat_count": len(beats),
        "beats": beats,
        "pauses": pauses,
        "keep_ranges": keeps,
    }, indent=2))

    lines = [f"# Segments — {base.name}", "",
             f"**Duration:** {fmt_ts(duration)} · **Beats:** {len(beats)} · "
             f"**Pauses ≥ soft:** {len(pauses)} · **Hard pauses:** {sum(1 for p in pauses if p['hard'])}",
             "", "## Beats", "",
             "| ID | Time | Dur | Pause after | VO text |", "|---|---|---|---|---|"]
    for b in beats:
        dur = b["t1"] - b["t0"]
        pause = f"{b['pause_after']:.1f}s" if b["pause_after"] >= 0.3 else "—"
        lines.append(f"| {b['id']} | [{fmt_ts(b['t0'])}–{fmt_ts(b['t1'])}] | "
                     f"{dur:.1f}s | {pause} | {b['text']} |")
    hard = [p for p in pauses if p["hard"]]
    if hard:
        lines += ["", "## Cut candidates (hard pauses)", "",
                  "| From | To | Length |", "|---|---|---|"]
        lines += [f"| {fmt_ts(p['t0'])} | {fmt_ts(p['t1'])} | {p['dur']:.1f}s |" for p in hard]
    if keeps:
        lines += ["", "## Keep ranges (pause-free edit)", ""]
        lines += [f"- [{fmt_ts(a)}–{fmt_ts(b)}]" for a, b in keeps]
    mdpath = base.with_suffix(".segments.md")
    mdpath.write_text("\n".join(lines) + "\n")
    return jpath, mdpath


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="media file OR transcript (.srt/.vtt/.json)")
    ap.add_argument("--transcript", help="transcript file to use alongside a media --input")
    ap.add_argument("--beat-length", type=float, default=None, help="target beat length (s)")
    ap.add_argument("--soft-pause", type=float, default=0.6)
    ap.add_argument("--hard-pause", type=float, default=1.2)
    ap.add_argument("--cut-threshold", type=float, default=None,
                    help="pause length that gets cut (default = hard-pause)")
    ap.add_argument("--cut", action="store_true", help="export pause-free keep segments")
    ap.add_argument("--cut-beats", action="store_true", help="export one clip per beat")
    ap.add_argument("--whisper-model", default="small")
    ap.add_argument("--out-dir", help="where cut clips go (default: <input dir>/segments/)")
    args = ap.parse_args()

    target = args.beat_length
    if target is None:
        try:
            from _common import load_config
            target = float(load_config()["defaults"].get("beat_length", 5.0))
        except MotionBuilderError:
            target = 5.0
    cut_threshold = args.cut_threshold or args.hard_pause

    src = Path(args.input).expanduser()
    if not src.exists():
        raise MotionBuilderError(f"input not found: {src}")

    media: Path | None = None
    tpath: Path | None = None
    if src.suffix.lower() in MEDIA_EXT:
        media = src
        if args.transcript:
            tpath = Path(args.transcript).expanduser()
    else:
        tpath = src

    if tpath:
        if tpath.suffix.lower() in {".srt", ".vtt"}:
            segments = parse_srt_vtt(tpath)
        elif tpath.suffix.lower() == ".json":
            segments = parse_json_transcript(tpath)
        else:
            raise MotionBuilderError(
                f"unsupported transcript format: {tpath.suffix} (use .srt/.vtt/.json, or give "
                f"media to transcribe — plain .txt has no timestamps to segment on)")
    elif media:
        segments = transcribe(media, args.whisper_model)
    else:
        raise MotionBuilderError("nothing to do")

    words = to_word_stream(segments)
    if not words:
        raise MotionBuilderError("empty transcript")

    duration = media_duration(media) if media else 0.0
    duration = max(duration, words[-1]["t1"])

    pauses = find_pauses(words, args.soft_pause, args.hard_pause)
    beats = build_beats(words, pauses, target)
    keeps = keep_ranges(duration, pauses, cut_threshold) if media else []

    base = src.parent / src.stem
    jpath, mdpath = write_outputs(base, media, beats, pauses, keeps, duration)
    print(f"  beats: {len(beats)}  pauses: {len(pauses)}  "
          f"hard: {sum(1 for p in pauses if p['hard'])}", file=sys.stderr)

    outdir = Path(args.out_dir).expanduser() if args.out_dir else src.parent / "segments"
    cut_files: list[Path] = []
    if args.cut and media:
        for i, (a, b) in enumerate(keeps, 1):
            out = outdir / f"{src.stem}_keep_{i:02d}.mp4"
            ffmpeg_cut(media, a, b, out)
            cut_files.append(out)
        print(f"  keep clips: {len(cut_files)} → {outdir}", file=sys.stderr)
    if args.cut_beats and media:
        for b in beats:
            out = outdir / f"{src.stem}_beat_{b['id']}.mp4"
            ffmpeg_cut(media, b["t0"], b["t1"], out)
            cut_files.append(out)
        print(f"  beat clips exported → {outdir}", file=sys.stderr)

    print(jpath)
    print(mdpath)
    for f in cut_files:
        print(f)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except MotionBuilderError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)
    except subprocess.CalledProcessError as e:
        print(f"error: subprocess failed: {e}", file=sys.stderr)
        sys.exit(2)
