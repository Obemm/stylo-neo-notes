# stylo-neo-notes

*[Version française](README.fr.md)*

Your **Neo smartpen M1** handwriting, turned into **Obsidian notes** — without the NeoLAB app.

- `pen/` — **stylo-neo**, a small Windows console tool (.NET 8, official NeoLAB SDK) that downloads the pages
  stored in the pen over Bluetooth LE and saves them per notebook and page: raw strokes (JSON), vector (SVG) and
  image (PNG). It never erases the pen unless asked.
- `.claude/skills/pen-notes/` — a **Claude Code skill** that reads each page and writes Obsidian notes: faithful
  transcription (uncertain words marked `word[?]`), tasks, diagrams redrawn in Mermaid keeping their layout,
  sketches kept as SVG, one note per meeting or topic plus a daily note, meeting minutes matched to your
  calendar (optional), tags. When in doubt, it writes the doubt **in the note**; you correct in Obsidian, and it
  learns your corrections (glossary, tags) without ever rewriting your text.
- `scripts/` — a desktop window (`app.ps1`): sync + conversion, convert without sync, integrate my corrections,
  open today's note or the conversion log, with live progress; `run.ps1` is the same in a console, for automation.

> Today the conversion runs through [Claude Code](https://claude.com/claude-code). Choosing another LLM
> (Anthropic API, OpenAI-compatible APIs, local models through Ollama) is on the roadmap.

## Requirements
- Windows 10/11 with Bluetooth LE, a **Neo smartpen M1** (other Neo pens using the same SDK may work, untested)
  and **Ncode paper** (NeoLAB notebooks, Moleskine Smart…): ordinary paper is not captured.
- To build the pen tool: the .NET 8 SDK (a per-user install without admin rights works, see below) and Git.
- For the conversion: Python 3.11+ with Pillow (`pip install pillow`), PowerShell 7 (`pwsh`) for the shortcut,
  Claude Code, and Obsidian.

## Install
```powershell
git clone https://github.com/<you>/stylo-neo-notes
cd stylo-neo-notes
powershell -ExecutionPolicy Bypass -File pen/setup.ps1     # fetches the NeoLAB SDK at a pinned commit
powershell -ExecutionPolicy Bypass -File pen/publish.ps1   # builds pen/dist/stylo-neo.exe (self-contained)
copy config.example.toml config.toml                       # then edit vault.path and pen.data_dir
pwsh -File scripts/install-shortcut.ps1                    # optional: "Pen notes" on the desktop
```
No admin rights? Install the .NET 8 SDK in your profile with Microsoft's official script:
`dotnet-install.ps1 -Channel 8.0 -InstallDir "$env:LOCALAPPDATA\Microsoft\dotnet"`.
The self-contained exe (~90 MB) can also be built on another computer and copied.

## Configure
Everything is in `config.toml` (see [`config.example.toml`](config.example.toml)): vault path and folder names,
notes language (`en` or `fr`), time zone, pen data folder, references folder, calendar. It is looked up in
`STYLO_NEO_CONFIG`, then `config.toml` at the repository root, then `%APPDATA%\stylo-neo-notes\config.toml`;
`STYLO_NEO_VAULT`, `STYLO_NEO_DATA`, `STYLO_NEO_REFERENCES` override it.
`python .claude/skills/pen-notes/pen_tool.py config` shows the resolved values.

**Calendar (optional)**: with `agenda.source = "mcp"`, the converter matches the time of your strokes to your
meetings through read-only MCP tools you provide (`agenda.mcp_config`, `agenda.tools`), and the shortcut can
check and renew the calendar session (`agenda.session_check`, `agenda.login`). Without it, notes are still
written, just not attached to meetings.

## Use
1. Pen on (blue light), Bluetooth of your phone off (the Neo app would keep the pen connected or empty it).
2. Double-click **Pen notes**: a window opens. Click **Sync + conversion** (all notebooks, or pick one): the pen
   syncs, then Claude Code converts the new pages; progress is shown live, **Stop** interrupts. The pen password is
   never typed in the window: if it is not saved yet, a console opens for it (it can then be stored in Windows
   Credential Manager) and the conversion goes on in the window.
3. Read the notes in Obsidian. Doubts are in a **"To decide"** box at the top of each note: fix the text, or
   answer in the doubt's line ("→ yes", "→ it's DLQ").
4. **Integrate my corrections**: doubts settled, glossary and tags updated. **Convert without sync** converts what
   is already downloaded; the last two buttons open today's note and the conversion log in Obsidian.

Interactively, open the repository in Claude Code and say "convert my pen notes" (`/pen-notes`).

Paper signs the converter understands: `M: title` at the top of a page = a meeting; `SL: title` above a grid =
a slide mock-up; `!` in the margin = important; `?` = open question; boxed text = decision; circled word = tag;
☐ or `→ Name` = task.

## The pen tool alone
| Command | What it does |
|---|---|
| `stylo-neo sync [--mac AA:BB:…] [--notebook 3-27-738] [--erase] [--no-prompt]` | downloads all notebooks (or one) and prints a per-notebook report; exit code 3 if a notebook did not arrive in full. `--erase` only erases notebooks whose end the pen confirmed. `--no-prompt`: exit code 4 instead of asking for a password that is not saved |
| `stylo-neo pending [--json]` | pages new or modified, not converted yet |
| `stylo-neo mark-done <key>` | the note of this page is up to date (e.g. `3-27-738/p012`) |
| `stylo-neo listen [--seconds 45]` | connection diagnostic |
| `stylo-neo forget-password` | removes the pen password from Windows Credential Manager |
| `stylo-neo render` | redraws SVG and PNG from the JSON |
| `stylo-neo log` | every known page |
| `stylo-neo migrate` | rewrites data saved by older versions in the current format |

Common options: `--data-dir <path>` (else `STYLO_NEO_DATA`, else `Documents\StyloNeo`), `--lang en|fr` (else `STYLO_NEO_LANG`, else `en`).
Data layout: `journal.json` and `pages/<section>-<owner>-<notebook>/pNNN.json|svg|png`.

## Safety
- **Erasing**: the SDK erases by default after download; this tool never does unless `--erase`, and then only
  notebooks whose transfer end the pen confirmed. A V1-protocol pen always erases: the tool refuses without
  `--erase`.
- **Password**: too many wrong attempts reset the pen; the tool stops while 3 attempts remain. The password is
  never written to disk or logs.
- **Your text**: the converter keeps a copy of what it wrote (outside the vault) and works from the diff with
  your version; it never rewrites what you corrected.
- **Automatic mode**: the shortcut runs `claude -p` locked down: file tools limited to the vault, the pen data
  and the skill; the repository is denied; the only shell command is `pen_tool.py`.
- Pen pages and notes never go into this repository.

## Tests
```powershell
dotnet test pen/tests/StyloNeo.Tests
cd .claude/skills/pen-notes; python -m pytest -q
```

## Pitfalls
See [`pen/lessons.md`](pen/lessons.md) (pen, SDK, Bluetooth) and
[`.claude/skills/pen-notes/lessons.md`](.claude/skills/pen-notes/lessons.md) (conversion).

## License
[GPL-3.0](LICENSE). The pen tool links the [NeoLAB Windows SDK 2.0](https://github.com/NeoSmartpen/Windows-SDK2.0),
itself GPL-3.0. Not affiliated with NeoLAB, Obsidian or Anthropic.
