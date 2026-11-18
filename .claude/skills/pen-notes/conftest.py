"""Shared test fixtures: every test runs against temporary folders, never the user's own."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import config as cfg  # noqa: E402

ENV = ("STYLO_NEO_CONFIG", "STYLO_NEO_VAULT", "STYLO_NEO_DATA", "STYLO_NEO_REFERENCES")


@pytest.fixture(autouse=True)
def isolated(tmp_path, monkeypatch):
    """No configuration leaks in from the computer: env cleared, app folders and repo root in tmp."""
    for name in ENV:
        monkeypatch.delenv(name, raising=False)
    monkeypatch.setenv("APPDATA", str(tmp_path / "appdata"))
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path / "localappdata"))
    monkeypatch.setattr(cfg, "REPO_ROOT", tmp_path / "repo")
    yield tmp_path
