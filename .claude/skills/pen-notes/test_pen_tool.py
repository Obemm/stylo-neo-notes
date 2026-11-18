"""Tests of pen_tool.py: reference copies, path safety, page commands, vault migration. Fictitious content."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import pen_tool

NOTE = ("---\ndate: 2030-01-15\ntags: [pen]\n---\n# Fictitious meeting\n\n"
        "> [!question] To decide (Claude)\n> - **XQZ[?]**: maybe XYZ.\n\n"
        "Line one about topic A\nLine two about topic B\nLine three XQZ[?] for the solution\n")
LEGACY_NOTE = ("---\ndate: 2030-01-15\nstylo_pages: [3-27-551/p007]\nstylo_empreintes: [abc123]\n"
               "stylo_seances:\n  - 2030-01-15 09:00-09:42\n---\n# Fictitious page\n\n"
               "stylo_pages: this line is in the body and must stay\n")
T0 = 1_894_000_000_000  # a fictitious moment in 2030, Unix milliseconds
SVG = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 200"><g stroke="#000"><path d="M0 0"/></g></svg>'


@pytest.fixture
def env(tmp_path, monkeypatch):
    vault, refs, data = tmp_path / "vault", tmp_path / "refs", tmp_path / "data"
    (vault / "Notebooks" / "Notebook 1").mkdir(parents=True)
    (vault / "Journal").mkdir()
    monkeypatch.setenv("STYLO_NEO_VAULT", str(vault))
    monkeypatch.setenv("STYLO_NEO_REFERENCES", str(refs))
    monkeypatch.setenv("STYLO_NEO_DATA", str(data))
    monkeypatch.setattr(pen_tool, "CONF", None)
    return vault, refs, data


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run(capsys, *args: str) -> tuple[int, str]:
    code = pen_tool.main(list(args))
    return code, capsys.readouterr().out


def states(capsys) -> dict[str, dict]:
    code, out = run(capsys, "changed")
    assert code == 0
    return {n["note"]: n for n in json.loads(out)["notes"]}


A = "Notebooks/Notebook 1/a.md"


def test_unchanged_note_not_listed(env, capsys):
    write(env[0] / A, NOTE)
    run(capsys, "reference", A)
    assert states(capsys) == {}


def test_correction_shown_as_diff(env, capsys):
    write(env[0] / A, NOTE)
    run(capsys, "reference", A)
    write(env[0] / A, NOTE.replace("XQZ[?] for", "XYZ for"))
    e = states(capsys)[A]
    assert e["state"] == "modified"
    assert "-Line three XQZ[?] for the solution" in e["diff"]
    assert "+Line three XYZ for the solution" in e["diff"]


def test_windows_line_endings_ignored(env, capsys):
    write(env[0] / A, NOTE)
    run(capsys, "reference", A)
    (env[0] / A).write_bytes(NOTE.replace("\n", "\r\n").encode("utf-8"))
    assert states(capsys) == {}


def test_renamed_note_detected(env, capsys):
    write(env[0] / A, NOTE)
    run(capsys, "reference", A)
    (env[0] / A).rename(env[0] / "Notebooks/Notebook 1/b.md")
    e = states(capsys)["Notebooks/Notebook 1/b.md"]
    assert (e["state"], e["old"], e["diff"]) == ("renamed", A, "")


def test_deleted_and_no_reference(env, capsys):
    write(env[0] / A, NOTE)
    run(capsys, "reference", A)
    (env[0] / A).unlink()
    write(env[0] / "Journal/2030-01-15.md", "# 15 January\n\nSomething else, unrelated.\n")
    e = states(capsys)
    assert e[A]["state"] == "deleted"
    assert e["Journal/2030-01-15.md"]["state"] == "no_reference"
    assert run(capsys, "forget", A)[0] == 0
    assert A not in states(capsys)


def test_forget_refuses_an_existing_note(env, capsys):
    write(env[0] / A, NOTE)
    with pytest.raises(SystemExit):
        run(capsys, "forget", A)


@pytest.mark.parametrize("rel", ["_pen/Glossary.md", "../a.md", "Notebooks/../../x.md", "Notebooks/a.txt",
                                 "Notebooks", "/Notebooks/a.md", "C:/Notebooks/a.md", "Inbox/Transcripts/t.md"])
def test_paths_outside_notes_refused(env, capsys, rel):
    with pytest.raises(SystemExit, match="note refused"):
        run(capsys, "reference", rel)


def test_absolute_vault_path_refused(env, capsys):
    write(env[0] / A, NOTE)
    with pytest.raises(SystemExit, match="note refused"):
        run(capsys, "reference", str(env[0] / A))


def test_french_folders_tracked(env, capsys, tmp_path, monkeypatch):
    conf = tmp_path / "c.toml"
    conf.write_text('language = "fr"\n', encoding="utf-8")
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(conf))
    write(env[0] / "Réunions/r.md", NOTE)
    assert run(capsys, "reference", "Réunions/r.md")[0] == 0
    with pytest.raises(SystemExit):
        pen_tool.CONF = None
        run(capsys, "reference", A)


@pytest.mark.parametrize("args", [["sync"], ["pending", "x"], ["mark-done"], ["png", "a", "b"], ["changed", "x"],
                                  ["config", "x"], ["migrate-vault", "--rotate"]])
def test_unknown_or_malformed_command_refused(env, capsys, args):
    assert pen_tool.main(args) == 2
    assert "command refused" in capsys.readouterr().err


@pytest.mark.parametrize("key", ["3-27-551/p7", "../x/p001", "3-27-551/p007/..", "a-b-c/p001"])
def test_invalid_keys_refused(env, capsys, key):
    with pytest.raises(SystemExit, match="invalid key"):
        run(capsys, "png", key)


def test_config_output(env, capsys):
    code, out = run(capsys, "config")
    c = json.loads(out)
    assert code == 0
    assert c["vault"] == str(env[0].resolve())
    assert c["references"] == str(env[1].resolve())
    assert c["paths"]["log_file"] == str(env[0].resolve() / "_pen" / "Conversion log.md")
    assert Path(c["paths"]["transcripts_dir"]).is_absolute()


def test_missing_vault_is_reported(capsys, monkeypatch):
    monkeypatch.setattr(pen_tool, "CONF", None)
    with pytest.raises(SystemExit, match="no vault configured"):
        run(capsys, "changed")


def test_page_commands(env, capsys, tmp_path):
    pages = env[2] / "pages" / "3-27-551"
    write(pages / "p007.svg", SVG)
    write(pages / "p007.json", json.dumps({"section": 3, "proprietaire": 27, "carnet": 551, "page": 7,
                                           "traits": [{"debut": T0, "fin": T0 + 1000, "points": [[1, 5, 0.5, T0]]}]}))
    from PIL import Image
    Image.new("RGB", (4, 2), "white").save(pages / "p007.png")

    code, out = run(capsys, "sessions", "3-27-551/p007")
    assert code == 0 and json.loads(out)["3-27-551/p007"][0]["strokes"] == 1
    assert Path(run(capsys, "png", "3-27-551/p007")[1].strip()) == pages / "p007.png"
    rotated = Path(run(capsys, "png", "3-27-551/p007", "--rotate")[1].strip())
    assert rotated.is_file() and rotated.is_relative_to(tmp_path / "localappdata")
    svg = Path(run(capsys, "copy-svg", "3-27-551/p007", "--rotate")[1].strip())
    assert svg == env[0] / "Attachments" / "pen" / "3-27-551-p007.svg"
    assert 'transform="rotate(180 50.000 100.000)"' in svg.read_text(encoding="utf-8")
    with pytest.raises(SystemExit, match="page not found"):
        run(capsys, "png", "3-27-551/p008")


def test_pen_commands_need_the_executable(env, capsys, tmp_path):
    write(env[2] / "pages" / "3-27-551" / "p007.json", "{}")
    with pytest.raises(SystemExit, match="pen executable not found"):
        run(capsys, "pending")
    with pytest.raises(SystemExit, match="pen executable not found"):
        run(capsys, "mark-done", "3-27-551/p007")


def test_migrate_text_only_touches_frontmatter():
    out = pen_tool.migrate_text(LEGACY_NOTE)
    assert "pen_pages: [3-27-551/p007]\npen_hashes: [abc123]\npen_sessions:\n" in out
    assert out.endswith("stylo_pages: this line is in the body and must stay\n")
    assert pen_tool.migrate_text("# no frontmatter\nstylo_pages: x\n") == "# no frontmatter\nstylo_pages: x\n"
    crlf = LEGACY_NOTE.replace("\n", "\r\n")
    assert pen_tool.migrate_text(crlf) == out.replace("\n", "\r\n")


def test_migrate_vault(env, capsys):
    vault, refs, _ = env
    for base in (vault, refs):
        write(base / A, LEGACY_NOTE)
    write(vault / "Journal/new.md", NOTE)
    write(vault / "_pen/Glossary.md", LEGACY_NOTE)  # not a tracked folder: left alone

    code, out = run(capsys, "migrate-vault", "--dry-run")
    dry = json.loads(out)
    assert code == 0 and dry["dry_run"] is True
    assert sorted(dry["changed"]) == sorted([str(vault.resolve() / A), str(refs.resolve() / A)])
    assert (vault / A).read_text(encoding="utf-8") == LEGACY_NOTE

    real = json.loads(run(capsys, "migrate-vault")[1])
    assert real["changed"] == dry["changed"]
    for base in (vault, refs):
        assert "pen_pages:" in (base / A).read_text(encoding="utf-8")
    assert (vault / "_pen/Glossary.md").read_text(encoding="utf-8") == LEGACY_NOTE
    assert A not in states(capsys)  # note and reference migrated alike: no correction appears

    assert json.loads(run(capsys, "migrate-vault")[1])["changed"] == []  # idempotent
