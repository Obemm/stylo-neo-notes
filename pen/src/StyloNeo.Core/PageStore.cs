using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace StyloNeo.Core;

/// <summary>
/// Data folder: pages/&lt;notebook&gt;/pNNN.{json,svg,png} and journal.json.
/// Merges received strokes without ever duplicating them.
/// </summary>
public sealed class PageStore
{
    private static readonly JsonSerializerOptions Compact = new() { WriteIndented = false };
    private static readonly JsonSerializerOptions Indented = new() { WriteIndented = true };

    public string Root { get; }
    private string JournalPath => Path.Combine(Root, "journal.json");
    private string PagesDir => Path.Combine(Root, "pages");

    public PageStore(string root)
    {
        Root = Path.GetFullPath(root);
        Directory.CreateDirectory(PagesDir);
    }

    /// <summary>Reads the journal; a journal written with legacy (French) keys is read as well.</summary>
    public Journal ReadJournal()
    {
        if (!File.Exists(JournalPath)) return new Journal();
        var node = JsonNode.Parse(File.ReadAllText(JournalPath));
        LegacyFormat.UpgradeJournal(node);
        return node.Deserialize<Journal>() ?? new Journal();
    }

    private void WriteJournal(Journal j)
    {
        var tmp = JournalPath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(j, Indented));
        File.Move(tmp, JournalPath, overwrite: true);
    }

    private string BasePath(int section, int owner, int notebook, int page) =>
        Path.Combine(PagesDir, $"{section}-{owner}-{notebook}", $"p{page:D3}");

    public NotePage? ReadPage(int section, int owner, int notebook, int page)
    {
        var f = BasePath(section, owner, notebook, page) + ".json";
        return File.Exists(f) ? ReadPageFile(f) : null;
    }

    /// <summary>Reads a page file; a page written with legacy (French) keys is read as well.</summary>
    public static NotePage? ReadPageFile(string path)
    {
        var node = JsonNode.Parse(File.ReadAllText(path));
        LegacyFormat.UpgradePage(node);
        return node.Deserialize<NotePage>();
    }

    /// <summary>Adds the received strokes to existing pages and rewrites the files of the pages that changed.</summary>
    public MergeResult Merge(IEnumerable<ReceivedStroke> received)
    {
        var journal = ReadJournal();
        int newPages = 0, modified = 0, added = 0, known = 0;

        foreach (var group in received.GroupBy(r => (r.Section, r.Owner, r.Notebook, r.Page)))
        {
            var (s, o, n, p) = group.Key;
            var page = ReadPage(s, o, n, p);
            bool existed = page is not null;
            page ??= new NotePage { Section = s, Owner = o, Notebook = n, Page = p };

            var keys = page.Strokes.Select(t => t.Key).ToHashSet();
            int before = page.Strokes.Count;
            foreach (var r in group)
            {
                if (r.Stroke.Points.Count == 0) continue;
                if (keys.Add(r.Stroke.Key)) page.Strokes.Add(r.Stroke);
                else known++;
            }
            int delta = page.Strokes.Count - before;
            if (delta == 0) continue;

            added += delta;
            if (existed) modified++; else newPages++;
            page.Strokes.Sort((a, b) => a.Start.CompareTo(b.Start));
            journal.Pages[page.Key] = Save(page, journal.Pages.GetValueOrDefault(page.Key));
        }

        WriteJournal(journal);
        return new MergeResult(newPages, modified, added, known);
    }

    private JournalEntry Save(NotePage page, JournalEntry? previous)
    {
        var b = BasePath(page.Section, page.Owner, page.Notebook, page.Page);
        Directory.CreateDirectory(Path.GetDirectoryName(b)!);
        File.WriteAllText(b + ".json", JsonSerializer.Serialize(page, Compact));
        File.WriteAllText(b + ".svg", Renderer.Svg(page));
        Renderer.Png(page, b + ".png");

        return new JournalEntry
        {
            Key = page.Key,
            JsonFile = Path.GetRelativePath(Root, b + ".json"),
            SvgFile = Path.GetRelativePath(Root, b + ".svg"),
            PngFile = Path.GetRelativePath(Root, b + ".png"),
            StrokeCount = page.Strokes.Count,
            FirstStroke = Date(page.Strokes.First().Start),
            LastStroke = Date(page.Strokes.Last().End),
            Updated = DateTimeOffset.Now,
            Hash = Hash(page),
            DoneHash = previous?.DoneHash,
        };
    }

    private static DateTimeOffset? Date(long ms) =>
        ms > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(ms).ToLocalTime() : null;

    /// <summary>Content hash of a page: first 16 hex chars of SHA-256 over the sorted stroke keys.</summary>
    public static string Hash(NotePage page)
    {
        var text = string.Join("|", page.Strokes.Select(t => t.Key).Order(StringComparer.Ordinal));
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)))[..16].ToLowerInvariant();
    }

    public IReadOnlyList<JournalEntry> Pending() =>
        ReadJournal().Pages.Values.Where(e => e.IsPending).ToList();

    /// <summary>Called by the downstream conversion once the note of a page is up to date.</summary>
    public bool MarkDone(string key)
    {
        var j = ReadJournal();
        if (!j.Pages.TryGetValue(key, out var e)) return false;
        e.DoneHash = e.Hash;
        WriteJournal(j);
        return true;
    }

    private IEnumerable<string> PageFiles() =>
        Directory.EnumerateFiles(PagesDir, "p*.json", SearchOption.AllDirectories);

    /// <summary>Re-renders SVG and PNG of every page from its JSON (after a rendering change).</summary>
    public int RenderAll()
    {
        int n = 0;
        foreach (var f in PageFiles())
        {
            var page = ReadPageFile(f);
            if (page is null) continue;
            var b = f[..^5];
            File.WriteAllText(b + ".svg", Renderer.Svg(page));
            Renderer.Png(page, b + ".png");
            n++;
        }
        return n;
    }

    /// <summary>
    /// Rewrites the journal and every page file written with legacy (French) keys in the current format.
    /// The legacy journal is copied first (journal.legacy.json); nothing is deleted. Idempotent.
    /// </summary>
    /// <returns>Number of files converted (0 when everything is already in the current format).</returns>
    public int Migrate()
    {
        int converted = 0;

        if (File.Exists(JournalPath))
        {
            var node = JsonNode.Parse(File.ReadAllText(JournalPath));
            if (LegacyFormat.UpgradeJournal(node))
            {
                var backup = Path.Combine(Root, "journal.legacy.json");
                if (File.Exists(backup))
                    backup = Path.Combine(Root, $"journal.legacy.{DateTime.Now:yyyyMMdd-HHmmss}.json");
                File.Copy(JournalPath, backup);
                WriteJournal(node.Deserialize<Journal>() ?? new Journal());
                converted++;
            }
        }

        foreach (var f in PageFiles())
        {
            var node = JsonNode.Parse(File.ReadAllText(f));
            if (!LegacyFormat.UpgradePage(node)) continue;
            var page = node.Deserialize<NotePage>();
            if (page is null) continue;
            var tmp = f + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(page, Compact));
            File.Move(tmp, f, overwrite: true);
            converted++;
        }

        return converted;
    }
}
