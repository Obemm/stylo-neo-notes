"""The only command the automatic conversion may run.

The shortcut script starts `claude -p` without a free shell: the only allowed command is this script,
which can only do what the conversion needs. It never runs the pen's `sync`, never erases anything from
the pen, and writes only into the vault (attachments), the reference copies and a local temp folder.

    python pen_tool.py pending                    # pages to convert (JSON from the pen tool)
    python pen_tool.py sessions <key> [<key> ...] # writing sessions of pages (JSON)
    python pen_tool.py png <key> [--rotate]       # path of the PNG to read (rotated 180 degrees on request)
    python pen_tool.py copy-svg <key> [--rotate]  # SVG copied into the vault attachments folder
    python pen_tool.py mark-done <key>            # after the note is written
    python pen_tool.py reference <note.md> [...]  # keep the converter's version of a note
    python pen_tool.py forget <note.md>           # drop the copy of a renamed or deleted note
    python pen_tool.py changed                    # notes corrected since their copy (JSON + diff)
    python pen_tool.py config                     # resolved configuration (JSON)
    python pen_tool.py status                     # pages pending, notes corrected, notebooks (JSON, for the window)
    python pen_tool.py migrate-vault [--dry-run]  # rename legacy frontmatter keys (stylo_* -> pen_*)
    python pen_tool.py paste-save --kind notes|transcript --text-file F --date YYYY-MM-DD [--start HH:MM]
                       [--end HH:MM] [--title T] [--event-id ID] [--private]
                                                  # keep pasted notes / a meeting transcript in the vault (JSON)
    python pen_tool.py pasted                     # pasted items not processed yet (JSON)
    python pen_tool.py mark-pasted <file.md>      # after the pasted item is turned into notes

<key> = "3-27-551/p007". <note.md> = path relative to the vault, inside the notebooks, journal or
meetings folder of the configuration. Configuration: see config.example.toml at the repository root.
"""
from __future__ import annotations

import difflib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import config as cfg  # noqa: E402
import sessions as mod_sessions  # noqa: E402

KEY = re.compile(r"^(\d+-\d+-\d+)/p(\d{3})$")
# Frontmatter keys written by older versions of the converter.
LEGACY_FRONTMATTER_KEYS = {"stylo_pages": "pen_pages", "stylo_empreintes": "pen_hashes",
                           "stylo_seances": "pen_sessions"}
FRONTMATTER = re.compile(r"\A(---[ \t]*\r?\n)(.*?\r?\n)(---[ \t]*(?:\r?\n|\Z))", re.S)
LEGACY_KEY_LINE = re.compile(rf"^({'|'.join(LEGACY_FRONTMATTER_KEYS)})(?=[ \t]*:)", re.M)

CONF: cfg.Config | None = None
PASTE_KINDS = {"notes": {"en": "notes", "fr": "notes"}, "transcript": {"en": "transcript", "fr": "transcription"}}
HHMM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


def _conf() -> cfg.Config:
    global CONF
    if CONF is None:
        CONF = cfg.load()
    return CONF


class Refused(SystemExit):
    """A request outside what this tool allows (exits with a message on stderr)."""


def _pen(*args: str) -> subprocess.CompletedProcess:
    c = _conf()
    if not c.exe.is_file():
        raise Refused(f"pen executable not found: {c.exe} (build it with pen/publish.ps1 or set [pen] exe)")
    return subprocess.run([str(c.exe), *args, "--data-dir", str(c.require_data_dir())],
                          capture_output=True, text=True, encoding="utf-8", errors="replace")


def _page_file(key: str, ext: str) -> Path:
    m = KEY.match(key)
    if not m:
        raise Refused(f"invalid key: {key!r} (expected 3-27-551/p007)")
    path = _conf().require_data_dir() / "pages" / m.group(1) / f"p{m.group(2)}.{ext}"
    if not path.is_file():
        raise Refused(f"page not found: {path}")
    return path


def _flat(key: str) -> str:
    return key.replace("/", "-")


def pending() -> int:
    r = _pen("pending", "--json")
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
    return r.returncode


def sessions(keys: list[str]) -> int:
    tz = _conf().tz()
    result = dict(mod_sessions.sessions(_page_file(k, "json"), tz=tz) for k in keys)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def png(key: str, rotate: bool) -> int:
    source = _page_file(key, "png")
    if not rotate:
        print(source)
        return 0
    from PIL import Image
    target_dir = _conf().rotated_dir
    target_dir.mkdir(parents=True, exist_ok=True)
    target = target_dir / f"{_flat(key)}-rotated.png"
    with Image.open(source) as image:
        image.rotate(180).save(target)
    print(target)
    return 0


def copy_svg(key: str, rotate: bool) -> int:
    text = _page_file(key, "svg").read_text(encoding="utf-8")
    if rotate:
        vb = re.search(r'viewBox="([\d.\-]+) ([\d.\-]+) ([\d.\-]+) ([\d.\-]+)"', text)
        if not vb:
            raise Refused("viewBox not found: cannot rotate the SVG")
        x, y, w, h = map(float, vb.groups())
        text = text.replace("<g ", f'<g transform="rotate(180 {x + w / 2:.3f} {y + h / 2:.3f})" ', 1)
    c = _conf()
    target = c.require_vault() / c.attachments_dir / f"{_flat(key)}.svg"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")
    print(target)
    return 0


def mark_done(key: str) -> int:
    _page_file(key, "json")  # key checked before calling the pen tool
    r = _pen("mark-done", key)
    sys.stdout.write(r.stdout or r.stderr)
    return r.returncode


def _inside(rel: Path, folder: str) -> bool:
    parts = Path(folder).parts
    return len(rel.parts) > len(parts) and rel.parts[:len(parts)] == parts


def _note(rel: str) -> tuple[Path, Path]:
    """Path of a tracked vault note and of its reference copy; refuses anything else."""
    c = _conf()
    relp = Path(rel.replace("\\", "/"))
    if (relp.is_absolute() or relp.drive or relp.root or ".." in relp.parts or relp.suffix != ".md"
            or not any(_inside(relp, d) for d in c.tracked_dirs)):
        raise Refused(f"note refused: {rel!r} (expected a .md path relative to the vault, inside "
                      f"{', '.join(c.tracked_dirs)})")
    return c.require_vault() / relp, c.references / relp


def _read(p: Path) -> str:
    return p.read_text(encoding="utf-8").replace("\r\n", "\n")


def reference(notes: list[str]) -> int:
    for rel in notes:
        note, copy = _note(rel)
        if not note.is_file():
            raise Refused(f"note not found: {note}")
        copy.parent.mkdir(parents=True, exist_ok=True)
        copy.write_text(_read(note), encoding="utf-8")
        print(f"reference: {rel}")
    return 0


def forget(rel: str) -> int:
    note, copy = _note(rel)
    if note.is_file():
        raise Refused(f"the note still exists: {rel} (forget is for renamed or deleted notes)")
    if copy.is_file():
        copy.unlink()
    print(f"forgotten: {rel}")
    return 0


def _tracked(base: Path) -> dict[str, Path]:
    return {p.relative_to(base).as_posix(): p for d in _conf().tracked_dirs for p in (base / d).rglob("*.md")}


def _diff(before: str, after: str, old: str, new: str) -> str:
    return "\n".join(difflib.unified_diff(before.splitlines(), after.splitlines(), old, new, n=2, lineterm=""))


def _changed() -> tuple[Path, list[dict]]:
    """Compare each tracked note with its copy: modified, renamed, deleted, or without reference."""
    c = _conf()
    vault = c.require_vault()
    notes, copies = _tracked(vault), _tracked(c.references)
    result, orphans = [], []
    for rel, copy in sorted(copies.items()):
        if rel in notes:
            before, after = _read(copy), _read(notes[rel])
            if before != after:
                result.append({"note": rel, "state": "modified", "diff": _diff(before, after, rel, rel)})
        else:
            orphans.append(rel)
    without_copy = [r for r in sorted(notes) if r not in copies]
    # A copy without a note and a note without a copy with close content = a renamed or moved note.
    for rel in orphans:
        before = _read(copies[rel])
        ratio = {r: difflib.SequenceMatcher(None, before, _read(notes[r])).ratio() for r in without_copy}
        best = max(ratio, key=ratio.get, default=None)
        if best and ratio[best] >= 0.6:
            without_copy.remove(best)
            after = _read(notes[best])
            result.append({"note": best, "state": "renamed", "old": rel,
                           "diff": _diff(before, after, rel, best) if before != after else ""})
        else:
            result.append({"note": rel, "state": "deleted"})
    result += [{"note": r, "state": "no_reference"} for r in without_copy]
    return vault, result


def changed() -> int:
    vault, result = _changed()
    json.dump({"vault": str(vault), "notes": result}, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def status() -> int:
    """Summary for the desktop window: pages pending, notes corrected by the user, known notebooks."""
    c = _conf()
    _, notes = _changed()
    corrected = sum(1 for n in notes if n["state"] in ("modified", "renamed", "deleted"))
    pending_count, error = None, None
    try:
        r = _pen("pending", "--json")
        if r.returncode == 0:
            pending_count = len(json.loads(r.stdout)["pages"])
        else:
            error = (r.stderr or r.stdout).strip()[:300]
    except Refused as refused:
        error = str(refused)
    pages = c.require_data_dir() / "pages"
    notebooks = sorted(d.name for d in pages.iterdir() if d.is_dir()) if pages.is_dir() else []
    json.dump({"pending": pending_count, "corrected": corrected, "no_reference": len(notes) - corrected,
               "notebooks": notebooks, "error": error}, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def show_config() -> int:
    json.dump(_conf().as_dict(), sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def migrate_text(text: str) -> str:
    """Rename the legacy keys inside the YAML frontmatter block only."""
    m = FRONTMATTER.match(text)
    if not m:
        return text
    body = LEGACY_KEY_LINE.sub(lambda k: LEGACY_FRONTMATTER_KEYS[k.group(1)], m.group(2))
    return m.group(1) + body + m.group(3) + text[m.end():]


def migrate_vault(dry_run: bool) -> int:
    c = _conf()
    changed_files = []
    for base in (c.require_vault(), c.references):
        for path in sorted(_tracked(base).values()):
            raw = path.read_bytes().decode("utf-8")
            new = migrate_text(raw)
            if new != raw:
                changed_files.append(str(path))
                if not dry_run:
                    path.write_bytes(new.encode("utf-8"))
    json.dump({"dry_run": dry_run, "changed": changed_files}, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def _paste_dir() -> Path:
    c = _conf()
    folder = c.in_vault(c.transcripts_dir)
    if folder is None:
        raise Refused("transcripts folder outside the vault")
    return folder


def _yaml_str(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)   # a JSON string is a valid YAML scalar


def paste_save(opts: dict[str, str], private: bool) -> int:
    """Store pasted text with what the window knows about it; the converter turns it into notes later."""
    kind, day = opts.get("--kind"), opts.get("--date", "")
    if kind not in PASTE_KINDS:
        raise Refused("--kind must be notes or transcript")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", day):
        raise Refused("--date expects YYYY-MM-DD")
    start, end = opts.get("--start", ""), opts.get("--end", "")
    for value in (start, end):
        if value and not HHMM.match(value):
            raise Refused("--start / --end expect HH:MM")
    source = Path(opts.get("--text-file", ""))
    if not source.is_file():
        raise Refused(f"text file not found: {source}")
    text = source.read_text(encoding="utf-8").replace("\r\n", "\n").strip()
    if not text:
        raise Refused("nothing to save: the pasted text is empty")
    title = " ".join(re.sub(r'[/\\:*?"<>|\n\r\t]+', " ", opts.get("--title", "")).split())[:80]
    c = _conf()
    label = PASTE_KINDS[kind][c.language]
    stem = f"{day} {(start or '00:00').replace(':', 'h')} {title or label} ({label})"
    folder = _paste_dir()
    folder.mkdir(parents=True, exist_ok=True)
    target, n = folder / f"{stem}.md", 2
    while target.exists():
        target, n = folder / f"{stem} {n}.md", n + 1
    front = ["---", f"pasted: {kind}", f"date: {day}"]
    front += [f"start: {start}"] if start else []
    front += [f"end: {end}"] if end else []
    meeting = " ".join(opts.get("--title", "").split())[:200]   # the subject as given, on one line
    front += [f"meeting: {_yaml_str(meeting)}"] if meeting else []
    front += [f"event_id: {_yaml_str(opts['--event-id'])}"] if opts.get("--event-id") else []
    front += ["private: true"] if private else []
    front += ["processed: false", "---", ""]
    target.write_text("\n".join(front) + text + "\n", encoding="utf-8")
    vault = c.require_vault()
    json.dump({"file": target.relative_to(vault).as_posix(), "characters": len(text)}, sys.stdout, ensure_ascii=False)
    print()
    return 0


def _front(text: str) -> dict[str, str]:
    m = FRONTMATTER.match(text)
    if not m:
        return {}
    pairs = (line.split(":", 1) for line in m.group(2).splitlines() if ":" in line)
    return {k.strip(): v.strip() for k, v in pairs}


def pasted() -> int:
    folder, vault = _paste_dir(), _conf().require_vault()
    items = []
    for f in sorted(folder.glob("*.md")) if folder.is_dir() else []:
        meta = _front(_read(f))
        if meta.get("pasted") in PASTE_KINDS and meta.get("processed", "false") == "false":
            items.append({"file": f.relative_to(vault).as_posix(), **{k: meta[k] for k in
                          ("pasted", "date", "start", "end", "meeting", "event_id", "private") if k in meta}})
    json.dump({"pasted": items}, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


def mark_pasted(rel: str) -> int:
    folder, vault = _paste_dir(), _conf().require_vault()
    relp = Path(rel.replace("\\", "/"))
    if relp.is_absolute() or ".." in relp.parts or relp.suffix != ".md":
        raise Refused(f"file refused: {rel!r}")
    path = vault / relp
    if path.parent.resolve() != folder.resolve() or not path.is_file():
        raise Refused(f"not a pasted item of the transcripts folder: {rel!r}")
    text = path.read_bytes().decode("utf-8")
    if _front(text).get("pasted") not in PASTE_KINDS:
        raise Refused(f"not a pasted item: {rel!r}")
    from datetime import date
    new = re.sub(r"(?m)^processed:[ \t]*false[ \t]*\r?$", f"processed: {date.today().isoformat()}", text, count=1)
    path.write_bytes(new.encode("utf-8"))
    print(f"processed: {rel}")
    return 0


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):  # redirected output on Windows = cp1252: "⇒" would crash it
        sys.stdout.reconfigure(encoding="utf-8")
    if not argv:
        print(__doc__)
        return 2
    cmd, args = argv[0], argv[1:]
    rotate = "--rotate" in args
    dry_run = "--dry-run" in args
    flags = {"png": ["--rotate"], "copy-svg": ["--rotate"], "migrate-vault": ["--dry-run"],
             "paste-save": ["--private"]}.get(cmd, [])
    private = "--private" in args
    args = [a for a in args if a not in flags]
    try:
        if cmd == "pending" and not args:
            return pending()
        if cmd == "sessions" and args:
            return sessions(args)
        if cmd == "png" and len(args) == 1:
            return png(args[0], rotate)
        if cmd == "copy-svg" and len(args) == 1:
            return copy_svg(args[0], rotate)
        if cmd == "mark-done" and len(args) == 1:
            return mark_done(args[0])
        if cmd == "reference" and args:
            return reference(args)
        if cmd == "forget" and len(args) == 1:
            return forget(args[0])
        if cmd == "changed" and not args:
            return changed()
        if cmd == "paste-save" and args and len(args) % 2 == 0:
            opts = dict(zip(args[::2], args[1::2]))
            allowed = {"--kind", "--text-file", "--date", "--start", "--end", "--title", "--event-id"}
            if set(opts) <= allowed:
                return paste_save(opts, private)
        if cmd == "pasted" and not args:
            return pasted()
        if cmd == "mark-pasted" and len(args) == 1:
            return mark_pasted(args[0])
        if cmd == "status" and not args:
            return status()
        if cmd == "config" and not args:
            return show_config()
        if cmd == "migrate-vault" and not args:
            return migrate_vault(dry_run)
    except cfg.ConfigError as error:
        raise SystemExit(f"configuration error: {error}") from error
    print(f"command refused: {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
