"""Split a pen page into writing sessions.

A session is a run of strokes with no pause longer than 5 minutes. For each session: start and end time
(in the configured time zone, or the computer's when none is set), number of strokes, height used on the
page (y min / max, in Ncode units), and the label to copy into the `pen_sessions` field of the notes.

    python sessions.py <page.json> [<page.json> ...] [--pause-min 5] [--timezone Area/City]

JSON output: {"<notebook>/pNNN": [{"label": "2030-01-15 09:00-09:42", "start": ..., "end": ...,
"strokes": 52, "y_min": 40.1, "y_max": 68.1}, ...], ...}. Only reads the given files, writes nothing.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import tzinfo
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config as cfg  # noqa: E402

# Page JSON written by older versions of the pen tool used French keys.
LEGACY_PAGE_KEYS = {"traits": "strokes", "proprietaire": "owner", "carnet": "notebook"}
LEGACY_STROKE_KEYS = {"debut": "start", "fin": "end", "couleur": "color"}


def normalise_page(page: dict) -> dict:
    """Return the page with current (English) keys, whatever version of the pen tool wrote it."""
    out = {LEGACY_PAGE_KEYS.get(k, k): v for k, v in page.items()}
    out["strokes"] = [{LEGACY_STROKE_KEYS.get(k, k): v for k, v in s.items()} for s in out.get("strokes", [])]
    return out


def read_page(path: Path) -> dict:
    return normalise_page(json.loads(Path(path).read_text(encoding="utf-8")))


def _y(point) -> float:
    return point["y"] if isinstance(point, dict) else point[1]


def sessions(path: Path, pause_min: float = 5.0, tz: tzinfo | None = None) -> tuple[str, list[dict]]:
    page = read_page(path)
    key = f"{page['section']}-{page['owner']}-{page['notebook']}/p{int(page['page']):03d}"
    strokes = sorted(page["strokes"], key=lambda s: s["start"])
    groups: list[list[dict]] = []
    for s in strokes:
        if groups and s["start"] - groups[-1][-1]["end"] <= pause_min * 60_000:
            groups[-1].append(s)
        else:
            groups.append([s])
    out = []
    for g in groups:
        start = cfg.local_time(g[0]["start"], tz)
        end = cfg.local_time(max(s["end"] for s in g), tz)
        ys = [_y(p) for s in g for p in s["points"]]
        out.append({
            "label": f"{start:%Y-%m-%d %H:%M}-{end:%H:%M}",
            "start": start.isoformat(timespec="seconds"),
            "end": end.isoformat(timespec="seconds"),
            "strokes": len(g),
            "y_min": round(min(ys), 1) if ys else None,
            "y_max": round(max(ys), 1) if ys else None,
        })
    return key, out


def configured_tz() -> tzinfo | None:
    """Time zone from the configuration; the computer's when none is set or no configuration exists."""
    try:
        return cfg.load(require_vault=False).tz()
    except cfg.ConfigError:
        return None


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pages", nargs="+", type=Path)
    ap.add_argument("--pause-min", type=float, default=5.0)
    ap.add_argument("--timezone", help="IANA name; default = configuration, else the computer's time zone")
    args = ap.parse_args(argv)
    tz = ZoneInfo(args.timezone) if args.timezone else configured_tz()
    result = dict(sessions(p, args.pause_min, tz) for p in args.pages)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
