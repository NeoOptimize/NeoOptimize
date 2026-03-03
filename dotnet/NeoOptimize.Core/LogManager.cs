using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Text;
using System.Diagnostics;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class LogManager
{
    private readonly object _sync = new();
    private readonly string _reportDirectory;
    private readonly List<LogEntry> _entries = new();

    public LogManager(string? reportDirectory = null)
    {
        _reportDirectory = reportDirectory ??
                           Path.Combine(
                               Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                               "NeoOptimize",
                               "reports");

        Directory.CreateDirectory(_reportDirectory);
    }

    public string CurrentReportPath =>
        Path.Combine(_reportDirectory, $"report-{DateTime.Now:yyyy-MM-dd}.html");

    public LogEntry Append(string module, string action, OperationResult result)
    {
        var entry = new LogEntry(
            DateTimeOffset.Now,
            module,
            action,
            result.Success ? "ok" : "error",
            result.Message,
            result.Metrics);

        lock (_sync)
        {
            _entries.Add(entry);
            WriteHtmlReport();
        }

        return entry;
    }

    public IReadOnlyList<LogEntry> ReadRecent(int take = 150)
    {
        lock (_sync)
        {
            return _entries.TakeLast(Math.Max(1, take)).ToList();
        }
    }

    private void WriteHtmlReport()
    {
        var sb = new StringBuilder();
        sb.AppendLine("<!DOCTYPE html>");
        sb.AppendLine("<html><head><meta charset=\"utf-8\" /><title>NeoOptimize Report</title>");
        sb.AppendLine("<style>");
        sb.AppendLine("body{font-family:Segoe UI,Arial,sans-serif;background:#0a101a;color:#f4f7fb;padding:20px}");
        sb.AppendLine("table{width:100%;border-collapse:collapse}");
        sb.AppendLine("th,td{border:1px solid #2a3b52;padding:8px;text-align:left;vertical-align:top}");
        sb.AppendLine("th{background:#111c2b}");
        sb.AppendLine("</style></head><body>");
        sb.AppendLine($"<h2>NeoOptimize Report - {DateTime.Now:dd-MM-yyyy}</h2>");
        sb.AppendLine("<table>");
        sb.AppendLine("<thead><tr><th>Time</th><th>Module</th><th>Action</th><th>Result</th><th>Message</th><th>Metrics</th></tr></thead>");
        sb.AppendLine("<tbody>");

        foreach (var entry in _entries)
        {
            var metrics = entry.Metrics is { Count: > 0 }
                ? string.Join(", ", entry.Metrics.Select(kv => $"{WebUtility.HtmlEncode(kv.Key)}={WebUtility.HtmlEncode(kv.Value)}"))
                : "-";

            sb.AppendLine("<tr>");
            sb.AppendLine($"<td>{WebUtility.HtmlEncode(entry.Timestamp.ToString("u"))}</td>");
            sb.AppendLine($"<td>{WebUtility.HtmlEncode(entry.Module)}</td>");
            sb.AppendLine($"<td>{WebUtility.HtmlEncode(entry.Action)}</td>");
            sb.AppendLine($"<td>{WebUtility.HtmlEncode(entry.Result)}</td>");
            sb.AppendLine($"<td>{WebUtility.HtmlEncode(entry.Message)}</td>");
            sb.AppendLine($"<td>{metrics}</td>");
            sb.AppendLine("</tr>");
        }

        sb.AppendLine("</tbody></table></body></html>");

        try
        {
            File.WriteAllText(CurrentReportPath, sb.ToString(), Encoding.UTF8);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"NeoOptimize: failed to write HTML report to {CurrentReportPath}: {ex}");
        }
    }
}
