"""Configuration shared by the pen-notes helper scripts.

The configuration file is TOML (see config.example.toml at the repository root). It is looked up, in order:

1. the file named by the STYLO_NEO_CONFIG environment variable;
2. <repository root>/config.toml;
3. %APPDATA%\\stylo-neo-notes\\config.toml.

The environment variables STYLO_NEO_VAULT, STYLO_NEO_DATA and STYLO_NEO_REFERENCES win over the file.
A missing configuration file is fine as long as the vault path comes from the environment.
"""
from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from datetime import datetime, timezone as dt_timezone, tzinfo
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[2]
APP = "stylo-neo-notes"

LANGUAGES = ("en", "fr")
DEFAULT_FOLDERS = {
    "en": {"notebooks_dir": "Notebooks", "journal_dir": "Journal", "meetings_dir": "Meetings",
           "attachments_dir": "Attachments/pen", "system_dir": "_pen", "transcripts_dir": "Inbox/Transcripts",
           "log_file": "Conversion log.md"},
    "fr": {"notebooks_dir": "Carnets", "journal_dir": "Journal", "meetings_dir": "Réunions",
           "attachments_dir": "Pièces jointes/stylo", "system_dir": "_stylo",
           "transcripts_dir": "Inbox/Transcriptions", "log_file": "Journal des conversions.md"},
}


class ConfigError(Exception):
    """The configuration is missing or invalid."""


def local_app_dir() -> Path:
    """Per-user local (non-roaming, non-synced) application folder."""
    base = os.environ.get("LOCALAPPDATA")
    return (Path(base) if base else Path.home() / ".local" / "share") / APP


def roaming_app_dir() -> Path:
    base = os.environ.get("APPDATA")
    return (Path(base) if base else Path.home() / ".config") / APP


def candidate_files() -> list[Path]:
    """Configuration files in lookup order (the environment variable first)."""
    files = []
    if os.environ.get("STYLO_NEO_CONFIG"):
        files.append(Path(os.environ["STYLO_NEO_CONFIG"]).expanduser())
    files.append(REPO_ROOT / "config.toml")
    files.append(roaming_app_dir() / "config.toml")
    return files


def find_config_file() -> Path | None:
    explicit = os.environ.get("STYLO_NEO_CONFIG")
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_file():
            raise ConfigError(f"STYLO_NEO_CONFIG points to a missing file: {path}")
        return path
    return next((p for p in candidate_files() if p.is_file()), None)


def _path(value: str, base: Path) -> Path:
    p = Path(value).expanduser()
    return (p if p.is_absolute() else base / p).resolve()


@dataclass(frozen=True)
class Config:
    language: str
    timezone: str
    vault: Path | None
    data_dir: Path | None
    exe: Path
    references: Path
    notebooks_dir: str
    journal_dir: str
    meetings_dir: str
    attachments_dir: str
    system_dir: str
    transcripts_dir: str
    log_file: str
    config_file: Path | None = None
    agenda: dict = field(default_factory=dict)

    @property
    def tracked_dirs(self) -> tuple[str, str, str]:
        """Vault folders holding the notes written by the converter."""
        return self.notebooks_dir, self.journal_dir, self.meetings_dir

    def in_vault(self, rel: str) -> Path | None:
        """Absolute path of a vault folder or file (None when no vault is configured)."""
        return self.vault / rel if self.vault is not None else None

    @property
    def rotated_dir(self) -> Path:
        return local_app_dir() / "rotated"

    def tz(self) -> tzinfo | None:
        """The configured time zone, or None for the computer's local time zone."""
        return ZoneInfo(self.timezone) if self.timezone else None

    def require_vault(self) -> Path:
        if self.vault is None:
            raise ConfigError("no vault configured: set [vault] path in config.toml or STYLO_NEO_VAULT")
        return self.vault

    def require_data_dir(self) -> Path:
        if self.data_dir is None:
            raise ConfigError("no pen data folder configured: set [pen] data_dir in config.toml or STYLO_NEO_DATA")
        return self.data_dir

    def as_dict(self) -> dict:
        s = lambda p: str(p) if p is not None else None  # noqa: E731
        return {
            "config_file": s(self.config_file), "language": self.language, "timezone": self.timezone,
            "vault": s(self.vault), "notebooks_dir": self.notebooks_dir, "journal_dir": self.journal_dir,
            "meetings_dir": self.meetings_dir, "attachments_dir": self.attachments_dir,
            "system_dir": self.system_dir, "transcripts_dir": self.transcripts_dir, "log_file": self.log_file,
            "paths": {k: s(self.in_vault(getattr(self, k))) for k in (
                "notebooks_dir", "journal_dir", "meetings_dir", "attachments_dir", "system_dir",
                "transcripts_dir")} | {"log_file": s(self.in_vault(f"{self.system_dir}/{self.log_file}"))},
            "data_dir": s(self.data_dir), "exe": s(self.exe), "references": s(self.references),
            "rotated_dir": s(self.rotated_dir), "agenda": self.agenda,
        }


def load(require_vault: bool = True) -> Config:
    """Resolve the configuration: environment > file > defaults."""
    file = find_config_file()
    data: dict = {}
    if file is not None:
        try:
            data = tomllib.loads(file.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError) as error:
            raise ConfigError(f"cannot read {file}: {error}") from error
    base = file.parent if file is not None else Path.cwd()
    vault_s, pen_s, refs_s = data.get("vault", {}), data.get("pen", {}), data.get("references", {})

    language = (data.get("language") or "en").strip().lower()
    if language not in LANGUAGES:
        raise ConfigError(f"language must be one of {', '.join(LANGUAGES)}, not {language!r}")
    timezone = (data.get("timezone") or "").strip()
    if timezone:
        try:
            ZoneInfo(timezone)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ConfigError(f"unknown time zone: {timezone!r}") from error

    def pick(env: str, value: str | None) -> Path | None:
        if os.environ.get(env):
            return _path(os.environ[env], Path.cwd())
        return _path(value, base) if value else None

    vault = pick("STYLO_NEO_VAULT", vault_s.get("path"))
    if vault is None and require_vault:
        raise ConfigError("no vault configured: set [vault] path in config.toml or STYLO_NEO_VAULT"
                          + ("" if file else " (no configuration file found)"))
    data_dir = pick("STYLO_NEO_DATA", pen_s.get("data_dir"))
    references = pick("STYLO_NEO_REFERENCES", refs_s.get("dir")) or (local_app_dir() / "references")
    exe = _path(pen_s["exe"], base) if pen_s.get("exe") else REPO_ROOT / "pen" / "dist" / "stylo-neo.exe"

    folders = {}
    for key, default in DEFAULT_FOLDERS[language].items():
        value = (vault_s.get(key) or "").strip().replace("\\", "/").strip("/")
        if value and (Path(value).is_absolute() or ".." in Path(value).parts):
            raise ConfigError(f"[vault] {key} must be a relative path inside the vault: {value!r}")
        folders[key] = value or default

    return Config(language=language, timezone=timezone, vault=vault, data_dir=data_dir, exe=exe,
                  references=references, config_file=file, agenda=dict(data.get("agenda", {})), **folders)


def local_time(ms: float, tz: tzinfo | None) -> datetime:
    """A pen timestamp (Unix milliseconds) as an aware datetime in `tz` (None = the computer's zone)."""
    moment = datetime.fromtimestamp(ms / 1000, dt_timezone.utc)
    return moment.astimezone(tz) if tz is not None else moment.astimezone()
