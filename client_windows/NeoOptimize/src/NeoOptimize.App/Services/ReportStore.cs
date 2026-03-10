using System.IO;
using System.Diagnostics;
using System.Globalization;
using Microsoft.Extensions.Options;
using NeoOptimize.App.Models;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.App.Services;

public sealed class ReportStore
{
    private readonly string _reportsFolder;

    public ReportStore(IOptions<NeoOptimizeClientOptions> options)
    {
        _reportsFolder = options.Value.ReportsRootPath;
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
        var baseName = $"report-{timestamp:dd-MM-yyyy}.html";
        var fileName = baseName;
        var fullPath = Path.Combine(_reportsFolder, fileName);
        if (File.Exists(fullPath))
        {
            fileName = $"report-{timestamp:dd-MM-yyyy}-{timestamp:HHmmss}.html";
            fullPath = Path.Combine(_reportsFolder, fileName);
        }
        var details = detailLines.Select(line => System.Net.WebUtility.HtmlEncode(line)).ToList();
        var safeTitle = System.Net.WebUtility.HtmlEncode(title);
        var safeSummary = System.Net.WebUtility.HtmlEncode(summary);
        var detailItems = string.Join(Environment.NewLine, details.Select(item => $"<li>{item}</li>"));
        var html = $@"<!DOCTYPE html>
<html lang='en'>
<head>
  <meta charset='UTF-8' />
  <meta name='viewport' content='width=device-width, initial-scale=1.0' />
  <title>{safeTitle}</title>
  <style>
    :root {{
      color-scheme: light dark;
    }}
    body {{ font-family: 'Segoe UI', sans-serif; background: #07101d; color: #edf4ff; padding: 32px; }}
    main {{ max-width: 880px; margin: 0 auto; background: #10203a; border-radius: 24px; padding: 32px; }}
    h1 {{ margin-top: 0; }}
    .meta {{ color: #8aa5c8; margin-bottom: 24px; }}
    ul {{ margin: 0 0 24px 18px; }}
    li {{ margin-bottom: 6px; }}
    .summary {{ margin-bottom: 16px; }}
    .footer {{ margin-top: 28px; padding-top: 16px; border-top: 1px solid rgba(255,255,255,0.1); }}
    .footer h3 {{ margin: 0 0 8px 0; }}
    .footer a {{ color: inherit; text-decoration: none; }}
    .footer a:hover {{ text-decoration: underline; }}
    @media (prefers-color-scheme: light) {{
      body {{ background: #ffffff; color: #0f172a; }}
      main {{ background: #ffffff; border: 1px solid #e5e7eb; }}
      .meta {{ color: #475569; }}
      .footer {{ border-top: 1px solid #e5e7eb; }}
    }}
  </style>
</head>
<body>
  <main>
    <p class='meta'>NeoOptimize report - {timestamp:dd MMM yyyy HH:mm:ss}</p>
    <h1>{safeTitle}</h1>
    <p class='summary'>{safeSummary}</p>
    <ul>{detailItems}</ul>
    <div class='footer'>
      <h3>Kontak Developer: Sigit profesional IT</h3>
      <p>WhatsApp: 087889911030<br/>Email: neooptimizeofficial@gmail.com</p>
      <h3>Support</h3>
      <p>
        <a href='https://buymeacoffee.com/nol.eight'>BuyMeACoffee</a><br/>
        <a href='https://saweria.co/dtechtive'>Saweria</a><br/>
        <a href='https://ik.imagekit.io/dtechtive/Dana'>Dana</a>
      </p>
    </div>
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

