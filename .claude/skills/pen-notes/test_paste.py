"""Tests of the pasted notes / transcripts commands of pen_tool.py. Fictitious content."""
from __future__ import annotations

import json

import pytest

import pen_tool


@pytest.fixture
def vault(tmp_path, monkeypatch):
    v = tmp_path / "vault"
    v.mkdir()
    monkeypatch.setenv("STYLO_NEO_VAULT", str(v))
    monkeypatch.setenv("STYLO_NEO_REFERENCES", str(tmp_path / "refs"))
    monkeypatch.setattr(pen_tool, "CONF", None)
    return v


def run(capsys, *args):
    code = pen_tool.main(list(args))
    return code, capsys.readouterr().out


def text_file(tmp_path, text):
    f = tmp_path / "paste.txt"
    f.write_text(text, encoding="utf-8")
    return str(f)


def test_save_list_mark(vault, tmp_path, capsys):
    src = text_file(tmp_path, "Alex: we agree on option B\r\nSam: action for Friday\r\n")
    code, out = run(capsys, "paste-save", "--kind", "transcript", "--text-file", src, "--date", "2030-01-15",
                    "--start", "09:30", "--end", "10:00", "--title", "Weekly sync: API / events", "--event-id", "AAMk=1")
    saved = json.loads(out)
    assert code == 0 and saved["file"] == "Inbox/Transcripts/2030-01-15 09h30 Weekly sync API events (transcript).md"
    body = (vault / saved["file"]).read_text(encoding="utf-8")
    assert body.startswith("---\npasted: transcript\ndate: 2030-01-15\nstart: 09:30\nend: 10:00\n")
    assert 'meeting: "Weekly sync: API / events"' in body and "processed: false" in body
    assert "\r" not in body and body.endswith("action for Friday\n")

    items = json.loads(run(capsys, "pasted")[1])["pasted"]
    assert [i["file"] for i in items] == [saved["file"]] and items[0]["start"] == "09:30"

    assert run(capsys, "mark-pasted", saved["file"])[0] == 0
    assert json.loads(run(capsys, "pasted")[1])["pasted"] == []
    assert "processed: 20" in (vault / saved["file"]).read_text(encoding="utf-8")


def test_same_name_gets_a_suffix_and_french_label(vault, tmp_path, capsys, monkeypatch):
    cfg_file = tmp_path / "c.toml"
    cfg_file.write_text(f'language = "fr"\n[vault]\npath = "{vault.as_posix()}"\n', encoding="utf-8")
    monkeypatch.delenv("STYLO_NEO_VAULT")
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(cfg_file))
    src = text_file(tmp_path, "notes tapées")
    first = json.loads(run(capsys, "paste-save", "--kind", "notes", "--text-file", src, "--date", "2030-01-15")[1])
    second = json.loads(run(capsys, "paste-save", "--kind", "notes", "--text-file", src, "--date", "2030-01-15")[1])
    assert first["file"] == "Inbox/Transcriptions/2030-01-15 00h00 notes (notes).md"
    assert second["file"] == "Inbox/Transcriptions/2030-01-15 00h00 notes (notes) 2.md"


@pytest.mark.parametrize("args, message", [
    (["--kind", "minutes"], "--kind"),
    (["--kind", "notes", "--date", "15/01/2030"], "--date"),
    (["--kind", "notes", "--date", "2030-01-15", "--start", "9h30"], "HH:MM"),
    (["--kind", "notes", "--date", "2030-01-15", "--text-file", "missing.txt"], "text file not found"),
])
def test_save_refusals(vault, capsys, args, message):
    with pytest.raises(SystemExit, match=message):
        run(capsys, "paste-save", *args)


def test_empty_text_refused(vault, tmp_path, capsys):
    with pytest.raises(SystemExit, match="empty"):
        run(capsys, "paste-save", "--kind", "notes", "--text-file", text_file(tmp_path, "  \n"), "--date", "2030-01-15")


def test_unknown_option_refused(vault, tmp_path, capsys):
    code, _ = run(capsys, "paste-save", "--kind", "notes", "--output", "x")
    assert code == 2


def test_mark_pasted_only_in_transcripts_folder(vault, tmp_path, capsys):
    (vault / "Journal").mkdir()
    (vault / "Journal" / "2030-01-15.md").write_text("---\npasted: notes\nprocessed: false\n---\nx\n", encoding="utf-8")
    for rel in ("Journal/2030-01-15.md", "../x.md", "Inbox/Transcripts/none.md"):
        with pytest.raises(SystemExit):
            run(capsys, "mark-pasted", rel)
