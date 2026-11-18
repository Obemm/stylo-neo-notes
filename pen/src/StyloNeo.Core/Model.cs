using System.Text.Json.Serialization;

namespace StyloNeo.Core;

/// <summary>One stroke: from pen down to pen up. Points = [x, y, pressure 0..1, timestamp ms].</summary>
public sealed class InkStroke
{
    [JsonPropertyName("start")] public long Start { get; set; }
    [JsonPropertyName("end")] public long End { get; set; }
    [JsonPropertyName("color")] public int Color { get; set; }
    [JsonPropertyName("points")] public List<double[]> Points { get; set; } = new();

    /// <summary>Identity of a stroke: used to never add it twice to a page (also the input of the page hash).</summary>
    [JsonIgnore] public string Key => $"{Start}-{End}-{Points.Count}";
}

/// <summary>A page of an Ncode notebook: section, owner and notebook identify the notebook.</summary>
public sealed class NotePage
{
    [JsonPropertyName("section")] public int Section { get; set; }
    [JsonPropertyName("owner")] public int Owner { get; set; }
    [JsonPropertyName("notebook")] public int Notebook { get; set; }
    [JsonPropertyName("page")] public int Page { get; set; }
    [JsonPropertyName("strokes")] public List<InkStroke> Strokes { get; set; } = new();

    [JsonIgnore] public string NotebookId => $"{Section}-{Owner}-{Notebook}";
    [JsonIgnore] public string Key => $"{NotebookId}/p{Page:D3}";
}

/// <summary>A stroke received from the pen, with the address of its page.</summary>
public sealed record ReceivedStroke(int Section, int Owner, int Notebook, int Page, InkStroke Stroke);

/// <summary>Journal entry: what was downloaded, and what the downstream conversion has already processed.</summary>
public sealed class JournalEntry
{
    [JsonPropertyName("key")] public string Key { get; set; } = "";
    [JsonPropertyName("json")] public string JsonFile { get; set; } = "";
    [JsonPropertyName("svg")] public string SvgFile { get; set; } = "";
    [JsonPropertyName("png")] public string PngFile { get; set; } = "";
    [JsonPropertyName("strokes")] public int StrokeCount { get; set; }
    [JsonPropertyName("firstStroke")] public DateTimeOffset? FirstStroke { get; set; }
    [JsonPropertyName("lastStroke")] public DateTimeOffset? LastStroke { get; set; }
    [JsonPropertyName("updated")] public DateTimeOffset Updated { get; set; }
    [JsonPropertyName("hash")] public string Hash { get; set; } = "";
    [JsonPropertyName("doneHash")] public string? DoneHash { get; set; }

    [JsonIgnore] public bool IsPending => Hash != DoneHash;
    [JsonIgnore] public string State => DoneHash is null ? "new" : IsPending ? "modified" : "done";
    /// <summary>State for display, in the language of the messages.</summary>
    [JsonIgnore] public string StateLabel => DoneHash is null ? L.T("new", "nouvelle") : IsPending ? L.T("modified", "modifiée") : L.T("done", "traitée");
}

public sealed class Journal
{
    [JsonPropertyName("pages")] public SortedDictionary<string, JournalEntry> Pages { get; set; } = new();
}

public sealed record MergeResult(int NewPages, int ModifiedPages, int StrokesAdded, int StrokesAlreadyKnown);
