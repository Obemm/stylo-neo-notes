"""Tests of config.py: lookup order, environment overrides, per-language defaults, errors."""
from pathlib import Path

import pytest

import config as cfg


def write(path: Path, text: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def test_missing_vault_is_a_clear_error():
    with pytest.raises(cfg.ConfigError, match="no vault configured"):
        cfg.load()


def test_no_file_but_env_vault(tmp_path, monkeypatch):
    monkeypatch.setenv("STYLO_NEO_VAULT", str(tmp_path / "v"))
    c = cfg.load()
    assert c.config_file is None
    assert c.vault == (tmp_path / "v").resolve()
    assert c.language == "en"
    assert c.tracked_dirs == ("Notebooks", "Journal", "Meetings")
    assert c.attachments_dir == "Attachments/pen"
    assert (c.system_dir, c.transcripts_dir, c.log_file) == ("_pen", "Inbox/Transcripts", "Conversion log.md")
    assert c.references == tmp_path / "localappdata" / "stylo-neo-notes" / "references"
    assert c.exe == tmp_path / "repo" / "pen" / "dist" / "stylo-neo.exe"
    assert c.timezone == "" and c.tz() is None
    assert c.data_dir is None


def test_french_defaults(tmp_path, monkeypatch):
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(write(tmp_path / "c.toml", 'language = "fr"\n[vault]\npath = "v"\n')))
    c = cfg.load()
    assert c.tracked_dirs == ("Carnets", "Journal", "Réunions")
    assert c.attachments_dir == "Pièces jointes/stylo"
    assert (c.system_dir, c.transcripts_dir, c.log_file) == (
        "_stylo", "Inbox/Transcriptions", "Journal des conversions.md")
    assert c.vault == (tmp_path / "v").resolve()  # relative to the configuration file


def test_explicit_folders_and_timezone(tmp_path, monkeypatch):
    toml = ('timezone = "Asia/Tokyo"\n[vault]\npath = "~/Vault"\nnotebooks_dir = "Books"\n'
            'attachments_dir = "Files\\\\ink"\n[pen]\ndata_dir = "d"\nexe = "bin/pen.exe"\n'
            '[references]\ndir = "refs"\n')
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(write(tmp_path / "c.toml", toml)))
    c = cfg.load()
    assert c.vault == (Path.home() / "Vault").resolve()
    assert c.notebooks_dir == "Books" and c.meetings_dir == "Meetings"
    assert c.attachments_dir == "Files/ink"
    assert c.data_dir == (tmp_path / "d").resolve()
    assert c.exe == (tmp_path / "bin" / "pen.exe").resolve()
    assert c.references == (tmp_path / "refs").resolve()
    assert str(c.tz()) == "Asia/Tokyo"


def test_env_wins_over_file(tmp_path, monkeypatch):
    toml = '[vault]\npath = "file-vault"\n[pen]\ndata_dir = "file-data"\n[references]\ndir = "file-refs"\n'
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(write(tmp_path / "c.toml", toml)))
    for name, value in (("VAULT", "env-vault"), ("DATA", "env-data"), ("REFERENCES", "env-refs")):
        monkeypatch.setenv(f"STYLO_NEO_{name}", str(tmp_path / value))
    c = cfg.load()
    assert (c.vault.name, c.data_dir.name, c.references.name) == ("env-vault", "env-data", "env-refs")


def test_lookup_order(tmp_path, monkeypatch):
    appdata = write(tmp_path / "appdata" / "stylo-neo-notes" / "config.toml", '[vault]\npath = "/appdata-vault"\n')
    assert cfg.load().config_file == appdata
    repo = write(tmp_path / "repo" / "config.toml", '[vault]\npath = "/repo-vault"\n')
    assert cfg.load().config_file == repo
    env = write(tmp_path / "env.toml", '[vault]\npath = "/env-vault"\n')
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(env))
    assert cfg.load().config_file == env


def test_explicit_missing_file_is_an_error(tmp_path, monkeypatch):
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(tmp_path / "nowhere.toml"))
    with pytest.raises(cfg.ConfigError, match="missing file"):
        cfg.load()


@pytest.mark.parametrize("toml,message", [
    ('language = "de"\n[vault]\npath = "v"\n', "language"),
    ('timezone = "Nowhere/City"\n[vault]\npath = "v"\n', "time zone"),
    ('[vault]\npath = "v"\njournal_dir = "../out"\n', "inside the vault"),
    ('[vault\npath = "v"\n', "cannot read"),
])
def test_invalid_values(tmp_path, monkeypatch, toml, message):
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(write(tmp_path / "c.toml", toml)))
    with pytest.raises(cfg.ConfigError, match=message):
        cfg.load()


def test_vault_not_required_for_timezone_only(tmp_path, monkeypatch):
    monkeypatch.setenv("STYLO_NEO_CONFIG", str(write(tmp_path / "c.toml", 'timezone = "UTC"\n')))
    assert str(cfg.load(require_vault=False).tz()) == "UTC"
