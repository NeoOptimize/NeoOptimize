using System.Diagnostics;
using System.IO;
using System.Globalization;
using NeoOptimize.App.Models;

namespace NeoOptimize.App.Services;

public sealed class ReportStore
{
    private readonly string _reportsFolder = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "NeoOptimize",
        "reports");

    public ReportStore()
    {
        Directory.CreateDirectory(_reportsFolder);
    }

    public IReadOnlyList<UiReportRecord> ListReports()
    {
        return Directory.EnumerateFiles(_reportsFolder, "*.html")
            .Select(path => new FileInfo(path))
            .OrderByDescending(info => info.CreationTimeUtc)
            .Select(info => new UiReportRecord
            {
                FileName = info.Name,
                Title = Path.GetFileNameWithoutExtension(info.Name).Replace('-', ' '),
                CreatedAt = info.CreationTime.ToString("dd MMM yyyy HH:mm", CultureInfo.InvariantCulture),
                SizeLabel = FormatBytes(info.Length),
            })
            .ToList();
    }

    public string CreateReport(string slug, string title, string summary, IEnumerable<string> detailLines)
    {
        var timestamp = DateTimeOffset.Now;
        var fileName = $"{slug}-{timestamp:yyyyMMdd-HHmmss}.html";
        var fullPath = Path.Combine(_reportsFolder, fileName);
        var details = string.Join(Environment.NewLine, detailLines);
        var html = $@"<!DOCTYPE html>
<html lang=""en"">
<head>
  <meta charset=""UTF-8"" />
  <title>{title}</title>
  <style>
    body {{ font-family: 'Segoe UI', sans-serif; background: #07101d; color: #edf4ff; padding: 32px; }}
    main {{ max-width: 840px; margin: 0 auto; background: #10203a; border-radius: 24px; padding: 32px; }}
    h1 {{ margin-top: 0; }}
    .meta {{ color: #8aa5c8; margin-bottom: 24px; }}
    pre {{ background: #091625; padding: 18px; border-radius: 16px; white-space: pre-wrap; word-break: break-word; }}
  </style>
</head>
<body>
  <main>
    <p class=""meta"">NeoOptimize report · {timestamp:dd MMM yyyy HH:mm:ss}</p>
    <h1>{title}</h1>
    <p>{summary}</p>
    <pre>{details}</pre>
  </main>
</body>
</html>";
        File.WriteAllText(fullPath, html);
        return fullPath;
    }

    public void OpenReport(string fileName)
    {
        var fullPath = BuildSafePath(fileName);
        if (!File.Exists(fullPath))
        {
            return;
        }

        Process.Start(new ProcessStartInfo(fullPath) { UseShellExecute = true });
    }

    public bool DeleteReport(string fileName)
    {
        var fullPath = BuildSafePath(fileName);
        if (!File.Exists(fullPath))
        {
            return false;
        }

        File.Delete(fullPath);
        return true;
    }

    private string BuildSafePath(string fileName)
    {
        return Path.Combine(_reportsFolder, Path.GetFileName(fileName));
    }

    private static string FormatBytes(long bytes)
    {
        string[] sizes = ["B", "KB", "MB", "GB"];
        double len = bytes;
        var order = 0;
        while (len >= 1024 && order < sizes.Length - 1)
        {
            order++;
            len /= 1024;
        }

        return $"{len:0.##} {sizes[order]}";
    }
}
