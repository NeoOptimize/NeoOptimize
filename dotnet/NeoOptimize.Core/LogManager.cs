using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.Core
{
    public class LogFileInfo
    {
        public string Path { get; set; }
        public long Size { get; set; }
        public DateTime LastModified { get; set; }
        public string DisplayName => System.IO.Path.GetFileName(Path);
    }

    public static class LogManager
    {
        private static readonly string LogDir = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Logs");
        private static readonly long MaxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
        private static readonly int RetentionDays = 30;
        private static readonly SemaphoreSlim _writeLock = new SemaphoreSlim(1, 1);

        static LogManager()
        {
            try
            {
                if (!Directory.Exists(LogDir))
                    Directory.CreateDirectory(LogDir);
            }
            catch { }
        }

        private static string GetLogFilePath(DateTime when)
        {
            string fileName = $"report-{when:dd-MM-yyyy}.html";
            return Path.Combine(LogDir, fileName);
        }

        private static async Task EnsureHeaderIfNewAsync(string path)
        {
            if (!File.Exists(path) || new FileInfo(path).Length == 0)
            {
                var header = new StringBuilder();
                header.AppendLine("<html><head><meta charset=\"utf-8\"/><title>NeoOptimize Report</title>");
                header.AppendLine("<style>body{font-family:Segoe UI,system-ui; background:#121217;color:#fff;} p{margin:6px 0;font-size:13px;} .meta{color:#bdbdbd;font-size:12px;}</style>");
                header.AppendLine("</head><body>");
                header.AppendLine($"<h2>NeoOptimize Report - {DateTime.Now:dd MMM yyyy}</h2>");
                await File.WriteAllTextAsync(path, header.ToString(), Encoding.UTF8).ConfigureAwait(false);
            }
        }

        private static async Task AppendRawAsync(string path, string content)
        {
            await _writeLock.WaitAsync().ConfigureAwait(false);
            try
            {
                using (var fs = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.Read, 4096, useAsync: true))
                using (var sw = new StreamWriter(fs, Encoding.UTF8))
                {
                    await sw.WriteLineAsync(content).ConfigureAwait(false);
                }
            }
            finally
            {
                _writeLock.Release();
            }
        }

        public static async Task AppendAsync(string message)
        {
            var now = DateTime.Now;
            var path = GetLogFilePath(now);
            await EnsureHeaderIfNewAsync(path).ConfigureAwait(false);

            string entry = $"<p>[{now:HH:mm:ss}] {System.Web.HttpUtility.HtmlEncode(message)}</p>";
            await AppendRawAsync(path, entry).ConfigureAwait(false);

            await RotateIfNeededAsync(path).ConfigureAwait(false);
            await PurgeOldLogsAsync().ConfigureAwait(false);
        }

        private static async Task RotateIfNeededAsync(string currentPath)
        {
            try
            {
                var fi = new FileInfo(currentPath);
                if (fi.Exists && fi.Length > MaxFileSizeBytes)
                {
                    string rotatedName = Path.Combine(LogDir, $"report-{DateTime.Now:dd-MM-yyyy}_{DateTime.Now:HHmmss}.html");
                    await Task.Run(() => File.Move(currentPath, rotatedName)).ConfigureAwait(false);
                    await EnsureHeaderIfNewAsync(currentPath).ConfigureAwait(false);
                }
            }
            catch { }
        }

        private static async Task PurgeOldLogsAsync()
        {
            try
            {
                var files = Directory.GetFiles(LogDir, "report-*.html");
                var cutoff = DateTime.Now.AddDays(-RetentionDays);
                foreach (var f in files)
                {
                    try
                    {
                        var fi = new FileInfo(f);
                        if (fi.LastWriteTime < cutoff)
                            await Task.Run(() => fi.Delete()).ConfigureAwait(false);
                    }
                    catch { }
                }
            }
            catch { }
        }

        public static IEnumerable<LogFileInfo> GetAllLogs()
        {
            try
            {
                if (!Directory.Exists(LogDir))
                    return Enumerable.Empty<LogFileInfo>();

                return Directory.GetFiles(LogDir, "report-*.html")
                    .Select(p => new LogFileInfo
                    {
                        Path = p,
                        Size = new FileInfo(p).Length,
                        LastModified = File.GetLastWriteTime(p)
                    })
                    .OrderByDescending(x => x.LastModified)
                    .ToList();
            }
            catch
            {
                return Enumerable.Empty<LogFileInfo>();
            }
        }

        public static void DeleteLog(string filePath)
        {
            try
            {
                if (File.Exists(filePath))
                    File.Delete(filePath);
            }
            catch { }
        }

        public static bool ExportLog(string filePath, string destinationZipPath)
        {
            try
            {
                if (!File.Exists(filePath))
                    return false;

                using (var zip = System.IO.Compression.ZipFile.Open(destinationZipPath, System.IO.Compression.ZipArchiveMode.Create))
                {
                    var entryName = System.IO.Path.GetFileName(filePath);
                    zip.CreateEntryFromFile(filePath, entryName);
                }
                return true;
            }
            catch { return false; }
        }
    }
}
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
