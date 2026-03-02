using System;
using System.Collections.Generic;
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
            ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_CLI_ARGS") ?? string.Empty
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

            if (!document.RootElement.TryGetProperty("choices", out var choices) || choices.GetArrayLength() == 0)
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All HTTP response has no choices.", DateTimeOffset.Now);
            }

            var first = choices[0];
            if (!first.TryGetProperty("message", out var messageNode) || !messageNode.TryGetProperty("content", out var contentNode))
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All HTTP response missing message content.", DateTimeOffset.Now);
            }

            var text = contentNode.GetString();
            if (string.IsNullOrWhiteSpace(text))
            {
                return new AiAdviceResponse(false, "GPT4All", "GPT4All returned empty recommendation.", DateTimeOffset.Now);
            }

            return new AiAdviceResponse(true, "GPT4All", text.Trim(), DateTimeOffset.Now);
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

        var exeName = Path.GetFileName(_cliPath);
        if (exeName.Contains("installer", StringComparison.OrdinalIgnoreCase))
        {
            return new AiAdviceResponse(
                false,
                "GPT4All",
                "GPT4All CLI path points to installer binary, not runtime executable.",
                DateTimeOffset.Now);
        }

        string? lastError = null;
        foreach (var args in BuildCliArgumentCandidates(prompt))
        {
            var run = await ExecuteCliOnceAsync(args, cancellationToken).ConfigureAwait(false);
            if (run.Success)
            {
                return new AiAdviceResponse(true, "GPT4All", run.Message, DateTimeOffset.Now);
            }

            lastError = run.Message;
        }

        return new AiAdviceResponse(
            false,
            "GPT4All",
            string.IsNullOrWhiteSpace(lastError) ? "GPT4All CLI execution failed." : lastError,
            DateTimeOffset.Now);
    }

    private IEnumerable<string> BuildCliArgumentCandidates(string prompt)
    {
        var candidates = new List<string>();
        var promptQuoted = Quote(prompt);
        var modelQuoted = Quote(_model);

        if (!string.IsNullOrWhiteSpace(_cliArgsTemplate))
        {
            candidates.Add(
                _cliArgsTemplate
                    .Replace("{model}", modelQuoted, StringComparison.OrdinalIgnoreCase)
                    .Replace("{prompt}", promptQuoted, StringComparison.OrdinalIgnoreCase));
        }

        candidates.Add($"--model {modelQuoted} --prompt {promptQuoted}");
        candidates.Add($"--model {modelQuoted} -p {promptQuoted}");
        candidates.Add($"-m {modelQuoted} -p {promptQuoted}");
        candidates.Add($"--prompt {promptQuoted}");
        candidates.Add($"-p {promptQuoted}");
        candidates.Add(promptQuoted);

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var item in candidates)
        {
            if (!seen.Add(item)) continue;
            yield return item;
        }
    }

    private async Task<OperationResult> ExecuteCliOnceAsync(string arguments, CancellationToken cancellationToken)
    {
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
                var parsed = TryExtractMessage(stdout);
                return OperationResult.Ok(parsed);
            }

            var reason = string.IsNullOrWhiteSpace(stderr)
                ? $"CLI exited with code {process.ExitCode} ({arguments})."
                : $"{stderr} ({arguments})";

            return OperationResult.Fail(reason);
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

            return OperationResult.Fail($"GPT4All CLI timeout ({arguments}).");
        }
        catch (Exception ex)
        {
            return OperationResult.Fail($"{ex.Message} ({arguments})");
        }
    }

    private static string TryExtractMessage(string output)
    {
        var text = output.Trim();
        if (string.IsNullOrWhiteSpace(text)) return text;

        try
        {
            using var document = JsonDocument.Parse(text);
            var root = document.RootElement;

            if (root.TryGetProperty("response", out var responseNode) && responseNode.ValueKind == JsonValueKind.String)
            {
                return responseNode.GetString() ?? text;
            }

            if (root.TryGetProperty("content", out var contentNode) && contentNode.ValueKind == JsonValueKind.String)
            {
                return contentNode.GetString() ?? text;
            }

            if (root.TryGetProperty("text", out var textNode) && textNode.ValueKind == JsonValueKind.String)
            {
                return textNode.GetString() ?? text;
            }

            if (root.TryGetProperty("message", out var messageNode) && messageNode.ValueKind == JsonValueKind.String)
            {
                return messageNode.GetString() ?? text;
            }
        }
        catch
        {
        }

        return text;
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

    private sealed record OperationResult(bool Success, string Message)
    {
        public static OperationResult Ok(string message) => new(true, message);
        public static OperationResult Fail(string message) => new(false, message);
    }
}
