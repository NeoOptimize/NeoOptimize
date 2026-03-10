using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Web.WebView2.Core;
using NeoOptimize.App.Services;
using NeoOptimize.Contracts;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.App;

public partial class MainWindow : Window
{
    private static readonly Uri LatestReleaseEndpoint = new("https://api.github.com/repos/NeoOptimize/NeoOptimize/releases/latest");
    private static readonly HttpClient ReleaseHttpClient = CreateReleaseHttpClient();

    private readonly NeoOptimizeApiClient _apiClient;
    private readonly SystemSnapshotProvider _snapshotProvider;
    private readonly DesktopActionRunner _actionRunner;
    private readonly ReportStore _reportStore;
    private readonly NeoOptimizeClientOptions _options;
    private readonly ILogger<MainWindow> _logger;
    private readonly CancellationTokenSource _shutdownCts = new();
    private readonly DispatcherTimer _telemetryTimer;
    private readonly DispatcherTimer _commandTimer;
    private readonly List<ActivityEntry> _activity = [];
    private int _tickCount;
    private bool _timersStarted;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    public MainWindow(
        NeoOptimizeApiClient apiClient,
        SystemSnapshotProvider snapshotProvider,
        DesktopActionRunner actionRunner,
        ReportStore reportStore,
        IOptions<NeoOptimizeClientOptions> options,
        ILogger<MainWindow> logger)
    {
        InitializeComponent();
        _apiClient = apiClient;
        _snapshotProvider = snapshotProvider;
        _actionRunner = actionRunner;
        _reportStore = reportStore;
        _options = options.Value;
        _logger = logger;

        _telemetryTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(Math.Max(10, _options.TelemetryIntervalSeconds)),
        };
        _telemetryTimer.Tick += async (_, _) => await RefreshSnapshotAsync(manual: false);

        _commandTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(Math.Max(15, _options.CommandPollIntervalSeconds)),
        };
        _commandTimer.Tick += async (_, _) => await ProcessPendingCommandsAsync();

        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        await InitializeWebViewAsync();
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        _shutdownCts.Cancel();
        _telemetryTimer.Stop();
        _commandTimer.Stop();
    }

    private async Task InitializeWebViewAsync()
    {
        var webRoot = Path.Combine(AppContext.BaseDirectory, "WebApp");
        var userDataFolder = ResolveWebViewUserDataFolder();
        Directory.CreateDirectory(userDataFolder);

        var environment = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
        await DashboardWebView.EnsureCoreWebView2Async(environment);
        DashboardWebView.ZoomFactor = 1.0;
        DashboardWebView.CoreWebView2.Settings.AreDevToolsEnabled = false;
        DashboardWebView.CoreWebView2.Settings.IsStatusBarEnabled = false;
        DashboardWebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        DashboardWebView.CoreWebView2.WebMessageReceived += DashboardWebView_OnWebMessageReceived;
        DashboardWebView.CoreWebView2.NavigationStarting += DashboardWebView_OnNavigationStarting;
        DashboardWebView.CoreWebView2.NewWindowRequested += DashboardWebView_OnNewWindowRequested;
        DashboardWebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
            "app.neooptimize.local",
            webRoot,
            CoreWebView2HostResourceAccessKind.Allow);
        DashboardWebView.Source = new Uri("https://app.neooptimize.local/index.html");
    }

    private string ResolveWebViewUserDataFolder()
    {
        if (!string.IsNullOrWhiteSpace(_options.WebViewUserDataFolder))
        {
            return _options.WebViewUserDataFolder;
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "NeoOptimize",
            "WebView2");
    }

    private void DashboardWebView_OnNavigationStarting(object? sender, CoreWebView2NavigationStartingEventArgs e)
    {
        if (IsInternalAppUri(e.Uri))
        {
            return;
        }

        e.Cancel = true;
        OpenExternalUri(e.Uri);
    }

    private void DashboardWebView_OnNewWindowRequested(object? sender, CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        OpenExternalUri(e.Uri);
    }

    private async void DashboardWebView_OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
    {
        try
        {
            using var document = JsonDocument.Parse(e.WebMessageAsJson);
            var root = document.RootElement;
            var type = root.GetProperty("type").GetString();
            switch (type)
            {
                case "bootstrap":
                    await BootstrapAsync();
                    break;
                case "refresh":
                    await RefreshSnapshotAsync(manual: true);
                    break;
                case "runAction":
                    await RunActionAsync(root.GetProperty("action").GetString() ?? string.Empty);
                    break;
                case "listReports":
                    SendReports();
                    break;
                case "openReport":
                    _reportStore.OpenReport(root.GetProperty("fileName").GetString() ?? string.Empty);
                    break;
                case "deleteReport":
                    if (_reportStore.DeleteReport(root.GetProperty("fileName").GetString() ?? string.Empty))
                    {
                        SendReports();
                        AddActivity("Report deleted", "Laporan lokal dihapus dari storage desktop.");
                        SendActivity();
                    }
                    break;
                case "aiChat":
                    await HandleAiChatAsync(
                        root.GetProperty("message").GetString() ?? string.Empty,
                        root.TryGetProperty("dispatchActions", out var dispatchElement) && dispatchElement.GetBoolean());
                    break;
                case "checkUpdate":
                    await CheckForUpdateAsync(silent: false);
                    break;
            }
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Failed to handle WebView message");
            SendToast("error", "UI bridge gagal memproses permintaan.");
        }
    }

    private async Task BootstrapAsync()
    {
        try
        {
            var registration = await _apiClient.EnsureRegistrationAsync(_shutdownCts.Token);
            PostMessage(new
            {
                type = "bootstrap",
                payload = new
                {
                    clientId = registration.ClientId,
                    backendUrl = _options.BackendBaseUrl,
                    appVersion = _options.AppVersion,
                    status = $"Connected · {DateTimeOffset.Now:HH:mm:ss}",
                    reports = _reportStore.ListReports(),
                },
            });

            AddActivity("Client registered", $"NeoOptimize aktif sebagai {registration.ClientId[..8]}.");
            SendReports();
            SendActivity();
            await RefreshSnapshotAsync(manual: true);
            await ProcessPendingCommandsAsync();
            await CheckForUpdateAsync(silent: true);
            StartTimers();
            SendToast("success", "NeoOptimize connected to backend and Supabase.");
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Bootstrap failed");
            SendToast("error", "Bootstrap gagal. Periksa koneksi backend atau kredensial client.");
        }
    }

    private void StartTimers()
    {
        if (_timersStarted)
        {
            return;
        }

        _telemetryTimer.Start();
        _commandTimer.Start();
        _timersStarted = true;
    }

    private async Task RefreshSnapshotAsync(bool manual)
    {
        var telemetry = _snapshotProvider.CollectTelemetry();
        var health = _snapshotProvider.CollectHealth("desktop_ui");
        List<string> alerts = [];

        try
        {
            var response = await _apiClient.PushTelemetryAsync(telemetry, _shutdownCts.Token);
            alerts = response.Alerts;

            _tickCount++;
            var healthIntervalTicks = Math.Max(1, (int)Math.Ceiling((_options.HealthIntervalMinutes * 60d) / Math.Max(10, _options.TelemetryIntervalSeconds)));
            if (manual || _tickCount % healthIntervalTicks == 0)
            {
                await _apiClient.ReportHealthAsync(health, _shutdownCts.Token);
            }
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Snapshot push failed");
            if (manual)
            {
                SendToast("error", "Snapshot lokal tampil, tetapi push ke backend gagal.");
            }
        }

        var topProcesses = telemetry.TopProcesses.Select(process => new
        {
            name = TryGetString(process, "name") ?? "unknown",
            pid = TryGetInt(process, "pid"),
            workingSetMb = TryGetDouble(process, "working_set_mb"),
        }).ToList();

        var machineName = TryGetSnapshotString(telemetry.Snapshot, "machine_name") ?? Environment.MachineName;
        var operatingSystem = TryGetSnapshotString(telemetry.Snapshot, "os") ?? Environment.OSVersion.VersionString;
        var recordedAt = TryGetSnapshotDateTime(telemetry.Snapshot, "timestamp_utc") ?? DateTimeOffset.UtcNow;

        PostMessage(new
        {
            type = "stats",
            payload = new
            {
                cpu = telemetry.CpuPercent,
                ram = telemetry.RamPercent,
                disk = telemetry.DiskUsagePercent,
                networkMbps = telemetry.NetworkMbps,
                healthState = health.HealthState,
                integrityStatus = health.IntegrityStatus ?? "pending",
                alerts,
                overallScore = health.OverallScore,
                recommendations = health.Recommendations,
                issues = health.Issues,
                processCount = telemetry.ProcessCount,
                topProcesses,
                machineName,
                os = operatingSystem,
                recordedAt = recordedAt.ToLocalTime().ToString("dd MMM yyyy HH:mm:ss"),
            },
        });

        if (manual)
        {
            SendToast("info", "Snapshot sistem berhasil diperbarui.");
        }
    }

    private async Task RunActionAsync(string action)
    {
        try
        {
            var result = await _actionRunner.RunActionAsync(action, _shutdownCts.Token);
            AddActivity(result.Title, result.Summary);
            SendReports();
            SendActivity();
            PostMessage(new
            {
                type = "actionResult",
                payload = new
                {
                    title = result.Title,
                    summary = result.Summary,
                    reportFile = result.ReportFileName,
                },
            });
            await RefreshSnapshotAsync(manual: false);
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Action execution failed for {Action}", action);
            SendToast("error", $"Action '{action}' gagal dijalankan.");
        }
    }

    private async Task HandleAiChatAsync(string message, bool dispatchActions)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            SendToast("error", "Prompt AI tidak boleh kosong.");
            return;
        }

        try
        {
            var response = await _apiClient.ChatWithAiAsync(message, dispatchActions, _shutdownCts.Token);
            var plannedActions = response.PlannedActions.Select(action => new
            {
                commandName = action.CommandName,
                reason = action.Reason,
                dispatched = action.Dispatched,
            }).ToList();
            var memoryHits = response.MemoryHits.Select(hit => new
            {
                messageId = hit.MessageId,
                userMessage = hit.UserMessage,
                aiResponse = hit.AiResponse,
                similarity = hit.Similarity,
            }).ToList();

            PostMessage(new
            {
                type = "aiResponse",
                payload = new
                {
                    reply = response.Reply,
                    correlationId = response.CorrelationId,
                    memoryId = response.MemoryId,
                    plannedActions,
                    memoryHits,
                    contextSummary = response.ContextSummary,
                    dispatched = plannedActions.Any(action => action.dispatched),
                },
            });

            AddActivity(
                "Neo AI analysis",
                plannedActions.Any(action => action.dispatched)
                    ? "Neo AI mengirim tindakan ke execution loop lokal."
                    : "Neo AI mengembalikan analisis dan rencana aksi.");
            SendActivity();

            if (dispatchActions)
            {
                await ProcessPendingCommandsAsync();
            }
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "AI chat failed");
            SendToast("error", "Neo AI tidak merespons. Coba ulangi prompt Anda.");
        }
    }

    private async Task ProcessPendingCommandsAsync()
    {
        try
        {
            for (var i = 0; i < 4; i++)
            {
                var command = await _apiClient.PollCommandAsync(_shutdownCts.Token);
                if (!string.Equals(command.Status, "pending", StringComparison.OrdinalIgnoreCase))
                {
                    break;
                }

                var result = await _actionRunner.ExecuteCommandAsync(command, _shutdownCts.Token);
                await _apiClient.SubmitCommandResultAsync(result, _shutdownCts.Token);
                AddActivity(
                    $"Remote command · {command.CommandName}",
                    result.Status == "completed"
                        ? "Command berhasil dieksekusi dari queue backend."
                        : result.ErrorMessage ?? "Command gagal dieksekusi.");
                SendReports();
                SendActivity();
            }
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Remote command polling failed");
        }
    }

    private async Task CheckForUpdateAsync(bool silent)
    {
        try
        {
            using var response = await ReleaseHttpClient.GetAsync(LatestReleaseEndpoint, _shutdownCts.Token);
            response.EnsureSuccessStatusCode();

            await using var stream = await response.Content.ReadAsStreamAsync(_shutdownCts.Token);
            var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(stream, JsonOptions, _shutdownCts.Token)
                ?? throw new InvalidOperationException("Release metadata is empty.");

            var currentVersion = NormalizeVersion(_options.AppVersion);
            var latestVersion = NormalizeVersion(release.TagName ?? _options.AppVersion);
            var hasUpdate = CompareVersions(latestVersion, currentVersion) > 0;
            var summary = hasUpdate
                ? $"Versi {latestVersion} siap diunduh."
                : $"Versi {currentVersion} sudah sinkron dengan release terbaru.";

            PostMessage(new
            {
                type = "updateStatus",
                payload = new
                {
                    status = hasUpdate ? "update-available" : "up-to-date",
                    currentVersion,
                    latestVersion,
                    hasUpdate,
                    releaseUrl = release.HtmlUrl ?? "https://github.com/NeoOptimize/NeoOptimize/releases",
                    publishedAt = release.PublishedAt?.ToLocalTime().ToString("dd MMM yyyy HH:mm"),
                    summary,
                },
            });

            if (!silent)
            {
                SendToast(hasUpdate ? "info" : "success", summary);
            }
        }
        catch (Exception exception) when (!_shutdownCts.IsCancellationRequested)
        {
            _logger.LogWarning(exception, "Update check failed");
            PostMessage(new
            {
                type = "updateStatus",
                payload = new
                {
                    status = "check-failed",
                    currentVersion = NormalizeVersion(_options.AppVersion),
                    latestVersion = NormalizeVersion(_options.AppVersion),
                    hasUpdate = false,
                    releaseUrl = "https://github.com/NeoOptimize/NeoOptimize/releases",
                    publishedAt = string.Empty,
                    summary = "Tidak bisa memeriksa release GitHub saat ini.",
                },
            });

            if (!silent)
            {
                SendToast("error", "Cek update gagal. GitHub release belum dapat diakses.");
            }
        }
    }

    private void SendReports()
    {
        PostMessage(new
        {
            type = "reports",
            payload = _reportStore.ListReports().Select(report => new
            {
                fileName = report.FileName,
                title = report.Title,
                createdAt = report.CreatedAt,
                sizeLabel = report.SizeLabel,
            }),
        });
    }

    private void SendActivity()
    {
        PostMessage(new
        {
            type = "activity",
            payload = _activity.Select(item => new
            {
                title = item.Title,
                summary = item.Summary,
                timestamp = item.Timestamp,
            }),
        });
    }

    private void AddActivity(string title, string summary)
    {
        _activity.Insert(0, new ActivityEntry(title, summary, DateTimeOffset.Now.ToString("HH:mm:ss")));
        if (_activity.Count > 12)
        {
            _activity.RemoveAt(_activity.Count - 1);
        }
    }

    private void SendToast(string tone, string message)
    {
        PostMessage(new { type = "toast", payload = new { tone, message } });
    }

    private void PostMessage(object payload)
    {
        if (DashboardWebView.CoreWebView2 is null)
        {
            return;
        }

        DashboardWebView.CoreWebView2.PostWebMessageAsJson(JsonSerializer.Serialize(payload, JsonOptions));
    }

    private static HttpClient CreateReleaseHttpClient()
    {
        var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(20),
        };
        client.DefaultRequestHeaders.UserAgent.ParseAdd("NeoOptimizeDesktop/0.2");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        return client;
    }

    private void OpenExternalUri(string? rawUri)
    {
        if (string.IsNullOrWhiteSpace(rawUri))
        {
            return;
        }

        try
        {
            Process.Start(new ProcessStartInfo(rawUri) { UseShellExecute = true });
        }
        catch (Exception exception)
        {
            _logger.LogWarning(exception, "Failed to open external URI {Uri}", rawUri);
            SendToast("error", "Gagal membuka tautan eksternal.");
        }
    }

    private static bool IsInternalAppUri(string? rawUri)
    {
        if (string.IsNullOrWhiteSpace(rawUri))
        {
            return false;
        }

        if (!Uri.TryCreate(rawUri, UriKind.Absolute, out var uri))
        {
            return false;
        }

        return uri.Scheme == Uri.UriSchemeHttps
            && string.Equals(uri.Host, "app.neooptimize.local", StringComparison.OrdinalIgnoreCase);
    }

    private static string? TryGetString(IReadOnlyDictionary<string, object?> source, string key)
    {
        return source.TryGetValue(key, out var value) ? value?.ToString() : null;
    }

    private static int? TryGetInt(IReadOnlyDictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var value) || value is null)
        {
            return null;
        }

        return value switch
        {
            int intValue => intValue,
            long longValue => (int)longValue,
            double doubleValue => (int)Math.Round(doubleValue),
            float floatValue => (int)Math.Round(floatValue),
            string stringValue when int.TryParse(stringValue, out var parsed) => parsed,
            JsonElement element when element.ValueKind == JsonValueKind.Number && element.TryGetInt32(out var parsed) => parsed,
            JsonElement element when element.ValueKind == JsonValueKind.String && int.TryParse(element.GetString(), out var parsed) => parsed,
            _ => null,
        };
    }

    private static double? TryGetDouble(IReadOnlyDictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var value) || value is null)
        {
            return null;
        }

        return value switch
        {
            double doubleValue => doubleValue,
            float floatValue => floatValue,
            decimal decimalValue => (double)decimalValue,
            int intValue => intValue,
            long longValue => longValue,
            string stringValue when double.TryParse(stringValue, out var parsed) => parsed,
            JsonElement element when element.ValueKind == JsonValueKind.Number && element.TryGetDouble(out var parsed) => parsed,
            JsonElement element when element.ValueKind == JsonValueKind.String && double.TryParse(element.GetString(), out var parsed) => parsed,
            _ => null,
        };
    }

    private static string? TryGetSnapshotString(IReadOnlyDictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var value) || value is null)
        {
            return null;
        }

        return value switch
        {
            string stringValue => stringValue,
            JsonElement element when element.ValueKind == JsonValueKind.String => element.GetString(),
            _ => value.ToString(),
        };
    }

    private static DateTimeOffset? TryGetSnapshotDateTime(IReadOnlyDictionary<string, object?> source, string key)
    {
        if (!source.TryGetValue(key, out var value) || value is null)
        {
            return null;
        }

        return value switch
        {
            DateTimeOffset dateTimeOffset => dateTimeOffset,
            DateTime dateTime => new DateTimeOffset(dateTime),
            string stringValue when DateTimeOffset.TryParse(stringValue, out var parsed) => parsed,
            JsonElement element when element.ValueKind == JsonValueKind.String && DateTimeOffset.TryParse(element.GetString(), out var parsed) => parsed,
            _ => null,
        };
    }

    private static string NormalizeVersion(string? version)
    {
        return string.IsNullOrWhiteSpace(version)
            ? "0.0.0"
            : version.Trim().TrimStart('v', 'V');
    }

    private static int CompareVersions(string left, string right)
    {
        if (Version.TryParse(left, out var leftVersion) && Version.TryParse(right, out var rightVersion))
        {
            return leftVersion.CompareTo(rightVersion);
        }

        return string.Compare(left, right, StringComparison.OrdinalIgnoreCase);
    }

    private void TitleBar_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2)
        {
            ToggleWindowState();
            return;
        }

        DragMove();
    }

    private void Minimize_OnClick(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    private void MaximizeRestore_OnClick(object sender, RoutedEventArgs e) => ToggleWindowState();

    private void Close_OnClick(object sender, RoutedEventArgs e) => Close();

    private void ToggleWindowState()
    {
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    }

    private sealed record ActivityEntry(string Title, string Summary, string Timestamp);

    private sealed record GitHubRelease(
        [property: JsonPropertyName("tag_name")] string? TagName,
        [property: JsonPropertyName("html_url")] string? HtmlUrl,
        [property: JsonPropertyName("published_at")] DateTimeOffset? PublishedAt);
}

