# Lessons — pen-notes

Lessons learned while converting real pages. Apply them; add new ones (generic only: no names of people,
companies or partners — those belong in the vault's glossary).

- Diagrams in Mermaid (no Excalidraw), notes split by topic, filed by notebook. The conversion runs inside a
  Claude Code session: no API key needed.
- The folded manuscript at the top of the note plus Mermaid below was validated as the default format. An
  uncertain proper noun marked `[?]` turned out to be right: keep that caution.
- A sketch without text → the SVG shown large, without a folded callout, plus one sentence of description in
  italics.
- An acronym confirmed by the user stays as written in the text; add the expanded name as a tag for search.
  A title word misread as a similar-looking word: the `[?]` was justified — cross doubtful words with the
  calendar event's subject.
- A page may carry **two meetings**: separate them by the time of the strokes (pauses > 5 min). The context
  found in the calendar goes into a context callout signed by the converter, never into the transcribed text.
  An underlined word is often the name of the meeting's partner: cross doubtful words with the invitation.
- Page written **upside down**: rotate the PNG by 180° to read it (`pen_tool.py png <key> --rotate`); in the
  vault, the SVG is copied with `transform="rotate(180 cx cy)"` on its `<g>` (`copy-svg --rotate`) and the
  manuscript callout title says so.
- A grid-like architecture diagram rendered as `flowchart LR` was rejected ("everything flattened"). Redone as
  `block-beta` keeping the layout **and the gaps** of the drawing (one empty row per box height), with colours by
  object type: judged right in Obsidian.
- Meeting recordings: names like `YYYYMMDD_HHMMSSUTC` carry the time zone; `YYYYMMDD_HHMMSS` does not (confirm
  the time). Prefer `.vtt` transcripts; an unknown format is refused by `transcript.py`.
- Meetings are identified through the calendar (agenda tools), not only through invitation emails.
- A grid drawn in columns (titles on top, blocks in rows) may be the **mock-up of a slide**, not a data table:
  title it "Slide mock-up" and flag it when in doubt.
- The user prefers to correct in Obsidian rather than answer a numbered list of questions in the chat: doubts
  go into the note, and corrections are integrated afterwards (choice 2 of the shortcut).
