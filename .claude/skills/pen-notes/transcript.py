#!/usr/bin/env python3
"""Cross-match a meeting transcript (.vtt, Microsoft Teams .docx) with the pen strokes.

    python transcript.py read <transcript>
    python transcript.py cross <transcript> --page <p001.json> [--page ...]
                         (--start 2030-01-15T10:00:00+01:00 | --recording-name <name>)
                         [--offset-s 0] [--before 90] [--after 15]

Transcript times are relative to the start of the recording, hence `--start`. A recording name without
the UTC suffix does not tell its time zone: it is refused. `--offset-s` is added to the pen time to bring
it to the recording's clock. No network, no writing: the result goes to standard output.
"""
import argparse
import json
import re
import statistics
import sys
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.etree import ElementTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sessions import configured_tz, normalise_page  # noqa: E402

SESSION_PAUSE_S = 300  # beyond this, two separate writing sessions (two meetings on one page)
LINE_PAUSE_S = 120
Y_TOLERANCE = 2.5  # Ncode units: vertical gap beyond which a stroke starts a new line
SHARE_IN_MEETING = 0.8

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
TIME = r"\d+:\d{2}(?::\d{2})?(?:[.,]\d+)?"
RE_CUE = re.compile(rf"^\s*({TIME})\s*-->\s*({TIME})")
RE_DOCX_OLD = re.compile(r"^\s*(\d+:\d+:\d+(?:\.\d+)?)\s*-->\s*(\d+:\d+:\d+(?:\.\d+)?)\s*$")
# "First Last   2:13": at least two blanks, so that "meet at 14:30" is not taken for a header.
RE_DOCX_NEW = re.compile(r"^(\S.{0,60}?)(?:\s{2,}|\t)(\d{1,2}:\d{2}(?::\d{2})?)\s*$")
RE_VOICE = re.compile(r"<v\s+([^>]+)>(.*?)(?:</v>|$)", re.S)
RE_TAG = re.compile(r"<[^>]+>")
RE_NAME = re.compile(r"(\d{8})_(\d{6})(UTC)?")

TZ = None  # time zone of the output (None = the computer's); set from the configuration by main()


class TranscriptError(Exception):
    """Unreadable file or uncertain start time: stop rather than guess."""


def seconds(text):
    total = 0.0
    for part in (float(p.replace(",", ".")) for p in text.split(":")):
        total = total * 60 + part
    return total


def read_vtt(text):
    segments = []
    for block in re.split(r"\r?\n\s*\r?\n", text.lstrip("﻿")):
        lines = block.splitlines()
        for i, line in enumerate(lines):
            cue = RE_CUE.match(line)
            if not cue:
                continue
            content = "\n".join(lines[i + 1:])
            voices = RE_VOICE.findall(content) or [(None, content)]
            for speaker, words in voices:
                words = " ".join(RE_TAG.sub("", words).split())
                if words:
                    segments.append({"start": seconds(cue[1]), "end": seconds(cue[2]),
                                     "speaker": speaker.strip() if speaker else None, "text": words})
            break
    return segments


def docx_lines(path):
    try:
        with zipfile.ZipFile(path) as archive:
            root = ElementTree.fromstring(archive.read("word/document.xml"))
    except (zipfile.BadZipFile, KeyError, ElementTree.ParseError) as error:
        raise TranscriptError(f"unreadable Word document: {error}") from error
    lines = []
    for paragraph in root.iter(f"{W}p"):
        parts = []
        for node in paragraph.iter():
            if node.tag == f"{W}t":
                parts.append(node.text or "")
            elif node.tag == f"{W}tab":
                parts.append("\t")
            elif node.tag in (f"{W}br", f"{W}cr"):
                parts.append("\n")
        lines.extend("".join(parts).split("\n"))
    return [line for line in lines if line.strip()]


def read_docx(lines):
    """Two known layouts: "start --> end / name / text" and "name   m:ss / text"."""
    segments = []
    current = None
    expect_name = False
    for line in lines:
        old = RE_DOCX_OLD.match(line)
        new = RE_DOCX_NEW.match(line)
        if old:
            current = {"start": seconds(old[1]), "end": seconds(old[2]), "speaker": None, "text": ""}
            segments.append(current)
            expect_name = True
        elif new and (not segments or seconds(new[2]) >= segments[-1]["start"]):
            current = {"start": seconds(new[2]), "end": None, "speaker": new[1].strip(), "text": ""}
            segments.append(current)
            expect_name = False
        elif current is not None and expect_name:
            current["speaker"] = line.strip()
            expect_name = False
        elif current is not None:
            current["text"] = f"{current['text']} {line.strip()}".strip()
    segments = [s for s in segments if s["text"]]
    for segment, following in zip(segments, segments[1:]):
        if segment["end"] is None:
            segment["end"] = following["start"]
    if segments and segments[-1]["end"] is None:
        segments[-1]["end"] = segments[-1]["start"] + 30
    return segments


def read_transcript(path):
    path = Path(path)
    extension = path.suffix.lower()
    if extension == ".vtt":
        segments = read_vtt(path.read_text(encoding="utf-8-sig"))
    elif extension == ".docx":
        segments = read_docx(docx_lines(path))
    else:
        raise TranscriptError(f"unsupported format: {extension or path.name}")
    if not segments:
        raise TranscriptError("no timed utterance found: unrecognised format")
    return segments


def start_from_name(name):
    found = RE_NAME.search(name)
    if not found:
        raise TranscriptError("no YYYYMMDD_HHMMSS time in this name: give --start")
    if not found[3]:
        raise TranscriptError("this name does not say UTC: time to be confirmed, give --start")
    return datetime.strptime(found[1] + found[2], "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)


def parse_start(text):
    try:
        start = datetime.fromisoformat(text)
    except ValueError as error:
        raise TranscriptError(f"invalid --start: {text}") from error
    return start if start.tzinfo else start.astimezone()


def centre_y(stroke):
    ys = [point[1] for point in stroke["points"]]
    return (min(ys) + max(ys)) / 2


def split_lines(strokes):
    """Group strokes into lines of writing: same height, no long pause."""
    lines = []
    for stroke in sorted((s for s in strokes if s.get("points")), key=lambda s: s["start"]):
        y = centre_y(stroke)
        line = lines[-1] if lines else None
        if (line is None or stroke["start"] - line["end"] > LINE_PAUSE_S * 1000
                or abs(y - statistics.median(line["ys"])) > Y_TOLERANCE):
            line = {"start": stroke["start"], "end": stroke["end"], "ys": []}
            lines.append(line)
        line["ys"].append(y)
        line["end"] = max(line["end"], stroke["end"])
    return lines


def split_sessions(strokes):
    sessions = []
    for stroke in sorted(strokes, key=lambda s: s["start"]):
        if not sessions or stroke["start"] - sessions[-1]["end"] > SESSION_PAUSE_S * 1000:
            sessions.append({"start": stroke["start"], "end": stroke["end"]})
        sessions[-1]["end"] = max(sessions[-1]["end"], stroke["end"])
    return sessions


def covered_share(session, start_ms, end_ms):
    duration = session["end"] - session["start"]
    common = min(session["end"], end_ms) - max(session["start"], start_ms)
    if duration <= 0:
        return 1.0 if start_ms <= session["start"] <= end_ms else 0.0
    return max(0.0, common / duration)


def merge(segments):
    """Transcripts cut a sentence into several utterances: join consecutive ones of the same speaker."""
    merged = []
    for segment in segments:
        if merged and merged[-1]["speaker"] == segment["speaker"]:
            merged[-1]["text"] += " " + segment["text"]
            merged[-1]["end"] = segment["end"]
        else:
            merged.append(dict(segment))
    return merged


def iso(ms):
    moment = datetime.fromtimestamp(ms / 1000, timezone.utc)
    return (moment.astimezone(TZ) if TZ else moment.astimezone()).isoformat(timespec="seconds")


def cross(segments, pages, start, offset_s=0, before=90, after=15):
    """`pages`: list of (name, page JSON). Returns the lines, their excerpts and the verdict."""
    pages = [(name, normalise_page(page)) for name, page in pages]
    start_ms = start.timestamp() * 1000
    end_ms = start_ms + max(s["end"] for s in segments) * 1000
    offset_ms = offset_s * 1000

    def shift(stroke):
        return {**stroke, "start": stroke["start"] + offset_ms, "end": stroke["end"] + offset_ms}

    strokes = [shift(s) for _, page in pages for s in page["strokes"]]
    if not strokes:
        raise TranscriptError("no stroke on these pages")
    sessions = split_sessions(strokes)
    reasons = []
    for session in sessions:
        session["share"] = round(covered_share(session, start_ms, end_ms), 2)
        session["in_meeting"] = session["share"] >= SHARE_IN_MEETING
        if 0 < session["share"] < SHARE_IN_MEETING:
            reasons.append(f"session starting {iso(session['start'])} overlaps the meeting edge "
                           f"({session['share']:.0%} inside)")
    kept = [s for s in sessions if s["in_meeting"]]
    if not kept:
        reasons.append("no writing session during the meeting")
    verdict = "uncertain" if reasons else "ok"

    out_pages = []
    for name, page in pages:
        out_lines = []
        for number, line in enumerate(split_lines([shift(s) for s in page["strokes"]]), 1):
            inside = any(s["start"] <= line["start"] <= s["end"] for s in kept)
            excerpts = []
            if verdict == "ok" and inside:
                lo = (line["start"] - start_ms) / 1000 - before
                hi = (line["end"] - start_ms) / 1000 + after
                excerpts = [{"time": iso(start_ms + s["start"] * 1000), "speaker": s["speaker"], "text": s["text"]}
                            for s in merge([s for s in segments if s["end"] >= lo and s["start"] <= hi])]
            out_lines.append({"n": number, "y": round(statistics.median(line["ys"]), 1),
                              "start": iso(line["start"]), "end": iso(line["end"]),
                              "in_meeting": inside, "excerpts": excerpts})
        out_pages.append({"page": name, "lines": out_lines})
    return {"start": iso(start_ms), "end": iso(end_ms), "offset_s": offset_s, "utterances": len(segments),
            "verdict": verdict, "reasons": reasons,
            "sessions": [{**s, "start": iso(s["start"]), "end": iso(s["end"])} for s in sessions],
            "pages": out_pages}


def main(arguments=None):
    global TZ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    read = commands.add_parser("read")
    read.add_argument("transcript")
    crossp = commands.add_parser("cross")
    crossp.add_argument("transcript")
    crossp.add_argument("--page", action="append", required=True)
    source = crossp.add_mutually_exclusive_group(required=True)
    source.add_argument("--start")
    source.add_argument("--recording-name")
    crossp.add_argument("--offset-s", type=float, default=0)
    crossp.add_argument("--before", type=float, default=90)
    crossp.add_argument("--after", type=float, default=15)
    options = parser.parse_args(arguments)
    TZ = configured_tz()
    try:
        segments = read_transcript(options.transcript)
        if options.command == "read":
            for segment in merge(segments):
                time = str(timedelta(seconds=int(segment["start"])))
                print(f"[{time}] {segment['speaker'] or '?'}: {segment['text']}")
            return 0
        start = parse_start(options.start) if options.start else start_from_name(options.recording_name)
        pages = [(p, json.loads(Path(p).read_text(encoding="utf-8"))) for p in options.page]
        result = cross(segments, pages, start, options.offset_s, options.before, options.after)
    except (TranscriptError, OSError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
