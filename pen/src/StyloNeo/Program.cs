using System.Text;
using System.Text.Json;
using StyloNeo;
using StyloNeo.Core;

Console.OutputEncoding = Encoding.UTF8;

const string Help = """
stylo-neo: downloads the pages of a Neo smartpen and files them for note-taking apps.

  stylo-neo sync [--mac AA:BB:..] [--notebook 3-27-738] [--erase]
                                    downloads the pen's pages (never erases by default);
                                    --notebook: a single notebook; --erase: only the notebooks
                                    whose end the pen confirmed
  stylo-neo pending [--json]        new or modified pages, not yet converted
  stylo-neo mark-done <key>         the note of this page is up to date (key e.g. 3-27-551/p009)
  stylo-neo listen [--seconds 45]   diagnostic: prints live the notebook and page being written
  stylo-neo forget-password         removes the pen password from Windows Credential Manager
  stylo-neo render                  re-renders SVG and PNG of every page
  stylo-neo log                     all known pages
  stylo-neo migrate                 rewrites data saved by older versions (French keys) in the current format
  stylo-neo help                    this help

Common option: --data-dir <path>    (default: %STYLO_NEO_DATA%, else %USERPROFILE%\Documents\StyloNeo)

Exit codes: 0 ok · 1 unknown command or page · 2 error · 3 sync: at least one notebook incomplete
""";

var arguments = args.ToList();
string? Option(string name)
{
    int i = arguments.IndexOf(name);
    if (i < 0) return null;
    if (i + 1 >= arguments.Count) throw new ArgumentException($"{name} expects a value.");
    var v = arguments[i + 1];
    arguments.RemoveRange(i, 2);
    return v;
}
bool Flag(string name) => arguments.Remove(name);

try
{
    var dataDir = Option("--data-dir")
        ?? Environment.GetEnvironmentVariable("STYLO_NEO_DATA")
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Documents", "StyloNeo");
    var command = arguments.FirstOrDefault();
    if (command is null or "help" or "--help" or "-h")
    {
        Console.WriteLine(Help);
        return 0;
    }

    var known = new[] { "sync", "pending", "mark-done", "listen", "forget-password", "render", "log", "migrate" };
    if (!known.Contains(command))
    {
        Console.WriteLine(Help);
        return 1;
    }

    var store = new PageStore(dataDir);

    switch (command)
    {
        case "sync":
        {
            var mac = Option("--mac");
            var notebook = Option("--notebook");
            if (notebook is not null && !NotebookReport.TryParseId(notebook, out _, out _, out _))
                throw new ArgumentException($"--notebook expects a section-owner-notebook id, e.g. 3-27-738 (got: {notebook}).");
            var erase = Flag("--erase");
            var sync = new PenSync(new SyncOptions(mac, erase, TimeSpan.FromSeconds(45), Notebook: notebook));
            var res = await sync.Run();
            // Received strokes are always kept, even when a notebook is incomplete.
            var r = store.Merge(res.Strokes);
            Console.WriteLine($"New pages: {r.NewPages} · modified: {r.ModifiedPages} · " +
                              $"strokes added: {r.StrokesAdded} · already known: {r.StrokesAlreadyKnown}");
            Console.WriteLine($"Pages to convert: {store.Pending().Count} · data folder: {store.Root}");
            if (res.Reports.Count > 0)
            {
                Console.WriteLine("Report per notebook:");
                foreach (var b in res.Reports) Console.WriteLine($"  {b.Notebook}: {b.Label}");
            }
            if (res.Strokes.Count > 0) OfferToSavePassword(sync);
            bool allReceived = res.Reports.All(b => b.State is NotebookState.Complete or NotebookState.EndNotConfirmed);
            if (!allReceived)
                Console.WriteLine("At least one notebook did not arrive in full: it stays in the pen, run sync again later " +
                                  "(strokes already received will not be duplicated).");
            return allReceived ? 0 : 3;
        }
        case "pending":
        {
            var list = store.Pending();
            if (Flag("--json"))
                Console.WriteLine(JsonSerializer.Serialize(new { dataDir = store.Root, pages = list },
                    new JsonSerializerOptions { WriteIndented = true }));
            else if (list.Count == 0) Console.WriteLine("Nothing to convert.");
            else foreach (var e in list) Console.WriteLine($"{e.Key}  {e.State,-9} {e.StrokeCount,5} strokes  {e.LastStroke:yyyy-MM-dd HH:mm}  {e.PngFile}");
            return 0;
        }
        case "mark-done":
        {
            var key = arguments.ElementAtOrDefault(1) ?? throw new ArgumentException("Page key expected, e.g. 3-27-603/p012.");
            if (!store.MarkDone(key)) { Console.Error.WriteLine($"Unknown page: {key}"); return 1; }
            Console.WriteLine($"{key} marked as done.");
            return 0;
        }
        case "listen":
        {
            var seconds = int.TryParse(Option("--seconds"), out var s) ? s : 45;
            await new PenSync(new SyncOptions(Option("--mac"), false, TimeSpan.FromSeconds(45), TimeSpan.FromSeconds(seconds))).Run();
            return 0;
        }
        case "forget-password":
            Console.WriteLine(CredentialVault.Forget()
                ? "Pen password removed from Windows Credential Manager."
                : "No saved password.");
            return 0;
        case "render":
            Console.WriteLine($"{store.RenderAll()} page(s) rendered.");
            return 0;
        case "log":
            foreach (var e in store.ReadJournal().Pages.Values)
                Console.WriteLine($"{e.Key}  {e.State,-9} {e.StrokeCount,5} strokes  {e.LastStroke:yyyy-MM-dd HH:mm}");
            return 0;
        case "migrate":
        {
            int n = store.Migrate();
            Console.WriteLine(n == 0
                ? $"Nothing to migrate: data already in the current format ({store.Root})."
                : $"{n} file(s) converted to the current format ({store.Root}).");
            return 0;
        }
        default:
            Console.WriteLine(Help);
            return 1;
    }
}
catch (Exception e)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine($"Error: {e.Message}");
    return 2;
}

// The password worked (the sync went through): offer to keep it in Windows Credential Manager.
static void OfferToSavePassword(PenSync s)
{
    if (s.TypedPassword is null || Console.IsInputRedirected) return;
    Console.Write("Save this password in Windows Credential Manager so you don't have to type it again? (y/N) ");
    var answer = Console.ReadLine()?.Trim().ToLowerInvariant();
    if (answer is "y" or "yes")
    {
        CredentialVault.Write(s.TypedPassword, s.Mac);
        Console.WriteLine($"Saved (\"{CredentialVault.Target}\"). To remove it: stylo-neo forget-password");
    }
}
