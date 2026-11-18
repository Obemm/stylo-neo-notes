using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Text;

namespace StyloNeo.Core;

/// <summary>Page rendering: vector SVG (for notes) and PNG (for reading by an AI model).</summary>
public static class Renderer
{
    /// <summary>One Ncode unit = 56/600 inch ≈ 2.37 mm.</summary>
    public const double MmPerUnit = 56.0 / 600.0 * 25.4;
    public const double PixelsPerUnit = 20;   // ≈ 214 dpi: sharp enough to read handwriting
    private const double Margin = 2;
    private const string Ink = "#1a1a2e";

    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static (double X, double Y, double W, double H) Bounds(NotePage page)
    {
        var pts = page.Strokes.SelectMany(t => t.Points).ToList();
        if (pts.Count == 0) return (0, 0, 10, 10);
        double minX = Math.Max(0, pts.Min(p => p[0]) - Margin), minY = Math.Max(0, pts.Min(p => p[1]) - Margin);
        double maxX = pts.Max(p => p[0]) + Margin, maxY = pts.Max(p => p[1]) + Margin;
        return (minX, minY, maxX - minX, maxY - minY);
    }

    /// <summary>Stroke width in Ncode units from pressure (0..1): about 0.3 to 0.7 mm.</summary>
    public static double Width(double pressure) => 0.12 + 0.18 * Math.Clamp(pressure, 0, 1);

    private static double AveragePressure(InkStroke t) => t.Points.Count == 0 ? 0.5 : t.Points.Average(p => p[2]);

    public static string Svg(NotePage page)
    {
        var (x, y, w, h) = Bounds(page);
        var sb = new StringBuilder();
        sb.Append(Inv, $"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"{x:0.##} {y:0.##} {w:0.##} {h:0.##}\" ");
        sb.Append(Inv, $"width=\"{w * MmPerUnit:0.#}mm\" height=\"{h * MmPerUnit:0.#}mm\">\n");
        sb.Append($"<title>Notebook {page.NotebookId}, page {page.Page}</title>\n");
        sb.Append(Inv, $"<rect x=\"{x:0.##}\" y=\"{y:0.##}\" width=\"{w:0.##}\" height=\"{h:0.##}\" fill=\"#fff\"/>\n");
        sb.Append($"<g fill=\"none\" stroke=\"{Ink}\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\n");
        foreach (var t in page.Strokes)
        {
            sb.Append(Inv, $"<path stroke-width=\"{Width(AveragePressure(t)):0.###}\" d=\"{PathData(t.Points)}\"/>\n");
        }
        sb.Append("</g>\n</svg>\n");
        return sb.ToString();
    }

    /// <summary>Smoothed curve: quadratics through the midpoints of the segments.</summary>
    public static string PathData(IReadOnlyList<double[]> p)
    {
        var sb = new StringBuilder();
        sb.Append(Inv, $"M{p[0][0]:0.##} {p[0][1]:0.##}");
        if (p.Count == 1) { sb.Append(Inv, $"l0.01 0"); return sb.ToString(); }
        for (int i = 1; i < p.Count - 1; i++)
        {
            double mx = (p[i][0] + p[i + 1][0]) / 2, my = (p[i][1] + p[i + 1][1]) / 2;
            sb.Append(Inv, $"Q{p[i][0]:0.##} {p[i][1]:0.##} {mx:0.##} {my:0.##}");
        }
        sb.Append(Inv, $"L{p[^1][0]:0.##} {p[^1][1]:0.##}");
        return sb.ToString();
    }

    public static void Png(NotePage page, string path)
    {
        var (x, y, w, h) = Bounds(page);
        int wp = Math.Max(1, (int)Math.Ceiling(w * PixelsPerUnit));
        int hp = Math.Max(1, (int)Math.Ceiling(h * PixelsPerUnit));
        using var bmp = new Bitmap(wp, hp, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Color.White);
            var ink = ColorTranslator.FromHtml(Ink);
            foreach (var t in page.Strokes)
            {
                using var pen = new Pen(ink, (float)(Width(AveragePressure(t)) * PixelsPerUnit))
                {
                    StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round,
                };
                var pts = t.Points
                    .Select(p => new PointF((float)((p[0] - x) * PixelsPerUnit), (float)((p[1] - y) * PixelsPerUnit)))
                    .ToArray();
                if (pts.Length == 1) g.DrawLine(pen, pts[0], new PointF(pts[0].X + 0.5f, pts[0].Y));
                else g.DrawLines(pen, pts);
            }
        }
        bmp.Save(path, ImageFormat.Png);
    }
}
