using System.Net;
using System.Net.Http.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NeoOptimize.Agent.Models;

namespace NeoOptimize.Agent.Services;

public class ApiClient
{
    private readonly HttpClient _http;
    private readonly ILogger<ApiClient> _logger;
    private string _apiKey;
    private readonly string _version = "1.0.0";
    private DateTime _lastRegistrationAttemptUtc = DateTime.MinValue;

    // Gets the real EXE folder (works with single-file publish)
    private static string GetExeDir()
    {
        var exe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName;
        return System.IO.Path.GetDirectoryName(exe) ?? AppDomain.CurrentDomain.BaseDirectory;
    }

    private readonly ISystemCollector _sys;

    public ApiClient(HttpClient http, IConfiguration config, ILogger<ApiClient> logger, ISystemCollector sys)
    {
        _http   = http;
        _logger = logger;
        _sys    = sys;

        var baseUrl = config["ServerUrl"] ?? config["Agent:ServerUrl"] ?? "http://localhost:3000";
        var enrollmentToken =
            config["EnrollmentToken"] ??
            config["Agent:EnrollmentToken"] ??
            Environment.GetEnvironmentVariable("NEO_RMM_ENROLLMENT_TOKEN") ??
            Environment.GetEnvironmentVariable("AGENT_ENROLLMENT_TOKEN");

        _http.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/api/v1/agent/");
        _logger.LogInformation("RMM Server: {Url}", _http.BaseAddress);
        if (!string.IsNullOrWhiteSpace(enrollmentToken))
        {
            _http.DefaultRequestHeaders.Remove("x-enrollment-token");
            _http.DefaultRequestHeaders.Add("x-enrollment-token", enrollmentToken);
        }

        // First try reading from appsettings.json in the REAL exe folder
        var appSettingsPath = System.IO.Path.Combine(GetExeDir(), "appsettings.json");
        _logger.LogInformation("Config path: {Path}", appSettingsPath);

        _apiKey = config["ApiKey"] ?? config["Agent:ApiKey"] ?? "";

        // Also re-read directly from file in case config cache is stale
        if (IsPlaceholderApiKey(_apiKey) && System.IO.File.Exists(appSettingsPath))
        {
            try {
                var rawJson = System.IO.File.ReadAllText(appSettingsPath);
                var doc = System.Text.Json.JsonDocument.Parse(rawJson);
                var saved = ReadApiKey(doc.RootElement);
                if (!IsPlaceholderApiKey(saved)) _apiKey = saved!;
            } catch { }
        }

        if (IsPlaceholderApiKey(_apiKey))
        {
            PerformRegistration(appSettingsPath, baseUrl);
        }

        if (!IsPlaceholderApiKey(_apiKey))
            _http.DefaultRequestHeaders.Add("x-api-key", _apiKey);
        else
            _logger.LogWarning("Running without API key — check-ins will fail until registration succeeds.");
    }

    private void PerformRegistration(string appSettingsPath, string baseUrl)
    {
        if (DateTime.UtcNow - _lastRegistrationAttemptUtc < TimeSpan.FromMinutes(5))
        {
            _logger.LogWarning("Auto-registration cooldown active; skipping retry.");
            return;
        }

        _lastRegistrationAttemptUtc = DateTime.UtcNow;
        _logger.LogInformation("No API Key — starting Auto-Registration...");

        // [BUG-A03 FIX] Cache meta so we don't query WMI twice
        var meta = _sys.GetSystemMeta();
        var uuid = _sys.GetBiosUuid();

        // [BUG-A01 FIX] Field names now match server /register route:
        // Server expects: {uuid, hostname, version, os, cpu, gpu, ram_mb}
        // Old code sent:  {u, h, v, meta} — WRONG, caused silent server failure
        var regBody = new
        {
            uuid     = uuid,
            hostname = Environment.MachineName,
            version  = _version,   // [BUG-A02 FIX] was hardcoded "4.0.0"
            os       = meta.GetValueOrDefault("os", "Unknown"),
            cpu      = meta.GetValueOrDefault("cpu", "Unknown"),
            gpu      = meta.GetValueOrDefault("gpu"),
            ram_mb   = meta.ContainsKey("ram_mb") && int.TryParse(meta["ram_mb"], out var mb) ? mb : (int?)null
        };

        try
        {
            var res  = _http.PostAsJsonAsync("register", regBody).GetAwaiter().GetResult();
            if (!res.IsSuccessStatusCode)
            {
                var errBody = res.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                _logger.LogError("Auto-Registration FAILED ({Status}): {Body}", res.StatusCode, errBody);
                return;
            }
            var data = res.Content.ReadFromJsonAsync<System.Text.Json.JsonElement>().GetAwaiter().GetResult();
            _apiKey  = data.GetProperty("api_key").GetString() ?? "";

            SaveApiSettings(appSettingsPath, baseUrl, _apiKey);
            _logger.LogInformation("API Key saved to: {Path}", appSettingsPath);
            _logger.LogInformation("Auto-Registration SUCCESS. Agent ID active.");

            _http.DefaultRequestHeaders.Remove("x-api-key");
            _http.DefaultRequestHeaders.Add("x-api-key", _apiKey);
        }
        catch (Exception ex)
        {
            _logger.LogError("Auto-Registration FAILED (network): {Msg}", ex.Message);
            _logger.LogError("Check that ServerUrl ({Url}) is reachable.", _http.BaseAddress);
        }
    }

    private void HandleUnauthorized()
    {
        _logger.LogError("CRITICAL: Server rejected the API Key (401 Unauthorized). The agent may have been deleted from the dashboard.");
        _logger.LogInformation("Attempting to re-register with the server to obtain a new API Key...");

        var appSettingsPath = System.IO.Path.Combine(GetExeDir(), "appsettings.json");
        if (System.IO.File.Exists(appSettingsPath))
        {
            try
            {
                var json = System.IO.File.ReadAllText(appSettingsPath);
                // Wipe the old key so it goes back to default
                SaveApiSettings(appSettingsPath, _http.BaseAddress?.ToString().Replace("/api/v1/agent/", "") ?? "http://localhost:3000", "");
                _apiKey = "";
            } catch { }
        }

        // Delay to prevent spamming
        Thread.Sleep(2000);
        PerformRegistration(appSettingsPath, _http.BaseAddress?.ToString().Replace("/api/v1/agent/", "") ?? "http://localhost:3000");
    }

    private static bool IsPlaceholderApiKey(string? value)
    {
        return string.IsNullOrWhiteSpace(value) || !Guid.TryParse(value.Trim(), out _);
    }

    private static string? ReadApiKey(System.Text.Json.JsonElement root)
    {
        if (root.TryGetProperty("ApiKey", out var rootKey)) return rootKey.GetString();
        if (root.TryGetProperty("Agent", out var agent) && agent.TryGetProperty("ApiKey", out var nestedKey))
            return nestedKey.GetString();
        return null;
    }

    private static void SaveApiSettings(string appSettingsPath, string serverUrl, string apiKey)
    {
        System.Text.Json.Nodes.JsonObject root;
        if (System.IO.File.Exists(appSettingsPath))
        {
            var parsed = System.Text.Json.Nodes.JsonNode.Parse(System.IO.File.ReadAllText(appSettingsPath));
            root = parsed as System.Text.Json.Nodes.JsonObject ?? new System.Text.Json.Nodes.JsonObject();
        }
        else
        {
            root = new System.Text.Json.Nodes.JsonObject();
        }

        if (root["Agent"] is System.Text.Json.Nodes.JsonObject agent)
        {
            agent["ServerUrl"] = serverUrl;
            agent["ApiKey"] = apiKey;
        }
        else
        {
            root["ServerUrl"] = serverUrl;
            root["ApiKey"] = apiKey;
        }

        var json = root.ToJsonString(new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
        System.IO.File.WriteAllText(appSettingsPath, json);
    }

    public async Task<CheckInResponse?> CheckInAsync(CheckInRequest req, CancellationToken ct)
    {
        try
        {
            var res = await _http.PostAsJsonAsync("check-in", req, ct);
            if (res.StatusCode == HttpStatusCode.Unauthorized)
            {
                HandleUnauthorized();
                return null;
            }
            res.EnsureSuccessStatusCode();
            return await res.Content.ReadFromJsonAsync<CheckInResponse>(cancellationToken: ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning("CheckIn failed: {Message}", ex.Message);
            return null;
        }
    }

    public async Task SendReportAsync(ReportRequest req, CancellationToken ct)
    {
        try
        {
            var res = await _http.PostAsJsonAsync("report", req, ct);
            if (res.StatusCode == HttpStatusCode.Unauthorized) HandleUnauthorized();
            else res.EnsureSuccessStatusCode();
        }
        catch (Exception ex)
        {
            _logger.LogError("Failed to send report for cmd {CmdId}: {Msg}", req.CmdId, ex.Message);
        }
    }

    public async Task SendTelemetryAsync(TelemetryRequest req, CancellationToken ct)
    {
        try
        {
            var res = await _http.PostAsJsonAsync("telemetry", req, ct);
            if (res.StatusCode == HttpStatusCode.Unauthorized) HandleUnauthorized();
            else res.EnsureSuccessStatusCode();
        }
        catch (Exception ex)
        {
            _logger.LogDebug("Telemetry dropped: {Msg}", ex.Message);
        }
    }
}
