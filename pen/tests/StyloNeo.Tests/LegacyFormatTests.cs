using System.Text.Json.Nodes;
using StyloNeo.Core;

namespace StyloNeo.Tests;

/// <summary>Data saved by earlier versions used French JSON keys: it must still be read, and can be migrated.</summary>
public sealed class LegacyFormatTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "stylo-neo-tests", Guid.NewGuid().ToString("N"));

    // Hash computed independently: SHA-256 of the ordinal-sorted stroke keys "start-end-count" joined with '|', 16 hex chars.
    private const string LegacyHash = "ff8633de92c4c061";

    private const string LegacyPage = """
        {"section":3,"proprietaire":27,"carnet":551,"page":9,"traits":[
          {"debut":1700000000000,"fin":1700000000900,"couleur":-16777216,"points":[[10.5,12.25,0.6,1700000000000],[11,12.5,0.7,1700000000100],[11.5,13,0.5,1700000000200]]},
          {"debut":1700000005000,"fin":1700000005400,"couleur":-16777216,"points":[[20,30,0.4,1700000005000],[21,31,0.45,1700000005100]]}]}
        """;

    private const string LegacyJournal = """
        {
          "pages": {
            "3-27-551/p009": {
              "cle": "3-27-551/p009",
              "json": "pages\\3-27-551\\p009.json",
              "svg": "pages\\3-27-551\\p009.svg",
              "png": "pages\\3-27-551\\p009.png",
              "traits": 2,
              "premierTrait": "2023-11-14T23:13:20+01:00",
              "dernierTrait": "2023-11-14T23:13:25.4+01:00",
              "misAJour": "2026-11-12T09:30:00+01:00",
              "empreinte": "ff8633de92c4c061",
              "empreinteTraitee": "0000000000000000"
            }
          }
        }
        """;

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    private PageStore LegacyStore()
    {
        var store = new PageStore(_dir);
        Directory.CreateDirectory(Path.Combine(_dir, "pages", "3-27-551"));
        File.WriteAllText(Path.Combine(_dir, "pages", "3-27-551", "p009.json"), LegacyPage);
        File.WriteAllText(Path.Combine(_dir, "journal.json"), LegacyJournal);
        return store;
    }

    [Fact]
    public void A_legacy_page_is_read_correctly()
    {
        var page = LegacyStore().ReadPage(3, 27, 551, 9)!;

        Assert.Equal((3, 27, 551, 9), (page.Section, page.Owner, page.Notebook, page.Page));
        Assert.Equal(2, page.Strokes.Count);
        Assert.Equal(1_700_000_000_000, page.Strokes[0].Start);
        Assert.Equal(1_700_000_000_900, page.Strokes[0].End);
        Assert.Equal(-16777216, page.Strokes[0].Color);
        Assert.Equal(new[] { 10.5, 12.25, 0.6, 1_700_000_000_000 }, page.Strokes[0].Points[0]);
        Assert.Equal(LegacyHash, PageStore.Hash(page));
    }

    [Fact]
    public void A_legacy_journal_is_read_correctly()
    {
        var e = LegacyStore().ReadJournal().Pages["3-27-551/p009"];

        Assert.Equal("3-27-551/p009", e.Key);
        Assert.Equal(2, e.StrokeCount);
        Assert.Equal(LegacyHash, e.Hash);
        Assert.Equal("0000000000000000", e.DoneHash);
        Assert.Equal("modified", e.State);
        Assert.Equal(DateTimeOffset.Parse("2026-11-12T09:30:00+01:00"), e.Updated);
        Assert.NotNull(e.FirstStroke);
        Assert.NotNull(e.LastStroke);
    }

    [Fact]
    public void Merging_into_legacy_data_keeps_known_strokes_and_saves_in_english()
    {
        var store = LegacyStore();
        var page = store.ReadPage(3, 27, 551, 9)!;
        var again = page.Strokes.Select(s => new ReceivedStroke(3, 27, 551, 9, s));

        var r = store.Merge(again);

        Assert.Equal(new MergeResult(0, 0, 0, 2), r);
        var journal = JsonNode.Parse(File.ReadAllText(Path.Combine(_dir, "journal.json")))!["pages"]!["3-27-551/p009"]!;
        Assert.Equal(LegacyHash, (string?)journal["hash"]);
        Assert.Null(journal["empreinte"]);
    }

    [Fact]
    public void Migrate_rewrites_in_english_keeps_hashes_and_is_idempotent()
    {
        var store = LegacyStore();

        Assert.Equal(2, store.Migrate());

        Assert.Equal(LegacyJournal, File.ReadAllText(Path.Combine(_dir, "journal.legacy.json")));
        var page = JsonNode.Parse(File.ReadAllText(Path.Combine(_dir, "pages", "3-27-551", "p009.json")))!.AsObject();
        Assert.Equal(new[] { "section", "owner", "notebook", "page", "strokes" }, page.Select(kv => kv.Key));
        Assert.Equal(new[] { "start", "end", "color", "points" }, page["strokes"]![0]!.AsObject().Select(kv => kv.Key));
        var entry = JsonNode.Parse(File.ReadAllText(Path.Combine(_dir, "journal.json")))!["pages"]!["3-27-551/p009"]!.AsObject();
        Assert.Equal(new[] { "key", "json", "svg", "png", "strokes", "firstStroke", "lastStroke", "updated", "hash", "doneHash" },
                     entry.Select(kv => kv.Key));
        Assert.Equal(LegacyHash, (string?)entry["hash"]);
        Assert.Equal(LegacyHash, PageStore.Hash(store.ReadPage(3, 27, 551, 9)!));

        var journalAfterFirst = File.ReadAllText(Path.Combine(_dir, "journal.json"));
        Assert.Equal(0, store.Migrate());
        Assert.Equal(journalAfterFirst, File.ReadAllText(Path.Combine(_dir, "journal.json")));
        Assert.Single(Directory.GetFiles(_dir, "journal.legacy*.json"));
    }

    [Fact]
    public void Migrate_on_current_data_converts_nothing()
    {
        var store = new PageStore(_dir);
        store.Merge(new[] { new ReceivedStroke(1, 2, 3, 4, new InkStroke { Start = 5, End = 6, Points = { new[] { 1.0, 1.0, 0.5, 5.0 } } }) });

        Assert.Equal(0, store.Migrate());
        Assert.False(File.Exists(Path.Combine(_dir, "journal.legacy.json")));
    }
}
