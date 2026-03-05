using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class AiService
    {
        private readonly HttpClient _httpClient;
        private readonly SettingsService _settingsService;

        public AiService(HttpClient? httpClient = null, SettingsService? settingsService = null)
        {
            _httpClient = httpClient ?? new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(20)
            };
            _settingsService = settingsService ?? new SettingsService();
        }

        public async Task<string> AskAsync(string question, SystemMetricsSnapshot snapshot, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(question))
            {
                return "Please enter a question.";
            }

            var settings = await _settingsService.LoadAsync().ConfigureAwait(false);
            string endpoint = Environment.GetEnvironmentVariable("NEOOPTIMIZE_GPT4ALL_URL") ?? "http://127.0.0.1:4891/v1/chat/completions";

            var payload = new
            {
                model = settings.Gpt4AllModel,
                messages = new object[]
                {
                    new { role = "system", content = BuildSystemPrompt(snapshot) },
                    new { role = "user", content = question }
                },
                temperature = 0.2,
                max_tokens = 280
            };

            try
            {
                string body = JsonSerializer.Serialize(payload);
                using var request = new HttpRequestMessage(HttpMethod.Post, endpoint)
                {
                    Content = new StringContent(body, Encoding.UTF8, "application/json")
                };

                using var response = await _httpClient.SendAsync(request, cancellationToken).ConfigureAwait(false);
                response.EnsureSuccessStatusCode();

                string responseBody = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
                string parsed = ParseAssistantMessage(responseBody);
                if (!string.IsNullOrWhiteSpace(parsed))
                {
                    return parsed.Trim();
                }
            }
            catch
            {
            }

            return BuildFallbackAdvice(question, snapshot);
        }

        private static string ParseAssistantMessage(string json)
        {
            try
            {
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                if (root.TryGetProperty("choices", out var choices) &&
                    choices.ValueKind == JsonValueKind.Array &&
                    choices.GetArrayLength() > 0)
                {
                    var first = choices[0];
                    if (first.TryGetProperty("message", out var messageObj) &&
                        messageObj.TryGetProperty("content", out var contentObj) &&
                        contentObj.ValueKind == JsonValueKind.String)
                    {
                        return contentObj.GetString() ?? string.Empty;
                    }

                    if (first.TryGetProperty("text", out var textObj) &&
                        textObj.ValueKind == JsonValueKind.String)
                    {
                        return textObj.GetString() ?? string.Empty;
                    }
                }

                if (root.TryGetProperty("response", out var responseObj) &&
                    responseObj.ValueKind == JsonValueKind.String)
                {
                    return responseObj.GetString() ?? string.Empty;
                }
            }
            catch
            {
            }

            return string.Empty;
        }

        private static string BuildSystemPrompt(SystemMetricsSnapshot snapshot)
        {
            return $"You are NeoAI (GPT4All) assistant for NeoOptimize. " +
                   $"Current system metrics: CPU {snapshot.CpuUsagePercent:0.0}%, RAM {snapshot.RamUsagePercent:0.0}%, " +
                   $"Disk C {snapshot.DiskUsagePercent:0.0}%, Latency {snapshot.LatencyMs:0.0}ms. " +
                   "Give concise and practical optimization advice for Windows.";
        }

        private static string BuildFallbackAdvice(string question, SystemMetricsSnapshot snapshot)
        {
            var sb = new StringBuilder();
            sb.AppendLine("NeoAI local fallback response:");

            bool any = false;
            if (snapshot.DiskUsagePercent >= 85)
            {
                sb.AppendLine("- Disk C is high. Run Cleaner (temp, browser cache, recycle bin) now.");
                any = true;
            }
            if (snapshot.RamUsagePercent >= 80)
            {
                sb.AppendLine("- RAM usage is high. Disable unnecessary startup/background apps from App Manager.");
                any = true;
            }
            if (snapshot.CpuUsagePercent >= 80)
            {
                sb.AppendLine("- CPU usage is high. Stop heavy background tasks, then run Optimizer.");
                any = true;
            }
            if (snapshot.LatencyMs >= 120)
            {
                sb.AppendLine("- Network latency is high. Run DNS flush and Winsock reset from Optimizer.");
                any = true;
            }

            string q = question.ToLowerInvariant();
            if (q.Contains("clean"))
            {
                sb.AppendLine("- Suggested flow: Analyze -> review categories -> Clean Now.");
                any = true;
            }
            if (q.Contains("startup") || q.Contains("boot"))
            {
                sb.AppendLine("- Suggested flow: disable non-essential startup items and enable startup delay.");
                any = true;
            }
            if (q.Contains("virus") || q.Contains("scan") || q.Contains("security"))
            {
                sb.AppendLine("- Suggested flow: Quick Scan first, then Full Scan for deeper check.");
                any = true;
            }

            if (!any)
            {
                sb.AppendLine("- Run Cleaner dry-run and Optimizer baseline, then check Scheduler recommended mode.");
            }

            sb.AppendLine("- GPT4All endpoint not reachable. Set NEOOPTIMIZE_GPT4ALL_URL if using custom local endpoint.");
            return sb.ToString().Trim();
        }
    }
}
