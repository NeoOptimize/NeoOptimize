using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Input;
using NeoOptimize.AIAdvisor;
using NeoOptimize.AIAdvisor.Models;
using NeoOptimize.App.Helpers;
using NeoOptimize.Core;
using NeoOptimize.Core.Models;
using NeoOptimize.Services;

namespace NeoOptimize.App.ViewModels;

public sealed class MainWindowViewModel : ViewModelBase
{
    private readonly CleanerEngine _cleanerEngine;
    private readonly OptimizerEngine _optimizerEngine;
    private readonly SystemToolsEngine _systemToolsEngine;
    private readonly SecurityEngine _securityEngine;
    private readonly LogManager _logManager;
    private readonly Scheduler _scheduler;
    private readonly TrayService _trayService;
    private readonly UpdateService _updateService;
    private readonly LocalizationService _localizationService;
    private readonly IAiAdvisor _aiAdvisor;
    private readonly AsyncRelayCommand _askAiCommand;
    private readonly Random _random = new();
    private readonly DateTimeOffset _sessionStartedAt = DateTimeOffset.Now;

    private double _cpuUsagePercent;
    private double _memoryUsagePercent;
    private double _diskUsagePercent;
    private double _networkUsageMbps;
    private double _networkLatencyMs;
    private string _sessionUptime = "00:00:00";
    private string _healthStatus = "Optimal";
    private string _lastActionStatus = "Ready.";
    private string _updateStatus = "Offline-first mode active.";
    private string _aiProviderName = "RuleBased";
    private string _aiRecommendation = "AI advisor siap. Tekan Ask AI untuk rekomendasi.";
    private bool _isAiBusy;
    private bool _miniTrayAutoCleanEnabled = true;
    private bool _miniTrayPreShutdownCleanerEnabled;
    private string _miniTrayAiTip = "Sistem stabil. Auto Clean standby setiap 20 menit.";

    public MainWindowViewModel(
        CleanerEngine cleanerEngine,
        OptimizerEngine optimizerEngine,
        SystemToolsEngine systemToolsEngine,
        SecurityEngine securityEngine,
        LogManager logManager,
        Scheduler scheduler,
        TrayService trayService,
        UpdateService updateService,
        LocalizationService localizationService,
        RemoteAssistService remoteAssistService,
        IAiAdvisor aiAdvisor)
    {
        _cleanerEngine = cleanerEngine;
        _optimizerEngine = optimizerEngine;
        _systemToolsEngine = systemToolsEngine;
        _securityEngine = securityEngine;
        _logManager = logManager;
        _scheduler = scheduler;
        _trayService = trayService;
        _updateService = updateService;
        _localizationService = localizationService;
        _aiAdvisor = aiAdvisor;

        Dashboard = new DashboardViewModel();
        Cleaner = new CleanerViewModel();
        Optimizer = new OptimizerViewModel();
        SystemTools = new SystemToolsViewModel();
        Security = new SecurityViewModel();
        Settings = new SettingsViewModel();
        Support = new SupportViewModel();

        RefreshDashboardCommand = new RelayCommand(RefreshDashboard);
        SmartCleanCommand = new RelayCommand(ExecuteSmartClean);
        SmartOptimizeCommand = new RelayCommand(ExecuteSmartOptimize);
        SmartFixCommand = new RelayCommand(ExecuteSmartFix);
        UnifiedScanCommand = new RelayCommand(ExecuteUnifiedScan);
        AskAiCommand = _askAiCommand = new AsyncRelayCommand(AskAiAsync, () => !IsAiBusy);

        var updateResult = _updateService.CheckForUpdates(onlineModeEnabled: false);
        UpdateStatus = updateResult.Message;

        var draftTicket = remoteAssistService.CreateDraftTicket(Environment.MachineName);
        Support.DraftTicketId = draftTicket.TicketId;

        foreach (var task in _scheduler.GetAll())
        {
            ActivityLog.Add($"{DateTimeOffset.Now:HH:mm:ss} [Scheduler] {task.Id} {task.Description}");
        }

        RefreshDashboard();
        AppendAction("System", "Startup", OperationResult.Ok("NeoOptimize WPF + AI advisor scaffold is running."));
    }

    public DashboardViewModel Dashboard { get; }
    public CleanerViewModel Cleaner { get; }
    public OptimizerViewModel Optimizer { get; }
    public SystemToolsViewModel SystemTools { get; }
    public SecurityViewModel Security { get; }
    public SettingsViewModel Settings { get; }
    public SupportViewModel Support { get; }
    public ObservableCollection<string> ActivityLog { get; } = new();

    public double CpuUsagePercent
    {
        get => _cpuUsagePercent;
        private set => SetProperty(ref _cpuUsagePercent, value);
    }

    public double MemoryUsagePercent
    {
        get => _memoryUsagePercent;
        private set => SetProperty(ref _memoryUsagePercent, value);
    }

    public double DiskUsagePercent
    {
        get => _diskUsagePercent;
        private set => SetProperty(ref _diskUsagePercent, value);
    }

    public double NetworkUsageMbps
    {
        get => _networkUsageMbps;
        private set => SetProperty(ref _networkUsageMbps, value);
    }

    public double NetworkLatencyMs
    {
        get => _networkLatencyMs;
        private set => SetProperty(ref _networkLatencyMs, value);
    }

    public string SessionUptime
    {
        get => _sessionUptime;
        private set => SetProperty(ref _sessionUptime, value);
    }

    public string HealthStatus
    {
        get => _healthStatus;
        private set => SetProperty(ref _healthStatus, value);
    }

    public string LastActionStatus
    {
        get => _lastActionStatus;
        private set => SetProperty(ref _lastActionStatus, value);
    }

    public string UpdateStatus
    {
        get => _updateStatus;
        set => SetProperty(ref _updateStatus, value);
    }

    public string AiProviderName
    {
        get => _aiProviderName;
        private set => SetProperty(ref _aiProviderName, value);
    }

    public string AiRecommendation
    {
        get => _aiRecommendation;
        private set => SetProperty(ref _aiRecommendation, value);
    }

    public bool IsAiBusy
    {
        get => _isAiBusy;
        private set
        {
            if (!SetProperty(ref _isAiBusy, value)) return;
            Notify(nameof(AskAiButtonText));
        }
    }

    public string AskAiButtonText => IsAiBusy ? "Analyzing..." : "Ask AI";

    public int MiniTrayAutoCleanIntervalMinutes => 20;

    public bool MiniTrayAutoCleanEnabled
    {
        get => _miniTrayAutoCleanEnabled;
        set
        {
            if (!SetProperty(ref _miniTrayAutoCleanEnabled, value)) return;
            UpdateMiniTrayTip(Array.Empty<string>());
            AppendAction(
                "Mini Tray",
                "Auto Clean Toggle",
                OperationResult.Ok(
                    value ? "Auto Clean 20 menit diaktifkan." : "Auto Clean dimatikan.",
                    new Dictionary<string, string>
                    {
                        ["enabled"] = value ? "true" : "false",
                        ["interval_minutes"] = MiniTrayAutoCleanIntervalMinutes.ToString()
                    }));
        }
    }

    public bool MiniTrayPreShutdownCleanerEnabled
    {
        get => _miniTrayPreShutdownCleanerEnabled;
        set
        {
            if (!SetProperty(ref _miniTrayPreShutdownCleanerEnabled, value)) return;
            UpdateMiniTrayTip(Array.Empty<string>());
            AppendAction(
                "Mini Tray",
                "Pre-Shutdown Toggle",
                OperationResult.Ok(
                    value ? "Pre-shutdown cleaner diaktifkan." : "Pre-shutdown cleaner dimatikan.",
                    new Dictionary<string, string>
                    {
                        ["enabled"] = value ? "true" : "false"
                    }));
        }
    }

    public string MiniTrayAiTip
    {
        get => _miniTrayAiTip;
        private set => SetProperty(ref _miniTrayAiTip, value);
    }

    public ICommand RefreshDashboardCommand { get; }
    public ICommand SmartCleanCommand { get; }
    public ICommand SmartOptimizeCommand { get; }
    public ICommand SmartFixCommand { get; }
    public ICommand UnifiedScanCommand { get; }
    public ICommand AskAiCommand { get; }

    private SystemSnapshot BuildSnapshot() => new(
        CpuUsagePercent,
        MemoryUsagePercent,
        DiskUsagePercent,
        NetworkUsageMbps,
        DateTimeOffset.Now);

    private void RefreshDashboard()
    {
        CpuUsagePercent = Math.Round(15 + (_random.NextDouble() * 75), 1);
        MemoryUsagePercent = Math.Round(20 + (_random.NextDouble() * 70), 1);
        DiskUsagePercent = Math.Round(30 + (_random.NextDouble() * 55), 1);
        NetworkUsageMbps = Math.Round(8 + (_random.NextDouble() * 140), 1);
        NetworkLatencyMs = Math.Round(6 + (_random.NextDouble() * 40), 1);

        var peak = new[] { CpuUsagePercent, MemoryUsagePercent, DiskUsagePercent }.Max();
        if (peak >= 85)
        {
            HealthStatus = _localizationService.Translate(Settings.Language, "health.critical");
        }
        else if (peak >= 65)
        {
            HealthStatus = _localizationService.Translate(Settings.Language, "health.warning");
        }
        else
        {
            HealthStatus = _localizationService.Translate(Settings.Language, "health.optimal");
        }

        Dashboard.LastQuickAction = "Snapshot refreshed";

        var suggestions = _trayService.EvaluateThresholds(BuildSnapshot());
        if (suggestions.Count > 0)
        {
            LastActionStatus = $"Mini Tray AI: {string.Join(" | ", suggestions)}";
        }

        UpdateMiniTrayTip(suggestions);
        UpdateSessionUptime();
    }

    private void ExecuteSmartClean()
    {
        var result = _cleanerEngine.RunSmartClean(
            Cleaner.AdvancedMode,
            Cleaner.IncludeRegistry,
            Cleaner.IncludeDriverLeftovers,
            Cleaner.IncludeBloatware);

        AppendAction("Cleaner", "Smart Clean", result);
    }

    private void ExecuteSmartOptimize()
    {
        var result = _optimizerEngine.RunSmartOptimize(
            BuildSnapshot(),
            Optimizer.PrivacyPackEnabled,
            Optimizer.ManualCpuTuning,
            Optimizer.ManualRamTuning,
            Optimizer.ManualDiskTuning,
            Optimizer.ManualNetworkTuning);

        AppendAction("Optimizer", "Smart Optimize", result);
    }

    private void ExecuteSmartFix()
    {
        var result = _systemToolsEngine.RunSystemRepair(
            SystemTools.CreateRestorePoint,
            SystemTools.BackupRegistry);

        AppendAction("System Tools", "Smart Fix", result);
    }

    private void ExecuteUnifiedScan()
    {
        var profile = new SecurityScanProfile(
            Security.UseClamAv,
            Security.UseKicomAv,
            Security.UseDefenderToggle);

        var result = _securityEngine.RunUnifiedScan(profile, Security.UsbAutorunBlockerEnabled);
        AppendAction("Security", "Unified Scan", result);
    }

    private async Task AskAiAsync()
    {
        if (IsAiBusy) return;
        IsAiBusy = true;
        _askAiCommand.RaiseCanExecuteChanged();

        try
        {
            var request = new AiAdviceRequest(
                BuildSnapshot(),
                ActivityLog.Take(40).ToArray(),
                Settings.ExperienceMode,
                Settings.Language,
                DateTimeOffset.Now);

            var response = await _aiAdvisor.GetAdviceAsync(request, CancellationToken.None).ConfigureAwait(true);
            AiProviderName = response.Provider;
            AiRecommendation = response.Recommendation;

            var result = response.Success
                ? OperationResult.Ok(response.Recommendation, new Dictionary<string, string> { ["provider"] = response.Provider })
                : OperationResult.Fail(response.Recommendation);
            AppendAction("AI Advisor", "Ask AI", result);
        }
        catch (Exception ex)
        {
            var message = $"AI advisor error: {ex.Message}";
            AiRecommendation = message;
            AppendAction("AI Advisor", "Ask AI", OperationResult.Fail(message));
        }
        finally
        {
            IsAiBusy = false;
            _askAiCommand.RaiseCanExecuteChanged();
        }
    }

    private void AppendAction(string module, string action, OperationResult result)
    {
        var entry = _logManager.Append(module, action, result);
        var metricSummary = entry.Metrics is { Count: > 0 }
            ? string.Join(", ", entry.Metrics.Select(kv => $"{kv.Key}={kv.Value}"))
            : "-";

        ActivityLog.Insert(
            0,
            $"{entry.Timestamp:HH:mm:ss} [{entry.Module}] {entry.Action} => {entry.Result} | {entry.Message} | {metricSummary}");

        if (ActivityLog.Count > 300)
        {
            ActivityLog.RemoveAt(ActivityLog.Count - 1);
        }

        LastActionStatus = $"{module}: {result.Message}";
        Dashboard.LastQuickAction = action;
        UpdateSessionUptime();
    }

    private void UpdateMiniTrayTip(IReadOnlyList<string> suggestions)
    {
        if (!MiniTrayAutoCleanEnabled && !MiniTrayPreShutdownCleanerEnabled)
        {
            MiniTrayAiTip = "Mini Tray pasif. Aktifkan Auto Clean atau Pre-Shutdown Cleaner.";
            return;
        }

        if (suggestions.Count > 0)
        {
            MiniTrayAiTip = suggestions[0];
            return;
        }

        if (CpuUsagePercent > 70)
        {
            MiniTrayAiTip = "CPU mulai tinggi. Jalankan Smart Optimize untuk jaga respons sistem.";
            return;
        }

        MiniTrayAiTip = "Semua indikator stabil. Sistem dalam kondisi optimal.";
    }

    private void UpdateSessionUptime()
    {
        var elapsed = DateTimeOffset.Now - _sessionStartedAt;
        SessionUptime = $"{(int)elapsed.TotalHours:00}:{elapsed.Minutes:00}:{elapsed.Seconds:00}";
    }
}
