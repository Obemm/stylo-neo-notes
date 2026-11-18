using System.Text.Json.Nodes;

namespace StyloNeo.Core;

/// <summary>
/// Reads data written by earlier versions of the tool, whose JSON keys were in French.
/// Keys are renamed in the JSON tree before deserialization; files are always saved in English.
/// </summary>
public static class LegacyFormat
{
    private static readonly (string Old, string New)[] PageKeys =
    {
        ("proprietaire", "owner"), ("carnet", "notebook"), ("traits", "strokes"),
    };

    private static readonly (string Old, string New)[] StrokeKeys =
    {
        ("debut", "start"), ("fin", "end"), ("couleur", "color"),
    };

    private static readonly (string Old, string New)[] EntryKeys =
    {
        ("cle", "key"), ("traits", "strokes"), ("premierTrait", "firstStroke"), ("dernierTrait", "lastStroke"),
        ("misAJour", "updated"), ("empreinte", "hash"), ("empreinteTraitee", "doneHash"),
    };

    /// <summary>Renames the legacy keys of a page file in place. Returns true if anything changed.</summary>
    public static bool UpgradePage(JsonNode? node)
    {
        if (node is not JsonObject page) return false;
        bool changed = Rename(page, PageKeys);
        if (page["strokes"] is JsonArray strokes)
            foreach (var s in strokes)
                if (s is JsonObject o) changed |= Rename(o, StrokeKeys);
        return changed;
    }

    /// <summary>Renames the legacy keys of the journal in place. Returns true if anything changed.</summary>
    public static bool UpgradeJournal(JsonNode? node)
    {
        if (node is not JsonObject journal || journal["pages"] is not JsonObject pages) return false;
        bool changed = false;
        foreach (var (_, entry) in pages)
            if (entry is JsonObject o) changed |= Rename(o, EntryKeys);
        return changed;
    }

    private static bool Rename(JsonObject o, (string Old, string New)[] keys)
    {
        bool changed = false;
        foreach (var (oldKey, newKey) in keys)
        {
            if (!o.ContainsKey(oldKey)) continue;
            var value = o[oldKey];
            o.Remove(oldKey);
            if (!o.ContainsKey(newKey)) o[newKey] = value;   // an English key, if present, wins
            changed = true;
        }
        return changed;
    }
}
