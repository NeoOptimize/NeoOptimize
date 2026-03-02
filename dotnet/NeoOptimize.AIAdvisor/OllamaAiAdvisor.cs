using System;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NeoOptimize.AIAdvisor.Models;

namespace NeoOptimize.AIAdvisor;

public sealed class OllamaAiAdvisor : IAiAdvisor
{
    private readonly HttpClient _httpClient;
    private readonly string _endpoint;
    private readonly string _model;

    public OllamaAiAdvisor(
        string? endpoint = null,
        string? model = null,
        HttpClient? httpClient = null)
    {
        _endpoint = string.IsNullOrWhiteSpace(endpoint)
            ? Environment.GetEnvironmentVariable("NEO_OLLAMA_ENDPOINT") ?? "http://127.0.0.1:11434/api/generate"
            : endpoint;

        _model = string.IsNullOrWhiteSpace(model)
            ? Environment.GetEnvironmentVariable("NEO_OLLAMA_MODEL") ?? "llama3.1:8b"
            : model;

        _httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(8)
        };
    }

    public async Task<AiAdviceResponse> GetAdviceAsync(AiAdviceRequest request, CancellationToken cancellationToken)
    {
        var prompt = $"System snapshot: CPU {request.Snapshot.CpuUsagePercent:F1}%, RAM {request.Snapshot.MemoryUsagePercent:F1}%, " +
                     $"Disk {request.Snapshot.DiskUsagePercent:F1}%, Network {request.Snapshot.NetworkUsageMbps:F1} Mbps. " +
                     "Give concise optimization advice for Windows offline tool. Advisor only, no direct action.";

        var payload = new
        {
            model = _model,
            prompt,
            stream = false
        };

        try
        {
            using var response = await _httpClient.PostAsJsonAsync(_endpoint, payload, cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode)
            {
                return new AiAdviceResponse(
                    false,
                    "Ollama",
                    $"Ollama unavailable ({(int)response.StatusCode}).",
                    DateTimeOffset.Now);
            }

            using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken).ConfigureAwait(false);
            var text = document.RootElement.TryGetProperty("response", out var resultNode)
                ? resultNode.GetString() ?? "No response from Ollama."
                : "No response from Ollama.";

            return new AiAdviceResponse(
                true,
                "Ollama",
                text.Trim(),
                DateTimeOffset.Now);
        }
        catch
        {
            return new AiAdviceResponse(false, "Ollama", "Ollama adapter failed.", DateTimeOffset.Now);
        }
    }
}
