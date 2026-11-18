using System.Text;
using System.Text.Json;
using StyloNeo;
using StyloNeo.Core;

Console.OutputEncoding = Encoding.UTF8;

const string HelpEn = """
stylo-neo: downloads the pages of a Neo smartpen and files them for note-taking apps.

  stylo-neo sync [--mac AA:BB:..] [--notebook 3-27-738] [--erase] [--no-prompt]
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

Common options: --data-dir <path>   (default: %STYLO_NEO_DATA%, else %USERPROFILE%\Documents\StyloNeo)
                --lang en|fr        language of messages (default: %STYLO_NEO_LANG%, else en)

Exit codes: 0 ok · 1 unknown command or page · 2 error · 3 sync: at least one notebook incomplete
            · 4 sync: the pen asks for a password that is not saved (--no-prompt, or no console)
""";

const string HelpFr = """
stylo-neo : télécharge les pages d'un stylo Neo et les range pour les applications de prise de notes.

  stylo-neo sync [--mac AA:BB:..] [--notebook 3-27-738] [--erase] [--no-prompt]
                                    télécharge les pages du stylo (n'efface jamais par défaut) ;
                                    --notebook : un seul carnet ; --erase : efface seulement
                                    les carnets dont le stylo a confirmé la fin
  stylo-neo pending [--json]        pages nouvelles ou modifiées, pas encore converties
  stylo-neo mark-done <clé>         la note de cette page est à jour (clé, ex. 3-27-551/p009)
  stylo-neo listen [--seconds 45]   diagnostic : affiche en direct le carnet et la page en cours d'écriture
  stylo-neo forget-password         retire le mot de passe du stylo du Gestionnaire d'identification Windows
  stylo-neo render                  régénère le SVG et le PNG de chaque page
  stylo-neo log                     toutes les pages connues
  stylo-neo migrate                 réécrit au format actuel les données des anciennes versions (clés en français)
  stylo-neo help                    cette aide

Options communes : --data-dir <chemin>  (par défaut : %STYLO_NEO_DATA%, sinon %USERPROFILE%\Documents\StyloNeo)
                   --lang en|fr         langue des messages (par défaut : %STYLO_NEO_LANG%, sinon en)

Codes de sortie : 0 ok · 1 commande ou page inconnue · 2 erreur · 3 synchro : au moins un carnet incomplet
                  · 4 synchro : le stylo demande un mot de passe non enregistré (--no-prompt, ou pas de console)
""";

string Help() => L.T(HelpEn, HelpFr);

var arguments = args.ToList();
string? Option(string name)
{
    int i = arguments.IndexOf(name);
    if (i < 0) return null;
    if (i + 1 >= arguments.Count) throw new ArgumentException(L.T($"{name} expects a value.", $"{name} attend une valeur."));
    var v = arguments[i + 1];
    arguments.RemoveRange(i, 2);
    return v;
}
bool Flag(string name) => arguments.Remove(name);

try
{
    // Language first, so every following message (help and errors included) is in the chosen language.
    L.Fr = L.Resolve(Option("--lang"), Environment.GetEnvironmentVariable(L.EnvVar));
    var dataDir = Option("--data-dir")
        ?? Environment.GetEnvironmentVariable("STYLO_NEO_DATA")
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Documents", "StyloNeo");
    var command = arguments.FirstOrDefault();
    if (command is null or "help" or "--help" or "-h")
    {
        Console.WriteLine(Help());
        return 0;
    }

    var known = new[] { "sync", "pending", "mark-done", "listen", "forget-password", "render", "log", "migrate" };
    if (!known.Contains(command))
    {
        Console.WriteLine(Help());
        return 1;
    }

    var store = new PageStore(dataDir);
    var strokesWord = L.T("strokes", "traits ");

    switch (command)
    {
        case "sync":
        {
            var mac = Option("--mac");
            var notebook = Option("--notebook");
            if (notebook is not null && !NotebookReport.TryParseId(notebook, out _, out _, out _))
                throw new ArgumentException(L.T(
                    $"--notebook expects a section-owner-notebook id, e.g. 3-27-738 (got: {notebook}).",
                    $"--notebook attend un identifiant section-propriétaire-carnet, ex. 3-27-738 (reçu : {notebook})."));
            var erase = Flag("--erase");
            var noPrompt = Flag("--no-prompt");
            var sync = new PenSync(new SyncOptions(mac, erase, TimeSpan.FromSeconds(45), Notebook: notebook, NoPrompt: noPrompt));
            var res = await sync.Run();
            // Received strokes are always kept, even when a notebook is incomplete.
            var r = store.Merge(res.Strokes);
            Console.WriteLine(L.T(
                $"New pages: {r.NewPages} · modified: {r.ModifiedPages} · " +
                $"strokes added: {r.StrokesAdded} · already known: {r.StrokesAlreadyKnown}",
                $"Pages nouvelles : {r.NewPages} · modifiées : {r.ModifiedPages} · " +
                $"traits ajoutés : {r.StrokesAdded} · déjà connus : {r.StrokesAlreadyKnown}"));
            Console.WriteLine(L.T(
                $"Pages to convert: {store.Pending().Count} · data folder: {store.Root}",
                $"Pages à convertir : {store.Pending().Count} · dossier des données : {store.Root}"));
            if (res.Reports.Count > 0)
            {
                Console.WriteLine(L.T("Report per notebook:", "Bilan par carnet :"));
                foreach (var b in res.Reports) Console.WriteLine($"  {b.Notebook}{L.T(":", " :")} {b.Label}");
            }
            if (res.Strokes.Count > 0) OfferToSavePassword(sync);
            bool allReceived = res.Reports.All(b => b.State is NotebookState.Complete or NotebookState.EndNotConfirmed);
            if (!allReceived)
                Console.WriteLine(L.T(
                    "At least one notebook did not arrive in full: it stays in the pen, run sync again later " +
                    "(strokes already received will not be duplicated).",
                    "Au moins un carnet n'est pas arrivé en entier : il reste dans le stylo, relancez la synchro plus tard " +
                    "(les traits déjà reçus ne seront pas dupliqués)."));
            return allReceived ? 0 : 3;
        }
        case "pending":
        {
            var list = store.Pending();
            if (Flag("--json"))
                Console.WriteLine(JsonSerializer.Serialize(new { dataDir = store.Root, pages = list },
                    new JsonSerializerOptions { WriteIndented = true }));
            else if (list.Count == 0) Console.WriteLine(L.T("Nothing to convert.", "Rien à convertir."));
            else foreach (var e in list)
                Console.WriteLine($"{e.Key}  {e.StateLabel,-9} {e.StrokeCount,5} {strokesWord}  {e.LastStroke:yyyy-MM-dd HH:mm}  {e.PngFile}");
            return 0;
        }
        case "mark-done":
        {
            var key = arguments.ElementAtOrDefault(1)
                ?? throw new ArgumentException(L.T("Page key expected, e.g. 3-27-603/p012.",
                                                   "Clé de page attendue, ex. 3-27-603/p012."));
            if (!store.MarkDone(key)) { Console.Error.WriteLine(L.T($"Unknown page: {key}", $"Page inconnue : {key}")); return 1; }
            Console.WriteLine(L.T($"{key} marked as done.", $"{key} marquée comme traitée."));
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
                ? L.T("Pen password removed from Windows Credential Manager.",
                      "Mot de passe du stylo retiré du Gestionnaire d'identification Windows.")
                : L.T("No saved password.", "Aucun mot de passe enregistré."));
            return 0;
        case "render":
        {
            int n = store.RenderAll();
            Console.WriteLine(L.T($"{n} page(s) rendered.", $"{n} page(s) régénérée(s)."));
            return 0;
        }
        case "log":
            foreach (var e in store.ReadJournal().Pages.Values)
                Console.WriteLine($"{e.Key}  {e.StateLabel,-9} {e.StrokeCount,5} {strokesWord}  {e.LastStroke:yyyy-MM-dd HH:mm}");
            return 0;
        case "migrate":
        {
            int n = store.Migrate();
            Console.WriteLine(n == 0
                ? L.T($"Nothing to migrate: data already in the current format ({store.Root}).",
                      $"Rien à migrer : les données sont déjà au format actuel ({store.Root}).")
                : L.T($"{n} file(s) converted to the current format ({store.Root}).",
                      $"{n} fichier(s) converti(s) au format actuel ({store.Root})."));
            return 0;
        }
        default:
            Console.WriteLine(Help());
            return 1;
    }
}
catch (PasswordNeededException e)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine(e.Message);
    return 4;
}
catch (Exception e)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine(L.T($"Error: {e.Message}", $"Erreur : {e.Message}"));
    return 2;
}

// The password worked (the sync went through): offer to keep it in Windows Credential Manager.
static void OfferToSavePassword(PenSync s)
{
    if (s.TypedPassword is null || Console.IsInputRedirected) return;
    Console.Write(L.T(
        "Save this password in Windows Credential Manager so you don't have to type it again? (y/N) ",
        "Enregistrer ce mot de passe dans le Gestionnaire d'identification Windows pour ne plus avoir à le saisir ? (o/N) "));
    if (L.IsYes(Console.ReadLine()))
    {
        CredentialVault.Write(s.TypedPassword, s.Mac);
        Console.WriteLine(L.T(
            $"Saved (\"{CredentialVault.Target}\"). To remove it: stylo-neo forget-password",
            $"Enregistré (« {CredentialVault.Target} »). Pour le retirer : stylo-neo forget-password"));
    }
}
