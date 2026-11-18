using StyloNeo.Core;

namespace StyloNeo.Tests;

/// <summary>Classification of a download and resumption of a partial notebook.</summary>
public sealed class NotebookDownloadTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "stylo-neo-tests", Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    private static ReceivedStroke S(int page, long start) =>
        new(3, 27, 551, page, new InkStroke
        {
            Start = start,
            End = start + 900,
            Points = Enumerable.Range(0, 5).Select(i => new[] { 10 + i * 0.8, 10.0, 0.6, start + i * 100.0 }).ToList(),
        });

    [Theory]
    [InlineData(true, 544, 544, NotebookState.Complete)]
    [InlineData(null, 544, 544, NotebookState.EndNotConfirmed)]   // everything received, no end marker
    [InlineData(false, 544, 544, NotebookState.EndNotConfirmed)]
    [InlineData(null, 200, 544, NotebookState.Incomplete)]
    [InlineData(false, 200, 544, NotebookState.Incomplete)]
    [InlineData(null, 0, 0, NotebookState.NothingReceived)]
    public void A_download_is_classified_by_end_marker_and_count(bool? end, int received, int total, NotebookState expected) =>
        Assert.Equal(expected, NotebookReport.Classify(end, received, total));

    [Fact]
    public void Only_a_notebook_confirmed_by_the_pen_may_be_erased()
    {
        Assert.True(new NotebookReport("3-27-551", NotebookState.Complete, 544, 544).EraseAllowed);
        foreach (var e in new[] { NotebookState.EndNotConfirmed, NotebookState.Incomplete, NotebookState.NothingReceived, NotebookState.NotAttempted })
            Assert.False(new NotebookReport("3-27-551", e, 1, 2).EraseAllowed);
    }

    [Theory]
    [InlineData("3-27-738", true, 3, 27, 738)]
    [InlineData(" 3-27-551 ", true, 3, 27, 551)]
    [InlineData("3-27", false, 0, 0, 0)]
    [InlineData("a-b-c", false, 0, 0, 0)]
    [InlineData(null, false, 0, 0, 0)]
    public void A_notebook_id_parses_as_section_owner_notebook(string? text, bool ok, int s, int o, int n)
    {
        Assert.Equal(ok, NotebookReport.TryParseId(text, out var s2, out var o2, out var n2));
        if (ok) Assert.Equal((s, o, n), (s2, o2, n2));
    }

    [Fact]
    public void A_partial_notebook_is_kept_then_completed_without_duplicates()
    {
        var d = new PageStore(_dir);
        var all = new[] { S(1, 1_000), S(1, 2_000), S(2, 3_000), S(2, 4_000) };

        var partial = d.Merge(all.Take(3));   // transfer interrupted after 3 strokes
        Assert.Equal(new MergeResult(2, 0, 3, 0), partial);

        var complete = d.Merge(all);          // next sync, whole notebook
        Assert.Equal(new MergeResult(0, 1, 1, 3), complete);
        Assert.Equal(2, d.ReadPage(3, 27, 551, 2)!.Strokes.Count);
    }
}
