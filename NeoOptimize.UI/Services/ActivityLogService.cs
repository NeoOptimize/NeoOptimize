using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class ActivityLogService
    {
        public string LogsRootPath
        {
            get
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                return Path.Combine(appData, "NeoOptimize", "Logs");
            }
        }

        public string LogFilePath => Path.Combine(LogsRootPath, "neooptimize.log");

        public async Task<string> AppendEngineEventAsync(string engineJson)
        {
            string module = "engine";
            string message = engineJson;

            try
            {
                using var doc = JsonDocument.Parse(engineJson);
                var root = doc.RootElement;
                if (root.TryGetProperty("module", out var moduleElement) && moduleElement.ValueKind == JsonValueKind.String)
                {
                    module = moduleElement.GetString() ?? module;
                }
                if (root.TryGetProperty("message", out var messageElement) && messageElement.ValueKind == JsonValueKind.String)
                {
                    message = messageElement.GetString() ?? message;
                }
            }
            catch
            {
            }

            return await AppendCustomEventAsync(module, message).ConfigureAwait(false);
        }

        public async Task<string> AppendCustomEventAsync(string module, string message)
        {
            Directory.CreateDirectory(LogsRootPath);
            string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\t[{module}]\t{message}";
            await File.AppendAllTextAsync(LogFilePath, line + Environment.NewLine, Encoding.UTF8).ConfigureAwait(false);
            return line;
        }

        public async Task<IReadOnlyList<string>> ReadRecentLinesAsync(int maxLines = 250)
        {
            try
            {
                if (!File.Exists(LogFilePath))
                {
                    return Array.Empty<string>();
                }

                string[] lines = await File.ReadAllLinesAsync(LogFilePath).ConfigureAwait(false);
                if (lines.Length <= maxLines)
                {
                    return lines;
                }

                return lines.Skip(lines.Length - maxLines).ToArray();
            }
            catch
            {
                return Array.Empty<string>();
            }
        }

        public async Task<string> GenerateHtmlReportAsync(IReadOnlyCollection<string> lines)
        {
            Directory.CreateDirectory(LogsRootPath);
            string reportPath = Path.Combine(LogsRootPath, $"report_{DateTime.Now:yyyyMMdd_HHmmss}.html");

            var sb = new StringBuilder();
            sb.AppendLine("<!DOCTYPE html>");
            sb.AppendLine("<html lang=\"en\">");
            sb.AppendLine("<head>");
            sb.AppendLine("<meta charset=\"utf-8\" />");
            sb.AppendLine("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />");
            sb.AppendLine("<title>NeoOptimize Activity Report</title>");
            sb.AppendLine("<style>");
            sb.AppendLine("body{font-family:Segoe UI,Arial,sans-serif;background:#0b1320;color:#d9e7ff;margin:0;padding:24px;}");
            sb.AppendLine(".card{background:#101a2b;border:1px solid #2a3b58;border-radius:12px;padding:16px;}");
            sb.AppendLine("h1{margin:0 0 8px 0;font-size:24px;color:#8bd5ff;}");
            sb.AppendLine("p{margin:0 0 16px 0;color:#9eb3d1;}");
            sb.AppendLine("table{width:100%;border-collapse:collapse;}");
            sb.AppendLine("th,td{border-bottom:1px solid #22324c;padding:8px;text-align:left;font-size:13px;}");
            sb.AppendLine("th{color:#8bd5ff;}");
            sb.AppendLine("</style>");
            sb.AppendLine("</head>");
            sb.AppendLine("<body>");
            sb.AppendLine("<div class=\"card\">");
            sb.AppendLine("<h1>NeoOptimize Activity Report</h1>");
            sb.AppendLine($"<p>Generated: {EscapeHtml(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss"))}</p>");
            sb.AppendLine("<table>");
            sb.AppendLine("<thead><tr><th>#</th><th>Entry</th></tr></thead>");
            sb.AppendLine("<tbody>");

            int index = 1;
            foreach (var line in lines)
            {
                sb.AppendLine($"<tr><td>{index}</td><td>{EscapeHtml(line)}</td></tr>");
                index++;
            }

            sb.AppendLine("</tbody>");
            sb.AppendLine("</table>");
            sb.AppendLine("</div>");
            sb.AppendLine("</body>");
            sb.AppendLine("</html>");

            await File.WriteAllTextAsync(reportPath, sb.ToString(), Encoding.UTF8).ConfigureAwait(false);
            return reportPath;
        }

        private static string EscapeHtml(string value)
        {
            if (string.IsNullOrEmpty(value))
            {
                return string.Empty;
            }

            return value
                .Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;")
                .Replace("'", "&#39;");
        }
    }
}
