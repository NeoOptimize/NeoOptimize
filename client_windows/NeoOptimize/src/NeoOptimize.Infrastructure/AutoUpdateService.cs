using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace NeoOptimize.Infrastructure;

/// <summary>
/// Auto-update service using Velopack (https://velopack.io).
/// 
/// Setup:
///   1. Install Velopack CLI:  dotnet tool install -g vpk
///   2. Package:               vpk pack --packId NeoOptimize --packVersion 1.1.0 --packDir artifacts\publish
///   3. Publish to GitHub:     vpk upload github --repoUrl https://github.com/NeoOptimize/NeoOptimize
///
/// At runtime this service checks GitHub Releases on startup and
/// every 6 hours, downloads+applies updates silently, and restarts
/// the app when the user closes it.
/// </summary>
public sealed class AutoUpdateService : BackgroundService
{
    private readonly ILogger<AutoUpdateService> _logger;
    private readonly NeoOptimizeClientOptions _options;
    private readonly HttpClient _http;
    private const string GitHubApiRelease = "https://api.github.com/repos/NeoOptimize/NeoOptimize/releases/latest";
    private const string VpkExeName = "Update.exe"; // Velopack bootstrapper placed by installer

    public bool IsUpdateAvailable { get; private set; }
    public string? LatestVersion   { get; private set; }
    public string? DownloadUrl     { get; private set; }

    public AutoUpdateService(
        IOptions<NeoOptimizeClientOptions> options,
        HttpClient http,
        ILogger<AutoUpdateService> logger)
    {
        _options = options.Value;
        _http    = http;
        _logger  = logger;
        _http.DefaultRequestHeaders.Add("User-Agent", $"NeoOptimize/{_options.AppVersion}");
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        // Initial check after 30s to avoid slowing startup
        await Task.Delay(TimeSpan.FromSeconds(30), ct);

        while (!ct.IsCancellationRequested)
        {
            await CheckAndApplyUpdateAsync(ct);
            await Task.Delay(TimeSpan.FromHours(6), ct);
        }
    }

    public async Task<UpdateCheckResult> CheckAndApplyUpdateAsync(CancellationToken ct = default)
    {
        try
        {
            var release = await _http.GetFromJsonAsync<GitHubRelease>(GitHubApiRelease, ct);
            if (release is null) return new UpdateCheckResult(false, null, "No release found.");

            var latestVer  = release.TagName.TrimStart('v');
            var currentVer = _options.AppVersion ?? "1.0.0";

            if (!IsNewer(latestVer, currentVer))
            {
                _logger.LogInformation("NeoOptimize is up-to-date ({Ver})", currentVer);
                return new UpdateCheckResult(false, currentVer, "Already up-to-date.");
            }

            LatestVersion    = latestVer;
            IsUpdateAvailable = true;
            DownloadUrl      = release.Assets.FirstOrDefault(a => a.Name.EndsWith(".exe"))?.BrowserDownloadUrl;

            _logger.LogInformation("Update available: {Current} ΓåÆ {Latest}", currentVer, latestVer);

            // If Velopack Update.exe is present, apply silently
            if (await TryApplyVelopackAsync(ct))
                return new UpdateCheckResult(true, latestVer, "Update applied. Restart required.");

            return new UpdateCheckResult(true, latestVer, $"Update v{latestVer} available. Download: {DownloadUrl}");
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Auto-update check failed");
            return new UpdateCheckResult(false, null, ex.Message);
        }
    }

    private async Task<bool> TryApplyVelopackAsync(CancellationToken ct)
    {
        // Update.exe is placed by Velopack in the app root during installation
        var updateExe = Path.Combine(AppContext.BaseDirectory, VpkExeName);
        if (!File.Exists(updateExe)) return false;

        try
        {
            // Velopack silent update: --update <channel_url>
            var channelUrl = $"https://github.com/NeoOptimize/NeoOptimize/releases/latest/download/";
            var psi = new ProcessStartInfo(updateExe, $"--update {channelUrl}")
            {
                UseShellExecute        = false,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                CreateNoWindow         = true,
            };
            using var proc = Process.Start(psi) ?? throw new InvalidOperationException("Cannot start Update.exe");
            using var cts  = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromMinutes(10));
            await proc.WaitForExitAsync(cts.Token);
            _logger.LogInformation("Velopack update exit code: {Exit}", proc.ExitCode);
            return proc.ExitCode == 0;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Velopack apply failed");
            return false;
        }
    }

    private static bool IsNewer(string latest, string current)
    {
        if (!Version.TryParse(latest, out var v1)) return false;
        if (!Version.TryParse(current, out var v2)) return false;
        return v1 > v2;
    }
}

// ΓöÇΓöÇ DTOs ΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇΓöÇ

public sealed class GitHubRelease
{
    [JsonPropertyName("tag_name")]  public string TagName  { get; init; } = string.Empty;
    [JsonPropertyName("assets")]    public List<GitHubAsset> Assets { get; init; } = [];
    [JsonPropertyName("body")]      public string? ReleaseNotes { get; init; }
}

public sealed class GitHubAsset
{
    [JsonPropertyName("name")]                  public string Name { get; init; } = string.Empty;
    [JsonPropertyName("browser_download_url")] public string BrowserDownloadUrl { get; init; } = string.Empty;
    [JsonPropertyName("size")]                  public long   Size { get; init; }
}

public sealed record UpdateCheckResult(bool HasUpdate, string? Version, string Message);
