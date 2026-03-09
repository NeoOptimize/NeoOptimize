using System.Text.Json;
using System.IO;
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
        await DashboardWebView.EnsureCoreWebView2Async();
        var webRoot = Path.Combine(AppContext.BaseDirectory, "WebApp");
        DashboardWebView.CoreWebView2.Settings.AreDevToolsEnabled = false;
        DashboardWebView.CoreWebView2.Settings.IsStatusBarEnabled = false;
        DashboardWebView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
        DashboardWebView.CoreWebView2.WebMessageReceived += DashboardWebView_OnWebMessageReceived;
        DashboardWebView.CoreWebView2.SetVirtualHostNameToFolderMapping(
            "app.neooptimize.local",
            webRoot,
            CoreWebView2HostResourceAccessKind.Allow);
        DashboardWebView.Source = new Uri("https://app.neooptimize.local/index.html");
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
                    status = $"Connected · {DateTimeOffset.Now:HH:mm:ss}",
                    reports = _reportStore.ListReports(),
                },
            });

            AddActivity("Client registered", $"NeoOptimize aktif sebagai {registration.ClientId[..8]}.");
            SendReports();
            SendActivity();
            await RefreshSnapshotAsync(manual: true);
            await ProcessPendingCommandsAsync();
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

        PostMessage(new
        {
            type = "stats",
            payload = new
            {
                cpu = telemetry.CpuPercent ?? 0,
                ram = telemetry.RamPercent ?? 0,
                disk = telemetry.DiskUsagePercent ?? 0,
                temp = telemetry.TemperatureCelsius ?? 0,
                healthState = health.HealthState,
                integrityStatus = health.IntegrityStatus ?? "pending",
                alerts,
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
            });

            PostMessage(new
            {
                type = "aiResponse",
                payload = new
                {
                    reply = response.Reply,
                    plannedActions,
                    dispatched = dispatchActions,
                },
            });

            AddActivity(
                "Neo AI analysis",
                dispatchActions
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
}
