"""Tests of the move from per-source folders to a single notes folder (pen_tool.py migrate-folders). Fictitious content."""
from __future__ import annotations

import json

import pytest

import pen_tool

PEN = ('---\ndate: 2030-01-15\nnotebook: Notebook 551\npen_pages: ["3-27-551/p009", "3-27-551/p010"]\n'
       'tags: [pen, type/meeting]\n---\n# Weekly sync\n\nLine written with the pen\n')
TRANSCRIPT = ("---\ndate: 2030-01-16\nsource: transcript\ntranscript: \"2030-01-16 sync.vtt\"\n"
              "tags: [pen, type/no-handwriting]\n---\n# Supplier call\n\nSummary\n")
PASTED_ON_PEN = ('---\ndate: 2030-01-17\npen_pages: ["3-27-738/p041"]\npasted: "x (notes).md"\n'
                 'tags: [pen]\n---\n# Design review\n')


@pytest.fixture
def vault(tmp_path, monkeypatch):
    v, refs = tmp_path / "vault", tmp_path / "refs"
    for base in (v, refs):
        (base / "Notebooks" / "Notebook 551").mkdir(parents=True)
        (base / "Meetings").mkdir()
    (v / "Notebooks" / "Notebook 551" / "2030-01-15 09h00 Weekly sync.md").write_text(PEN, encoding="utf-8")
    (refs / "Notebooks" / "Notebook 551" / "2030-01-15 09h00 Weekly sync.md").write_text(PEN, encoding="utf-8")
    (v / "Meetings" / "2030-01-16 14h00 Supplier call.md").write_text(TRANSCRIPT, encoding="utf-8")
    (v / "_pen").mkdir()
    (v / "_pen" / "Tags.md").write_text("| Family | Use | Tags |\n|---|---|---|\n| `type/` | kind | `meeting` |\n"
                                        "| `status/` | follow-up | `to-review` |\n\nPeople are never tags.\n", encoding="utf-8")
    monkeypatch.setenv("STYLO_NEO_VAULT", str(v))
    monkeypatch.setenv("STYLO_NEO_REFERENCES", str(refs))
    monkeypatch.setattr(pen_tool, "CONF", None)
    return v, refs


def run(capsys, *args):
    code = pen_tool.main(list(args))
    return code, capsys.readouterr().out


def test_source_tags_from_frontmatter():
    assert pen_tool.note_sources(PEN, "fr") == ["source/cahier-551"]
    assert pen_tool.note_sources(TRANSCRIPT, "en") == ["source/transcript"]
    assert pen_tool.note_sources(PASTED_ON_PEN, "fr") == ["source/cahier-738", "source/notes-tapees"]
    legacy = PEN.replace("pen_pages", "stylo_pages")
    assert pen_tool.note_sources(legacy, "en") == ["source/notebook-551"]


def test_add_tags_keeps_everything_else():
    out = pen_tool.add_tags(PEN, ["source/notebook-551", "pen"])
    assert "tags: [pen, type/meeting, source/notebook-551]\n" in out
    assert out.replace("tags: [pen, type/meeting, source/notebook-551]", "tags: [pen, type/meeting]") == PEN
    crlf = PEN.replace("\n", "\r\n")
    assert pen_tool.add_tags(crlf, ["source/x"]).count("\r\n") == crlf.count("\r\n")
    assert pen_tool.add_tags("no frontmatter", ["a"]) == "no frontmatter"
    assert "tags: [a]\n---" in pen_tool.add_tags("---\ndate: 2030-01-01\n---\nbody\n", ["a"])


def test_dry_run_changes_nothing(vault, capsys):
    v, _ = vault
    code, out = run(capsys, "migrate-folders", "--dry-run")
    plan = json.loads(out)
    assert code == 0 and plan["dry_run"] is True
    assert {m["to"] for m in plan["moves"]} == {"Notes/2030-01-15 09h00 Weekly sync.md", "Notes/2030-01-16 14h00 Supplier call.md"}
    assert (v / "Notebooks" / "Notebook 551" / "2030-01-15 09h00 Weekly sync.md").is_file()
    assert not (v / "Notes").exists()


def test_migration_moves_tags_and_keeps_corrections_visible(vault, capsys):
    v, refs = vault
    note = v / "Notebooks" / "Notebook 551" / "2030-01-15 09h00 Weekly sync.md"
    note.write_text(PEN.replace("Line written", "Line WRITTEN"), encoding="utf-8")   # a user correction
    code, out = run(capsys, "migrate-folders")
    assert code == 0 and json.loads(out)["tags_row_added"] is True
    moved = v / "Notes" / "2030-01-15 09h00 Weekly sync.md"
    assert "tags: [pen, type/meeting, source/notebook-551]" in moved.read_text(encoding="utf-8")
    assert "Line WRITTEN" in moved.read_text(encoding="utf-8")
    assert (refs / "Notes" / "2030-01-15 09h00 Weekly sync.md").is_file()
    assert not (v / "Notebooks").exists() and not (v / "Meetings").exists() and not (refs / "Notebooks").exists()
    # the correction is still reported, and nothing else
    states = {n["note"]: n for n in json.loads(run(capsys, "changed")[1])["notes"]}
    assert set(states) == {"Notes/2030-01-15 09h00 Weekly sync.md", "Notes/2030-01-16 14h00 Supplier call.md"}
    assert states["Notes/2030-01-15 09h00 Weekly sync.md"]["state"] == "modified"
    assert "+Line WRITTEN" in states["Notes/2030-01-15 09h00 Weekly sync.md"]["diff"]
    assert states["Notes/2030-01-16 14h00 Supplier call.md"]["state"] == "no_reference"
    tags = (v / "_pen" / "Tags.md").read_text(encoding="utf-8")
    assert "| `source/` | where the note comes from (a note may have several) | `notebook-551`, `transcript` |\n| `status/`" in tags
    # a second run has nothing left to do
    assert json.loads(run(capsys, "migrate-folders")[1])["moves"] == []


def test_name_clash_gets_a_suffix(vault, capsys):
    v, _ = vault
    (v / "Notes").mkdir()
    (v / "Notes" / "2030-01-16 14h00 Supplier call.md").write_text("---\ntags: []\n---\nalready here\n", encoding="utf-8")
    plan = json.loads(run(capsys, "migrate-folders", "--dry-run")[1])
    assert "Notes/2030-01-16 14h00 Supplier call (2).md" in {m["to"] for m in plan["moves"]}


def test_rerun_after_interruption_adds_the_vocabulary_row_and_reports_locked_folders(vault, capsys, monkeypatch):
    v, _ = vault
    (v / "Notes").mkdir()
    (v / "Notes" / "2030-01-20 10h00 Done.md").write_text("---\ntags: [pen, source/notebook-551]\n---\nx\n", encoding="utf-8")
    for p in list((v / "Notebooks").rglob("*.md")) + list((v / "Meetings").rglob("*.md")):
        p.unlink()   # as if the notes had already been moved by an interrupted run
    real_rmdir = type(v).rmdir

    def locked(self):
        if self.name == "Notebook 551" and str(v) in str(self):
            raise PermissionError("in use")
        real_rmdir(self)
    monkeypatch.setattr(type(v), "rmdir", locked)
    result = json.loads(run(capsys, "migrate-folders")[1])
    assert result["moves"] == [] and result["tags_row_added"] is True
    assert any(k.endswith("Notebook 551") for k in result["empty_folders_kept"])
    assert "`notebook-551`" in (v / "_pen" / "Tags.md").read_text(encoding="utf-8")
    assert not (v / "Meetings").exists()
