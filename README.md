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
  and **Ncode paper** (NeoLAB notebooks, Moleskine Smart…, or printed yourself, see
  [Paper and printing](#paper-and-printing)): ordinary paper is not captured.
- To build the pen tool: the .NET 8 SDK (a per-user install without admin rights works, see below) and Git.
- For the conversion: Python 3.11+ with Pillow (`pip install pillow`), PowerShell 7 (`pwsh`) for the shortcut,
  Claude Code, and Obsidian.

## Paper and printing
The pen only reads paper carrying the **Ncode** dot pattern. Two options:

- **Ready-made notebooks** with the Ncode mark (NeoLAB, Moleskine Smart, Lamy Ncode): the pattern is printed by the
  maker, recognition is the most reliable.
- **Print your own** from NeoLAB's free PDFs: **[Ncode PDF printables](https://neolab.net/en/customer/ncode-pdf)** — basic paper (Plain, Lined, Grid,
  Dot, Landscape), templates (Cornell, Check List, Meeting Minutes, Log Sheet, A5…), storyboards, 50 pages per PDF.

NeoLAB's printing advice (from that page): print with **Adobe PDF Reader** on a **colour laser printer** (CMYK
toners) with a **PCL or PostScript driver**; on a grayscale laser, use the **Plain** layout; **test-print a few pages**
and check that the pen reads them before printing the whole file — some printers cannot print Ncode.

What we observed with these files (checked in November 2026, not stated by NeoLAB):
- **Plain is US Letter, not A4**: it is listed under "Basic Paper (A4)", but its pages are 21.6 × 27.9 cm and the
  dot layer (an image at 600 dpi) is even a little wider than the page. On A4 paper, print at **actual size (100 %)**:
  you lose about 6 mm on the right. Avoid "fit to page", which shrinks the dot pattern by about 3 %.
- **Never print in "economy" or draft mode**, and keep the printer's full resolution (600 dpi or more): the dots
  must stay sharp.
- **Printing the same PDF twice gives the same pages**: the pattern is identical (byte-identical files), so page A3
  of the second print has the same address as page A3 of the first, and the pen merges what you write on both
  sheets. Print each PDF once, or keep track of the pages already used.
- Even a correct print is not perfect: on one printed notebook, about 5 % of the strokes contained a misread point
  (a jump of more than 12 mm). The converter is told to mark doubtful words `[?]` rather than guess.

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
check and renew the calendar session (`agenda.session_check`, `agenda.login`). `agenda.list_command` gives the
window the meetings of a date (for the Paste tab). Without a calendar, notes are still written, just not attached
to meetings.

## Use
1. Pen on (blue light), Bluetooth of your phone off (the Neo app would keep the pen connected or empty it).
2. Double-click **Pen notes**: a window opens. Click **Sync + conversion** (all notebooks, or pick one): the pen
   syncs, then Claude Code converts the new pages; progress is shown live, **Stop** interrupts. Tick **Erase from the
   pen after the sync** to empty the pen of the notebooks fully received (only once saved on the PC): next syncs get faster. The pen password is
   never typed in the window: if it is not saved yet, a console opens for it (it can then be stored in Windows
   Credential Manager) and the conversion goes on in the window.
3. Read the notes in Obsidian. Doubts are in a **"To decide"** box at the top of each note: fix the text, or
   answer in the doubt's line ("→ yes", "→ it's DLQ").
4. **Integrate my corrections**: doubts settled, glossary and tags updated. **Convert without sync** converts what
   is already downloaded; the last two buttons open today's note and the conversion log in Obsidian.
5. **Paste notes or a transcript** tab: notes typed elsewhere (chat, email, another app) or a meeting transcript.
   Pick the date and the meeting (list read through `agenda.list_command`, or a title and a start time), paste, then
   **File it in Obsidian**. The text is kept in the transcripts folder of the vault, then Claude Code files it: pasted
   notes complete the pen note of that meeting (a "typed notes" section, never reworded) or become a meeting note;
   a transcript enriches the pen note (decisions and actions said but not written) or becomes a meeting note
   without handwriting.

Interactively, open the repository in Claude Code and say "convert my pen notes" (`/pen-notes`).

Paper signs the converter understands: `M: title` at the top of a page = a meeting; `SL: title` above a grid =
a slide mock-up; `!` in the margin = important; `?` = open question; boxed text = decision; circled word = tag;
☐ or `→ Name` = task.

## The pen tool alone
| Command | What it does |
|---|---|
| `stylo-neo sync [--mac AA:BB:…] [--notebook 3-27-738] [--erase \| --erase-received] [--no-prompt]` | downloads all notebooks (or one) and prints a per-notebook report; exit code 3 if a notebook did not arrive in full. Erasing always comes last, once the strokes are saved: `--erase` only notebooks whose end the pen confirmed, `--erase-received` also those whose strokes all arrived without the end marker (it was once seen missing, on a large notebook); an incomplete notebook is never erased. `--no-prompt`: exit code 4 instead of asking for a password that is not saved |
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
- **Erasing**: the SDK erases by default after download; this tool never does unless asked (`--erase`,
  `--erase-received`, or the window's box), and then only after the strokes are saved to disk, and never an
  incomplete notebook. A V1-protocol pen always erases: the tool refuses without
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
