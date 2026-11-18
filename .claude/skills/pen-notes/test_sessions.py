"""Tests of sessions.py on fictitious pages, current and legacy JSON layouts."""
import json
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import sessions as s

T0 = int(datetime(2030, 1, 15, 9, 0, tzinfo=timezone.utc).timestamp() * 1000)
MIN = 60_000


def stroke(start_min, y=10.0, minutes=1):
    return {"start": T0 + start_min * MIN, "end": T0 + (start_min + minutes) * MIN, "color": "#000000",
            "points": [[1.0, y, 0.5, T0 + start_min * MIN], [2.0, y + 2, 0.5, T0 + start_min * MIN + 10]]}


def page(strokes):
    return {"section": 3, "owner": 27, "notebook": 551, "page": 7, "strokes": strokes}


def legacy(p):
    return {"section": p["section"], "proprietaire": p["owner"], "carnet": p["notebook"], "page": p["page"],
            "traits": [{"debut": t["start"], "fin": t["end"], "couleur": t["color"], "points": t["points"]}
                       for t in p["strokes"]]}


def write(tmp_path, data, name="p007.json"):
    path = tmp_path / name
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def test_pause_splits_sessions(tmp_path):
    key, out = s.sessions(write(tmp_path, page([stroke(0), stroke(3, y=30), stroke(20, y=50)])),
                          tz=ZoneInfo("UTC"))
    assert key == "3-27-551/p007"
    assert [o["label"] for o in out] == ["2030-01-15 09:00-09:04", "2030-01-15 09:20-09:21"]
    assert [o["strokes"] for o in out] == [2, 1]
    assert (out[0]["y_min"], out[0]["y_max"]) == (10.0, 32.0)


def test_timezone_applied(tmp_path):
    _, out = s.sessions(write(tmp_path, page([stroke(0)])), tz=ZoneInfo("Asia/Tokyo"))
    assert out[0]["label"] == "2030-01-15 18:00-18:01"
    assert out[0]["start"].endswith("+09:00")


def test_legacy_page_json(tmp_path):
    current = page([stroke(0), stroke(10)])
    assert s.sessions(write(tmp_path, legacy(current), "old.json"), tz=ZoneInfo("UTC")) == \
        s.sessions(write(tmp_path, current), tz=ZoneInfo("UTC"))


def test_normalise_keeps_current_keys():
    p = page([stroke(0)])
    assert s.normalise_page(p) == p


def test_cli(tmp_path, capsys):
    path = write(tmp_path, page([stroke(0)]))
    assert s.main([str(path), "--timezone", "UTC"]) == 0
    assert json.loads(capsys.readouterr().out)["3-27-551/p007"][0]["label"] == "2030-01-15 09:00-09:01"
