using Neosmartpen.Net;
using Neosmartpen.Net.Bluetooth;
using StyloNeo.Core;

namespace StyloNeo;

public sealed record SyncOptions(string? Mac, bool Erase, TimeSpan SearchTimeout, TimeSpan? Listen = null, string? Notebook = null,
                                 bool NoPrompt = false);

/// <summary>The pen asks for a password that is not saved and cannot be typed here (--no-prompt or no console).</summary>
public sealed class PasswordNeededException(string message) : InvalidOperationException(message);

/// <summary>Strokes received (even partial) and a report per notebook.</summary>
public sealed record SyncResult(IReadOnlyList<ReceivedStroke> Strokes, IReadOnlyList<NotebookReport> Reports);

/// <summary>
/// Bluetooth connection to the pen and download of its offline data (NeoLAB SDK).
/// Safeguards: never erase without --erase; stop before password attempts could trigger a pen reset.
/// </summary>
public sealed class PenSync
{
    /// <summary>Number of password attempts always kept in reserve.</summary>
    private const int AttemptsInReserve = 3;

    private readonly SyncOptions _opt;
    private readonly PenController _ctrl = new();
    private readonly GenericBluetoothPenClient _bt;
    private readonly List<ReceivedStroke> _received = new();
    private readonly object _lock = new();
    private int _maxForce = 1023;
    private bool _vaultTried;

    /// <summary>Password typed during this sync (null if it came from the vault or was not requested).</summary>
    public string? TypedPassword { get; private set; }
    public string? Mac { get; private set; }

    private TaskCompletionSource<PenInformation> _found = NewTcs<PenInformation>();
    private readonly TaskCompletionSource<bool> _authenticated = NewTcs<bool>();
    private readonly TaskCompletionSource<PenStatusReceivedEventArgs> _status = NewTcs<PenStatusReceivedEventArgs>();
    private TaskCompletionSource<OfflineDataInfo[]> _list = NewTcs<OfflineDataInfo[]>();
    private TaskCompletionSource<bool> _download = NewTcs<bool>();
    private TaskCompletionSource<bool> _erased = NewTcs<bool>();
    private DateTime _lastActivity = DateTime.Now;
    private int _receivedInNotebook, _totalInNotebook;
    private bool _disconnected;

    /// <summary>Time without receiving anything before giving up on a notebook.</summary>
    private static readonly TimeSpan SilenceTimeout = TimeSpan.FromSeconds(60);
    /// <summary>Wait for the end marker once all announced strokes have arrived.</summary>
    private static readonly TimeSpan EndTimeoutAfterTotal = TimeSpan.FromSeconds(5);

    private static TaskCompletionSource<T> NewTcs<T>() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    public PenSync(SyncOptions opt)
    {
        _opt = opt;
        _bt = new GenericBluetoothPenClient(_ctrl);
        _bt.onAddPenController += (_, info) => Candidate(info);

        _ctrl.Connected += (_, a) =>
        {
            if (a.MaxForce > 0) _maxForce = a.MaxForce;
            Console.WriteLine(L.T($"Connected: {a.DeviceName} {a.SubName}, firmware {a.FirmwareVersion}, protocol {a.ProtocolVersion}",
                                  $"Connecté : {a.DeviceName} {a.SubName}, firmware {a.FirmwareVersion}, protocole {a.ProtocolVersion}"));
        };
        _ctrl.Disconnected += (_, _) =>
        {
            var e = new InvalidOperationException(L.T("The pen disconnected.", "Le stylo s'est déconnecté."));
            _disconnected = true;
            _authenticated.TrySetException(e); _list.TrySetException(e); _download.TrySetException(e); _erased.TrySetException(e);
        };
        _ctrl.PasswordRequested += (_, a) => OnPasswordRequested(a.RetryCount, a.ResetCount);
        _ctrl.Authenticated += (_, _) => _authenticated.TrySetResult(true);
        _ctrl.PenStatusReceived += (_, a) => _status.TrySetResult(a);
        _ctrl.OfflineDataListReceived += (_, a) => _list.TrySetResult(a.OfflineNotes ?? Array.Empty<OfflineDataInfo>());
        _ctrl.OfflineDataDownloadStarted += (_, _) => _lastActivity = DateTime.Now;
        _ctrl.OfflineStrokeReceived += (_, a) =>
        {
            _lastActivity = DateTime.Now;
            _receivedInNotebook = a.AmountDone; _totalInNotebook = a.Total;
            lock (_lock) foreach (var s in a.Strokes) Add(s);
            Console.Write($"\r  {a.AmountDone}/{a.Total}   ");
        };
        _ctrl.OfflineDownloadFinished += (_, a) => _download.TrySetResult(a.Result);
        _ctrl.OfflineDataRemoved += (_, a) => _erased.TrySetResult(a.Result);
    }

    private void Candidate(PenInformation info)
    {
        if (info.Protocol == Protocols.NONE) return;
        bool ok = _opt.Mac is null
            || string.Equals(NormalizeMac(info.MacAddress), NormalizeMac(_opt.Mac), StringComparison.OrdinalIgnoreCase);
        if (ok) _found.TrySetResult(info);
    }

    private static string NormalizeMac(string? mac) => (mac ?? "").Replace(":", "").Replace("-", "");

    private void OnPasswordRequested(int attempts, int limit)
    {
        int remaining = limit - attempts;
        if (remaining <= AttemptsInReserve)
        {
            _authenticated.TrySetException(new InvalidOperationException(
                L.T($"Stopped for safety: only {remaining} password attempt(s) left before the pen erases all its data. " +
                    "Check the password in Neo Studio 2 before trying again.",
                    $"Arrêt par sécurité : il ne reste que {remaining} essai(s) de mot de passe avant que le stylo efface toutes ses données. " +
                    "Vérifiez le mot de passe dans Neo Studio 2 avant de réessayer.")));
            return;
        }
        if (!_vaultTried)
        {
            _vaultTried = true;
            string? saved = null;
            try { saved = CredentialVault.Read(); }
            catch (Exception e) { Console.WriteLine(L.T($"Windows Credential Manager unreadable ({e.Message}): manual entry.",
                                                       $"Gestionnaire d'identification Windows illisible ({e.Message}) : saisie manuelle.")); }
            if (saved is not null)
            {
                Console.WriteLine(L.T("Password taken from Windows Credential Manager.",
                                      "Mot de passe du stylo lu dans le Gestionnaire d'identification Windows."));
                _ctrl.InputPassword(saved);
                return;
            }
        }
        else if (TypedPassword is null)
        {
            // The saved password has just been rejected: remove it so no more attempts are wasted.
            try { CredentialVault.Forget(); } catch { /* nothing more to do */ }
            Console.WriteLine(L.T("The saved password was rejected by the pen: removed from Windows Credential Manager.",
                                  "Le mot de passe enregistré a été refusé par le stylo : retiré du Gestionnaire d'identification Windows."));
        }

        if (Console.IsInputRedirected || _opt.NoPrompt)
        {
            _authenticated.TrySetException(new PasswordNeededException(
                L.T("The pen asks for its password: run stylo-neo in a real terminal to type it.",
                    "Le stylo demande son mot de passe : lancez stylo-neo dans un vrai terminal pour le saisir.")));
            return;
        }
        Console.WriteLine(L.T($"The pen asks for its password ({remaining} attempts left before reset, " +
                              $"the tool stops when {AttemptsInReserve} are left).",
                              $"Le stylo demande son mot de passe ({remaining} essais restants avant réinitialisation, " +
                              $"l'outil s'arrête quand il en reste {AttemptsInReserve})."));
        var pwd = ReadMasked(L.T("Pen password: ", "Mot de passe du stylo : "));
        if (string.IsNullOrEmpty(pwd))
        {
            _authenticated.TrySetException(new OperationCanceledException(L.T("Input cancelled.", "Saisie annulée.")));
            return;
        }
        TypedPassword = pwd;
        _ctrl.InputPassword(pwd);
    }

    private static string ReadMasked(string prompt)
    {
        Console.Write(prompt);
        var sb = new System.Text.StringBuilder();
        while (true)
        {
            var k = Console.ReadKey(intercept: true);
            if (k.Key == ConsoleKey.Enter) break;
            if (k.Key == ConsoleKey.Escape) { sb.Clear(); break; }
            if (k.Key == ConsoleKey.Backspace) { if (sb.Length > 0) { sb.Length--; Console.Write("\b \b"); } continue; }
            if (!char.IsControl(k.KeyChar)) { sb.Append(k.KeyChar); Console.Write('*'); }
        }
        Console.WriteLine();
        return sb.ToString();
    }

    private void Add(Stroke s)
    {
        var t = new InkStroke { Start = s.TimeStart, End = s.TimeEnd, Color = s.Color };
        foreach (var d in s)
        {
            double p = Math.Round(Math.Clamp((double)d.Force / _maxForce, 0, 1), 3);
            t.Points.Add(new[] { Math.Round(d.X, 2), Math.Round(d.Y, 2), p, d.Timestamp });
        }
        _received.Add(new ReceivedStroke(s.Section, s.Owner, s.Note, s.Page, t));
    }

    /// <summary>
    /// Connects, downloads the notebooks, and returns the received strokes — even partial — and a
    /// report per notebook. A stuck notebook does not stop the following ones.
    /// </summary>
    public async Task<SyncResult> Run()
    {
        if (!await _bt.GetBluetoothIsEnabledAsync())
            throw new InvalidOperationException(L.T("Bluetooth unavailable or disabled on this PC.",
                                                    "Bluetooth indisponible ou désactivé sur ce PC."));

        Console.WriteLine(L.T("Searching for the pen… (turn it on: it should blink blue, and must not be connected to a phone)",
                              "Recherche du stylo… (allumez-le : il doit clignoter en bleu, et ne doit pas être connecté à un téléphone)"));
        _bt.StartLEAdvertisementWatcher();
        PenInformation pen;
        try { pen = await _found.Task.WaitAsync(_opt.SearchTimeout); }
        catch (TimeoutException) { throw new InvalidOperationException(L.T("No pen found. Turn it on and switch off the phone's Bluetooth.",
                                                                           "Aucun stylo trouvé. Allumez-le et coupez le Bluetooth du téléphone.")); }
        finally { _bt.StopLEAdvertisementWatcher(); }

        Mac = pen.MacAddress;
        Console.WriteLine(L.T($"Pen found: {pen.Name} ({pen.MacAddress}), protocol V{pen.Protocol}",
                              $"Stylo trouvé : {pen.Name} ({pen.MacAddress}), protocole V{pen.Protocol}"));
        if (pen.Protocol == Protocols.V1 && !_opt.Erase)
            throw new InvalidOperationException(L.T(
                "This pen uses protocol V1: the SDK always erases pages after download. " +
                "Run again with --erase if you accept that the pages leave the pen (they will be on the PC).",
                "Ce stylo utilise le protocole V1 : le SDK efface toujours les pages après le téléchargement. " +
                "Relancez avec --erase si vous acceptez que les pages quittent le stylo (elles seront sur le PC)."));

        var reports = new List<NotebookReport>();
        if (!await _bt.Connect(pen))
            throw new InvalidOperationException(L.T("Connection refused. The pen may already be connected to a phone.",
                                                    "Connexion refusée. Le stylo est peut-être déjà connecté à un téléphone."));

        try
        {
            await _authenticated.Task.WaitAsync(TimeSpan.FromMinutes(3));
            _ctrl.RequestPenStatus();
            try
            {
                var st = await _status.Task.WaitAsync(TimeSpan.FromSeconds(10));
                Console.WriteLine(L.T(
                    $"Pen status: battery {st.Battery} %, memory used {st.UsedMem} %, " +
                    $"offline recording {(st.UseOfflineData ? "enabled" : "DISABLED")}",
                    $"État du stylo : batterie {st.Battery} %, mémoire utilisée {st.UsedMem} %, " +
                    $"enregistrement hors connexion {(st.UseOfflineData ? "activé" : "DÉSACTIVÉ")}"));
                Console.WriteLine(L.T(
                    $"  power on by pen tip: {(st.AutoPowerOn ? "yes" : "NO")}, " +
                    $"power on with cap: {(st.PenCapPower ? "yes" : "no")}, " +
                    $"auto shutdown after {st.AutoShutdownTime} min",
                    $"  allumage par la pointe : {(st.AutoPowerOn ? "oui" : "NON")}, " +
                    $"allumage par le capuchon : {(st.PenCapPower ? "oui" : "non")}, " +
                    $"extinction automatique après {st.AutoShutdownTime} min"));
                if (!st.UseOfflineData)
                    Console.WriteLine(L.T(
                        "  → The pen keeps nothing while disconnected: enable it in Neo Studio 2 (pen settings).",
                        "  → Le stylo ne garde rien hors connexion : activez l'enregistrement dans Neo Studio 2 (réglages du stylo)."));
                if (!st.AutoPowerOn)
                    Console.WriteLine(L.T(
                        "  → Pen off, writing does not turn it on: nothing is captured while the light is off.",
                        "  → Stylo éteint, écrire ne l'allume pas : rien n'est capturé tant que le voyant est éteint."));
            }
            catch (TimeoutException) { Console.WriteLine(L.T("Pen status: no answer (continuing).", "État du stylo : pas de réponse (on continue).")); }
            _ctrl.AddAvailableNote();   // all Ncode notebooks
            if (_opt.Listen is { } duration)
            {
                await Listen(duration);
                return new SyncResult(Array.Empty<ReceivedStroke>(), Array.Empty<NotebookReport>());
            }
            _ctrl.RequestOfflineDataList();
            var notebooks = await _list.Task.WaitAsync(TimeSpan.FromSeconds(30));
            Console.WriteLine(notebooks.Length == 0
                ? L.T("No page in the pen's memory.", "Aucune page dans la mémoire du stylo.")
                : L.T($"{notebooks.Length} notebook(s) in memory: {string.Join(", ", notebooks.Select(Id))}",
                      $"{notebooks.Length} carnet(s) en mémoire : {string.Join(", ", notebooks.Select(Id))}"));

            if (_opt.Notebook is not null)
            {
                NotebookReport.TryParseId(_opt.Notebook, out var sec, out var own, out var note);
                var chosen = notebooks.Where(c => c.Section == sec && c.Owner == own && c.Note == note).ToArray();
                if (chosen.Length == 0)
                    throw new InvalidOperationException(
                        L.T($"Notebook {_opt.Notebook} is not in the pen's memory. Notebooks present: ",
                            $"Le carnet {_opt.Notebook} n'est pas dans la mémoire du stylo. Carnets présents : ") +
                        (notebooks.Length == 0 ? L.T("none", "aucun") : string.Join(", ", notebooks.Select(Id))) + ".");
                notebooks = chosen;
            }

            foreach (var c in notebooks)
            {
                if (_disconnected)
                {
                    reports.Add(new NotebookReport(Id(c), NotebookState.NotAttempted, 0, 0));
                    continue;
                }
                reports.Add(await DownloadNotebook(c, pen.Protocol));
            }
        }
        finally
        {
            if (_bt.Alive) await _bt.Disconnect();
        }

        lock (_lock) return new SyncResult(_received.ToList(), reports);
    }

    private static string Id(OfflineDataInfo c) => $"{c.Section}-{c.Owner}-{c.Note}";

    /// <summary>
    /// Downloads a notebook without asking the pen to erase at the end of the transfer: with --erase,
    /// erasing is requested separately, and only if the pen confirmed the end (protocol V2).
    /// </summary>
    private async Task<NotebookReport> DownloadNotebook(OfflineDataInfo c, int protocol)
    {
        // In V1 the SDK always erases at the end of the transfer (refused above without --erase).
        bool eraseAtEnd = protocol == Protocols.V1;
        Console.WriteLine(L.T($"Downloading notebook {Id(c)}", $"Téléchargement du carnet {Id(c)}") +
                          (_opt.Erase ? L.T(" (erased if the end is confirmed)", " (effacé si la fin est confirmée)")
                                      : L.T(" (no erase)", " (sans effacement)")));
        _download = NewTcs<bool>();
        _receivedInNotebook = 0; _totalInNotebook = 0;
        _lastActivity = DateTime.Now;
        if (!_ctrl.RequestOfflineData(c.Section, c.Owner, c.Note, deleteOnFinished: eraseAtEnd))
        {
            Console.WriteLine(L.T("  The pen refused the download request.", "  Le stylo a refusé la demande de téléchargement."));
            return new NotebookReport(Id(c), NotebookState.NothingReceived, 0, 0);
        }
        var end = await WaitForDownloadEnd();
        Console.WriteLine();
        var report = new NotebookReport(Id(c), NotebookReport.Classify(end, _receivedInNotebook, _totalInNotebook),
                                        _receivedInNotebook, _totalInNotebook);
        Console.WriteLine(L.T($"  Notebook {report.Notebook}: {report.Label}", $"  Carnet {report.Notebook} : {report.Label}"));

        if (_opt.Erase && !eraseAtEnd)
        {
            if (!report.EraseAllowed)
                Console.WriteLine(L.T($"  Notebook {report.Notebook} not erased: its end was not confirmed by the pen.",
                                      $"  Carnet {report.Notebook} non effacé : sa fin n'a pas été confirmée par le stylo."));
            else if (!_disconnected)
            {
                _erased = NewTcs<bool>();
                _ctrl.RequestRemoveOfflineData(c.Section, c.Owner, new[] { c.Note });
                try
                {
                    bool ok = await _erased.Task.WaitAsync(TimeSpan.FromSeconds(15));
                    Console.WriteLine(ok
                        ? L.T($"  Notebook {report.Notebook} erased from the pen.", $"  Carnet {report.Notebook} effacé du stylo.")
                        : L.T($"  The pen refused to erase notebook {report.Notebook}.", $"  Le stylo a refusé d'effacer le carnet {report.Notebook}."));
                }
                catch (Exception e)
                {
                    Console.WriteLine(L.T($"  Erasing notebook {report.Notebook} not confirmed: {e.Message}",
                                          $"  Effacement du carnet {report.Notebook} non confirmé : {e.Message}"));
                }
            }
        }
        return report;
    }

    /// <summary>Diagnostic: prints live the Ncode address of every stroke written during the connection.</summary>
    private async Task Listen(TimeSpan duration)
    {
        int strokes = 0;
        string? last = null;
        void OnDot(IPenClient _, DotReceivedEventArgs a)
        {
            if (a.Dot.DotType != DotTypes.PEN_DOWN) return;
            strokes++;
            var address = $"{a.Dot.Section}-{a.Dot.Owner}-{a.Dot.Note}, page {a.Dot.Page}";
            if (address != last) Console.WriteLine(L.T($"  stroke captured: notebook {address}", $"  trait capturé : carnet {address}"));
            last = address;
        }
        _ctrl.DotReceived += OnDot;
        Console.WriteLine(L.T($"Listening for {duration.TotalSeconds:0} s: write a few words on the notebook to test…",
                              $"Écoute pendant {duration.TotalSeconds:0} s : écrivez quelques mots sur le carnet pour tester…"));
        await Task.Delay(duration);
        _ctrl.DotReceived -= OnDot;
        Console.WriteLine(strokes == 0
            ? L.T("No stroke captured: the pen does not recognise this paper (or did not touch the page).",
                  "Aucun trait capturé : le stylo ne reconnaît pas ce papier (ou n'a pas touché la page).")
            : L.T($"{strokes} stroke(s) captured. Live strokes are not kept in the pen's memory.",
                  $"{strokes} trait(s) capturé(s). Les traits écrits en direct ne sont pas gardés dans la mémoire du stylo."));
    }

    /// <summary>
    /// Waits for the end while strokes keep arriving. Returns true/false if the pen signalled the end (success or not),
    /// null if it did not: disconnection, 60 s of silence, or 5 s after the last announced stroke.
    /// </summary>
    private async Task<bool?> WaitForDownloadEnd()
    {
        while (true)
        {
            var done = await Task.WhenAny(_download.Task, Task.Delay(TimeSpan.FromSeconds(1)));
            if (done == _download.Task)
                return _download.Task.IsCompletedSuccessfully ? _download.Task.Result : null;
            var silence = DateTime.Now - _lastActivity;
            if (_totalInNotebook > 0 && _receivedInNotebook >= _totalInNotebook && silence > EndTimeoutAfterTotal) return null;
            if (silence > SilenceTimeout) return null;
        }
    }
}
