# Lessons — stylo-neo

- 2026-11-07: the NeoLAB SDK erases the pen's pages by default (`RequestOfflineData(..., deleteOnFinished = true)`),
  and the official demo relies on that default. In protocol V1, `OfflineWorker.onFinishDownload` always
  erases. Always pass `deleteOnFinished` explicitly.
- 2026-11-07: `PasswordRequested` gives `RetryCount` and `ResetCount`; at `RetryCount >= ResetCount` the pen
  erases its data. Never loop on password input.
- 2026-11-07: the M1 drops the connection if it waits too long for its password ("The pen disconnected"):
  type the password as soon as prompted. No attempt is consumed in that case.
- 2026-11-07: type the password only when `Pen password:` is displayed. A restarted terminal tab gives back a
  PowerShell prompt: a code typed there ends up in the PSReadLine history
  (`%APPDATA%\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`), which must then be cleaned.
- 2026-11-07: a stroke written while the pen is connected (phone, PC) is sent live and not kept in memory;
  only pages written while disconnected can be retrieved by `sync`.
- 2026-11-08: nuance: when connected to `stylo-neo` (`listen` command), the M1 sends no `DotReceived`;
  strokes written during the connection go to offline memory and arrive at the next `sync`.
  Live mode is not useful here: `listen` stays a diagnostic tool.
- 2026-11-08: the M1 only reads Ncode paper (Neo notebooks, Moleskine "Smart"). On an ordinary Moleskine
  (dot grid of ~5 mm, visible to the eye) it writes in ink but captures nothing. Before suspecting
  Bluetooth or the tool, check the paper.
- 2026-11-07: `PenStatus.Battery` is above 100 (128) while the pen is charging.
- 2026-11-07: the M1's USB port is for charging only; no data goes through it.
- 2026-11-12: on notebook 3-27-551 (544 strokes), the M1 sent all strokes but **not the end marker**
  (`location == 2` in `PenClientParserV2.cs`): `OfflineDownloadFinished` is not raised. The previous version
  waited for that event and threw everything away after 60 s. Fixed: the end is tracked by the stroke
  count, and partial strokes are kept. Notebook 3-27-738, smaller, did receive its end marker. Later, the same
  notebook 3-27-551 (2,173 strokes, a printed Letter "Plain" PDF) sent its end marker normally: neither its size nor
  the printed paper explains the 2026-11-12 case; cause not established (an interrupted transfer is likely).
- 2026-11-12: after a transfer left without an end, three `sync` runs in a row received nothing from the pen
  (even after turning it off and on, even while charging); a successful `sync --notebook 3-27-738` unblocked
  the situation and 551 went through afterwards. Cause not established: on total silence, first try
  another notebook alone.
- 2026-11-12: USB charging does not change anything for a stuck transfer (battery read as 128 % while charging).
- 2026-11-12: the Neo phone app empties the pen on import: do not use it for diagnosis.
- Erasing must come **after** saving: erasing each notebook right after its download, before the strokes were
  written to disk, left a window where a crash would lose pages. Erasing is now the last step of a sync, and only
  if the save succeeded.
- A notebook whose end marker does not come cannot be erased with `--erase`: `--erase-received` accepts it when
  every announced stroke arrived. First run on a real pen: 2,173 strokes received, notebook erased, next syncs only
  bring new pages.
- The pen also sends **empty strokes** (no point): they are ignored when saving, so the count saved is lower than the
  count received (2,173 received, 2,125 with ink). Not a loss.
