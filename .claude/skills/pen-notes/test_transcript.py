"""Tests of transcript.py, on fictitious data only."""
import json
import zipfile
from datetime import datetime, timedelta, timezone

import pytest

import transcript as t

START = datetime(2030, 1, 15, 9, 0, 0, tzinfo=timezone.utc)
VTT = """WEBVTT

a1b2/12-0
00:00:10.000 --> 00:00:14.000
<v Alice Martin>We keep option A.</v>

a1b2/13-0
00:00:14.000 --> 00:00:18.000
<v Alice Martin>It is cheaper.</v>

00:10:00.000 --> 00:10:05.000
<v Bruno Petit>I will handle the quote.</v>
"""
W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'


def ms(secs):
    return int((START + timedelta(seconds=secs)).timestamp() * 1000)


def stroke(secs, y=10.0, duration=2):
    return {"start": ms(secs), "end": ms(secs + duration), "points": [[1, y, 0.5, ms(secs)]]}


def docx(path, paragraphs):
    body = "".join(f"<w:p>{p}</w:p>" for p in paragraphs)
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("word/document.xml", f"<w:document {W}><w:body>{body}</w:body></w:document>")
    return path


def r(text):
    return f'<w:r><w:t xml:space="preserve">{text}</w:t></w:r>'


def test_vtt_speakers_and_times():
    segments = t.read_vtt(VTT)
    assert len(segments) == 3
    assert segments[0] == {"start": 10.0, "end": 14.0, "speaker": "Alice Martin", "text": "We keep option A."}


def test_vtt_without_speaker():
    segments = t.read_vtt("WEBVTT\n\n00:01.000 --> 00:02.500\nHello <b>to</b> all\n")
    assert segments == [{"start": 1.0, "end": 2.5, "speaker": None, "text": "Hello to all"}]


def test_docx_new_layout(tmp_path):
    path = docx(tmp_path / "r.docx", [r("Fictitious meeting"), r("Alice Martin   0:10"), r("We keep A."),
                                      r("meet at 14:30"), r("Bruno Petit   1:05"), r("The quote.")])
    segments = t.read_transcript(path)
    assert [s["speaker"] for s in segments] == ["Alice Martin", "Bruno Petit"]
    assert segments[0]["text"] == "We keep A. meet at 14:30"
    assert segments[0]["end"] == 65


def test_docx_old_layout(tmp_path):
    path = docx(tmp_path / "a.docx", [r("0:0:3.120 --> 0:0:5.0") + "<w:r><w:br/></w:r>" + r("Alice Martin")
                                      + "<w:r><w:br/></w:r>" + r("Hello.")])
    assert t.read_transcript(path) == [{"start": 3.12, "end": 5.0, "speaker": "Alice Martin", "text": "Hello."}]


@pytest.mark.parametrize("name,content", [("v.vtt", "WEBVTT\n\nnothing\n"), ("n.txt", "x")])
def test_unrecognised_format(tmp_path, name, content):
    path = tmp_path / name
    path.write_text(content, encoding="utf-8")
    with pytest.raises(t.TranscriptError):
        t.read_transcript(path)


def test_utc_name_accepted():
    assert t.start_from_name("Review-20300115_090000UTC-Meeting Recording.mp4") == START


@pytest.mark.parametrize("name", ["Review-20300115_100000-Recording.mp4", "Review.mp4"])
def test_name_without_utc_refused(name):
    with pytest.raises(t.TranscriptError):
        t.start_from_name(name)


def test_start_with_utc_offset():
    assert t.parse_start("2030-01-15T10:00:00+01:00") == START


def test_excerpt_of_the_line():
    result = t.cross(t.read_vtt(VTT), [("p1", {"strokes": [stroke(20), stroke(601, y=20)]})], START, after=0)
    assert result["verdict"] == "ok"
    first, second = result["pages"][0]["lines"]
    assert first["excerpts"][0]["text"] == "We keep option A. It is cheaper."
    assert second["excerpts"][0]["speaker"] == "Bruno Petit"
    assert len(first["excerpts"]) == len(second["excerpts"]) == 1


def test_legacy_page_keys():
    legacy = {"traits": [{"debut": s["start"], "fin": s["end"], "points": s["points"]} for s in (stroke(20),)]}
    assert t.cross(t.read_vtt(VTT), [("p1", legacy)], START) == t.cross(t.read_vtt(VTT), [("p1", {"strokes": [stroke(20)]})], START)


def test_lines_split_by_height():
    assert len(t.split_lines([stroke(1), stroke(4, y=10.5), stroke(8, y=20)])) == 2


def test_pen_outside_meeting_no_match():
    result = t.cross(t.read_vtt(VTT), [("p1", {"strokes": [stroke(7200)]})], START)
    assert result["verdict"] == "uncertain"
    assert result["pages"][0]["lines"][0]["excerpts"] == []


def test_session_overlapping_edge_no_match():
    strokes = [stroke(590, duration=60)]  # ends 45 s after the last utterance, less than 80 % inside
    result = t.cross(t.read_vtt("WEBVTT\n\n00:00.000 --> 10:05.000\n<v A>x</v>\n"), [("p", {"strokes": strokes})], START)
    assert result["verdict"] == "uncertain"
    assert result["reasons"]


def test_two_meetings_on_one_page():
    result = t.cross(t.read_vtt(VTT), [("p", {"strokes": [stroke(20), stroke(7200, y=30)]})], START)
    assert result["verdict"] == "ok"
    inside, outside = result["pages"][0]["lines"]
    assert inside["excerpts"] and inside["in_meeting"]
    assert not outside["excerpts"] and not outside["in_meeting"]


def test_pen_clock_offset():
    pages = [("p", {"strokes": [stroke(7220)]})]
    assert t.cross(t.read_vtt(VTT), pages, START)["verdict"] == "uncertain"
    result = t.cross(t.read_vtt(VTT), pages, START, offset_s=-7200)
    assert result["verdict"] == "ok"
    assert result["pages"][0]["lines"][0]["excerpts"]


def test_command_line(tmp_path, capsys):
    vtt = tmp_path / "r.vtt"
    vtt.write_text(VTT, encoding="utf-8")
    page = tmp_path / "p001.json"
    page.write_text(json.dumps({"strokes": [stroke(20)]}), encoding="utf-8")
    assert t.main(["cross", str(vtt), "--page", str(page), "--start", START.isoformat()]) == 0
    assert json.loads(capsys.readouterr().out)["verdict"] == "ok"
    assert t.main(["cross", str(vtt), "--page", str(page), "--recording-name", "R-20300115_100000-E.mp4"]) == 2
    assert t.main(["read", str(vtt)]) == 0
    assert "Alice Martin: We keep option A. It is cheaper." in capsys.readouterr().out
