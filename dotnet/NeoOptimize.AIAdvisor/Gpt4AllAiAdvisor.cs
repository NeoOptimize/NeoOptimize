using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NeoOptimize.AIAdvisor.Models;

namespace NeoOptimize.AIAdvisor;

public sealed class Gpt4AllAiAdvisor : IAiAdvisor
{
    private readonly HttpClient _httpClient;
    private readonly string _endpoint;
    private readonly string _model;
    private readonly string _cliPath;
    private readonly string _cliArgsTemplate;

    public Gpt4AllAiAdvisor(
        string? endpoint = null,
        string? model = null,
        string? cliPath = null,
        string? cliArgsTemplate = null,
        HttpClient? httpClient = null)
    {
        _endpoint = string.IsNullOrWhiteSpace(endpoint)
            ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_ENDPOINT") ?? "http://127.0.0.1:4891/v1/chat/completions"
            : endpoint;

        _model = string.IsNullOrWhiteSpace(model)
            ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_MODEL") ?? "gpt4all"
            : model;

        _cliPath = string.IsNullOrWhiteSpace(cliPath)
            ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_CLI") ?? string.Empty
            : cliPath;

        _cliArgsTemplate = string.IsNullOrWhiteSpace(cliArgsTemplate)
            ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_CLI_ARGS") ?? "--model {model} --prompt {prompt}"
            : cliArgsTemplate;

        _httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(8)
        };
    }

    public async Task<AiAdviceResponse> GetAdviceAsync(AiAdviceRequest request, CancellationToken cancellationToken)
    {
        var prompt = BuildPrompt(request);

        var httpResult = await TryHttpAsync(prompt, cancellationToken).ConfigureAwait(false);
        if (httpResult.Success) return httpResult;

        var cliResult = await TryCliAsync(prompt, cancellationToken).ConfigureAwait(false);
        if (cliResult.Success) return cliResult;

        return new AiAdviceResponse(
            Success: false,
            Provider: "GPT4All",
            Recommendation: "GPT4All runtime not available. Set local API endpoint or CLI path via NEO_GPT4ALL_* env vars.",
            GeneratedAt: DateTimeOffset.Now);
    }

    private async Task<AiAdviceResponse> TryHttpAsync(string prompt, CancellationToken cancellationToken)
    {
        try
        {
            var payload = new
            {
                model = _model,
                messages = new[]
                {
                    new
                    {
                        role = "system",
                        content = "You are NeoOptimize AI advisor. Give concise optimization recommendations. Never execute actions."
                    },
                    new
                    {
                        role = "user",
                        content = prompt
                    }
                },
                max_tokens = 220,
                temperature = 0.2
            };

            using var response = await _httpClient.PostAsJsonAsync(_endpoint, payload, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return new AiAdviceResponse(
                    false,
                    "GPT4All",
                    $"GPT4All HTTP unavailable ({(int)response.StatusCode}).",
                    DateTimeOffset.Now);
            }

            using var content = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(content, cancellationToken: cancellationToken).ConfigureAwait(false);

            if (!document.RootElement.TryGetProperty("choices", out var choices) ||
                choices.GetArrayLength() == 0)
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All HTTP response has no choices.", DateTimeOffset.Now);
            }

            var first = choices[0];
            if (!first.TryGetProperty("message", out var messageNode) ||
                !messageNode.TryGetProperty("content", out var contentNode))
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All HTTP response missing message content.", DateTimeOffset.Now);
            }

            var text = contentNode.GetString();
            if (string.IsNullOrWhiteSpace(text))
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All returned empty recommendation.", DateTimeOffset.Now);
            }

            return new AiAdviceResponse(
                true,
                "GPT4All",
                text.Trim(),
                DateTimeOffset.Now);
        }
        catch
        {
            return new AiAdviceResponse(false, "GPT4All", "GPT4All HTTP adapter failed.", DateTimeOffset.Now);
        }
    }

    private async Task<AiAdviceResponse> TryCliAsync(string prompt, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_cliPath) || !File.Exists(_cliPath))
        {
            return new AiAdviceResponse(false, "GPT4All", "GPT4All CLI path is not set.", DateTimeOffset.Now);
        }

        var arguments = _cliArgsTemplate
            .Replace("{model}", Quote(_model), StringComparison.OrdinalIgnoreCase)
            .Replace("{prompt}", Quote(prompt), StringComparison.OrdinalIgnoreCase);

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = _cliPath,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try
        {
            process.Start();
            using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            linkedCts.CancelAfter(TimeSpan.FromSeconds(12));

            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            await process.WaitForExitAsync(linkedCts.Token).ConfigureAwait(false);

            var stdout = (await outputTask.ConfigureAwait(false)).Trim();
            var stderr = (await errorTask.ConfigureAwait(false)).Trim();

            if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(stdout))
            {
                return new AiAdviceResponse(true, "GPT4All", stdout, DateTimeOffset.Now);
            }

            var reason = string.IsNullOrWhiteSpace(stderr)
                ? $"GPT4All CLI exited with code {process.ExitCode}."
                : stderr;

            return new AiAdviceResponse(false, "GPT4All", reason, DateTimeOffset.Now);
        }
        catch (OperationCanceledException)
        {
            try
            {
                if (!process.HasExited) process.Kill(true);
            }
            catch
            {
            }

            return new AiAdviceResponse(false, "GPT4All", "GPT4All CLI timeout.", DateTimeOffset.Now);
        }
        catch (Exception ex)
        {
            return new AiAdviceResponse(false, "GPT4All", ex.Message, DateTimeOffset.Now);
        }
    }

    private static string BuildPrompt(AiAdviceRequest request)
    {
        return
            $"Mode={request.ExperienceMode}; Language={request.Language}; " +
            $"CPU={request.Snapshot.CpuUsagePercent:F1}%; RAM={request.Snapshot.MemoryUsagePercent:F1}%; " +
            $"Disk={request.Snapshot.DiskUsagePercent:F1}%; Network={request.Snapshot.NetworkUsageMbps:F1} Mbps. " +
            $"Recent logs: {string.Join(" || ", request.RecentLogs ?? Array.Empty<string>())}. " +
            "Give 3 concise recommendations and mention if scheduler should be adjusted.";
    }

    private static string Quote(string value)
    {
        var escaped = value.Replace("\"", "\\\"", StringComparison.Ordinal);
        return $"\"{escaped}\"";
    }
}
