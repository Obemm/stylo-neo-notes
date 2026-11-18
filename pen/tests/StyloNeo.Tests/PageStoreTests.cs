using System.Drawing;
using System.Xml.Linq;
using StyloNeo.Core;

namespace StyloNeo.Tests;

public sealed class PageStoreTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "stylo-neo-tests", Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    /// <summary>Synthetic stroke: a line of 10 points starting at (x, y), timestamped.</summary>
    private static ReceivedStroke S(int page, long start, double x = 10, double y = 10, int notebook = 603) =>
        new(3, 27, notebook, page, new InkStroke
        {
            Start = start,
            End = start + 900,
            Points = Enumerable.Range(0, 10).Select(i => new[] { x + i * 0.8, y + Math.Sin(i) * 0.5, 0.6, start + i * 100.0 }).ToList(),
        });

    [Fact]
    public void A_new_page_produces_json_svg_png_and_a_pending_entry()
    {
        var d = new PageStore(_dir);
        var r = d.Merge(new[] { S(1, 1_700_000_000_000), S(1, 1_700_000_001_000, y: 14) });

        Assert.Equal(new MergeResult(1, 0, 2, 0), r);
        var e = Assert.Single(d.Pending());
        Assert.Equal("3-27-603/p001", e.Key);
        Assert.Equal("new", e.State);
        foreach (var f in new[] { e.JsonFile, e.SvgFile, e.PngFile })
            Assert.True(File.Exists(Path.Combine(_dir, f)), f);
    }

    [Fact]
    public void A_second_identical_sync_duplicates_nothing()
    {
        var d = new PageStore(_dir);
        var strokes = new[] { S(1, 1_000), S(2, 2_000) };
        d.Merge(strokes);
        var r = d.Merge(strokes);

        Assert.Equal(new MergeResult(0, 0, 0, 2), r);
        Assert.Single(d.ReadPage(3, 27, 603, 1)!.Strokes);
    }

    [Fact]
    public void A_completed_page_is_updated_and_becomes_pending_again()
    {
        var d = new PageStore(_dir);
        d.Merge(new[] { S(5, 1_000) });
        Assert.True(d.MarkDone("3-27-603/p005"));
        Assert.Empty(d.Pending());
        Assert.Equal("done", d.ReadJournal().Pages["3-27-603/p005"].State);

        var r = d.Merge(new[] { S(5, 1_000), S(5, 5_000, y: 20) });

        Assert.Equal(new MergeResult(0, 1, 1, 1), r);
        var e = Assert.Single(d.Pending());
        Assert.Equal("modified", e.State);
        Assert.Equal(2, e.StrokeCount);
    }

    [Fact]
    public void Strokes_are_filed_by_page_and_notebook_in_chronological_order()
    {
        var d = new PageStore(_dir);
        d.Merge(new[] { S(1, 9_000), S(1, 3_000), S(1, 4_000, notebook: 604) });

        var p = d.ReadPage(3, 27, 603, 1)!;
        Assert.Equal(new long[] { 3_000, 9_000 }, p.Strokes.Select(t => t.Start));
        Assert.Single(d.ReadPage(3, 27, 604, 1)!.Strokes);
        Assert.Equal(2, d.ReadJournal().Pages.Count);
    }

    [Fact]
    public void Marking_an_unknown_page_fails_cleanly()
    {
        Assert.False(new PageStore(_dir).MarkDone("1-2-3/p999"));
    }

    [Fact]
    public void The_svg_is_valid_and_has_one_path_per_stroke()
    {
        var page = new NotePage { Section = 3, Owner = 27, Notebook = 603, Page = 1 };
        page.Strokes.AddRange(new[] { S(1, 1_000).Stroke, S(1, 2_000, y: 15).Stroke, S(1, 3_000, y: 20).Stroke });

        var svg = XDocument.Parse(Renderer.Svg(page));
        XNamespace ns = "http://www.w3.org/2000/svg";
        Assert.Equal(3, svg.Descendants(ns + "path").Count());
        Assert.Contains("mm", svg.Root!.Attribute("width")!.Value);
    }

    [Fact]
    public void The_png_has_the_size_of_the_content_and_contains_ink()
    {
        var page = new NotePage { Section = 3, Owner = 27, Notebook = 603, Page = 1 };
        page.Strokes.Add(S(1, 1_000, x: 10, y: 10).Stroke);
        var f = Path.Combine(_dir, "test.png");
        Directory.CreateDirectory(_dir);

        Renderer.Png(page, f);

        using var img = new Bitmap(f);
        var (_, _, w, h) = Renderer.Bounds(page);
        Assert.Equal((int)Math.Ceiling(w * Renderer.PixelsPerUnit), img.Width);
        Assert.Equal((int)Math.Ceiling(h * Renderer.PixelsPerUnit), img.Height);
        bool ink = false;
        for (int x = 0; x < img.Width && !ink; x += 2)
            for (int y = 0; y < img.Height && !ink; y += 2)
                ink = img.GetPixel(x, y).GetBrightness() < 0.5f;
        Assert.True(ink, "no dark pixel in the PNG");
    }

    [Fact]
    public void A_single_point_stroke_renders_without_error()
    {
        var page = new NotePage { Page = 1 };
        page.Strokes.Add(new InkStroke { Start = 1, End = 1, Points = { new[] { 5.0, 5.0, 0.5, 1.0 } } });
        Assert.Contains("<path", Renderer.Svg(page));
        Renderer.Png(page, Path.Combine(Directory.CreateDirectory(_dir).FullName, "point.png"));
    }
}
