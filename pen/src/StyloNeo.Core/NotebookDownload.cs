namespace StyloNeo.Core;

/// <summary>Outcome of downloading one notebook.</summary>
public enum NotebookState
{
    /// <summary>The pen signalled the end of the transfer.</summary>
    Complete,
    /// <summary>All announced strokes arrived, but the pen did not signal the end.</summary>
    EndNotConfirmed,
    /// <summary>Part of the strokes arrived, then nothing.</summary>
    Incomplete,
    /// <summary>The pen accepted the request but sent nothing.</summary>
    NothingReceived,
    /// <summary>Not requested: the connection was lost before.</summary>
    NotAttempted,
}

public sealed record NotebookReport(string Notebook, NotebookState State, int Received, int Total)
{
    /// <summary>Only a notebook whose end the pen confirmed may be erased.</summary>
    public bool EraseAllowed => State == NotebookState.Complete;

    public string Label => State switch
    {
        NotebookState.Complete => L.T($"received ({Received} strokes)", $"reçu ({Received} traits)"),
        NotebookState.EndNotConfirmed => L.T($"received, end not confirmed by the pen ({Received}/{Total} strokes)",
                                             $"reçu, fin non confirmée par le stylo ({Received}/{Total} traits)"),
        NotebookState.Incomplete => L.T($"INCOMPLETE ({Received}/{Total} strokes kept)",
                                        $"INCOMPLET ({Received}/{Total} traits conservés)"),
        NotebookState.NothingReceived => L.T("nothing received", "rien reçu"),
        _ => L.T("not attempted (connection lost)", "non tenté (connexion perdue)"),
    };

    /// <summary>
    /// Classifies a download. <paramref name="endSignalled"/>: true if the pen signalled a successful end,
    /// false if it signalled a failure, null if it signalled nothing (timeout or disconnection).
    /// </summary>
    public static NotebookState Classify(bool? endSignalled, int received, int total)
    {
        if (endSignalled == true) return NotebookState.Complete;
        if (total > 0 && received >= total) return NotebookState.EndNotConfirmed;
        return received > 0 ? NotebookState.Incomplete : NotebookState.NothingReceived;
    }

    /// <summary>Parses a notebook id "section-owner-notebook", e.g. 3-27-738.</summary>
    public static bool TryParseId(string? text, out int section, out int owner, out int notebook)
    {
        section = owner = notebook = 0;
        var p = (text ?? "").Trim().Split('-');
        return p.Length == 3
            && int.TryParse(p[0], out section)
            && int.TryParse(p[1], out owner)
            && int.TryParse(p[2], out notebook);
    }
}
