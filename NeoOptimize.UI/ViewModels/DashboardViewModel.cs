using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Dispatching;
using NeoOptimize.UI.Services;
using System;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class DashboardViewModel : BaseViewModel, IDisposable
    {
        private readonly SystemMetricsService _metricsService = new SystemMetricsService();
        private readonly ActivityLogService _logService = new ActivityLogService();
        private readonly AiService _aiService = new AiService();
        private readonly DispatcherQueue? _dispatcher;
        private readonly CancellationTokenSource _cts = new CancellationTokenSource();
        private readonly SemaphoreSlim _refreshGate = new SemaphoreSlim(1, 1);

        private bool _disposed;
        private SystemMetricsSnapshot _latestSnapshot = new SystemMetricsSnapshot();

        public ObservableCollection<string> ActivityLogs { get; } = new ObservableCollection<string>();
        public ObservableCollection<AiMessageItem> AiMessages { get; } = new ObservableCollection<AiMessageItem>();

        private double _cpuUsagePercent;
        public double CpuUsagePercent
        {
            get => _cpuUsagePercent;
            private set
            {
                if (SetProperty(ref _cpuUsagePercent, value))
                {
                    OnPropertyChanged(nameof(CpuUsageText));
                }
            }
        }

        public string CpuUsageText => $"{CpuUsagePercent:0.0}%";

        private double _ramUsagePercent;
        public double RamUsagePercent
        {
            get => _ramUsagePercent;
            private set
            {
                if (SetProperty(ref _ramUsagePercent, value))
                {
                    OnPropertyChanged(nameof(RamUsageText));
                }
            }
        }

        public string RamUsageText => $"{RamUsagePercent:0.0}%";

        private double _diskUsagePercent;
        public double DiskUsagePercent
        {
            get => _diskUsagePercent;
            private set
            {
                if (SetProperty(ref _diskUsagePercent, value))
                {
                    OnPropertyChanged(nameof(DiskUsageText));
                }
            }
        }

        public string DiskUsageText => $"{DiskUsagePercent:0.0}%";

        private double _latencyMs;
        public double LatencyMs
        {
            get => _latencyMs;
            private set
            {
                if (SetProperty(ref _latencyMs, value))
                {
                    OnPropertyChanged(nameof(LatencyText));
                }
            }
        }

        public string LatencyText => $"{LatencyMs:0.0}ms";

        private DateTime _lastUpdated = DateTime.Now;
        public DateTime LastUpdated
        {
            get => _lastUpdated;
            private set
            {
                if (SetProperty(ref _lastUpdated, value))
                {
                    OnPropertyChanged(nameof(LastUpdatedText));
                }
            }
        }

        public string LastUpdatedText => LastUpdated.ToString("HH:mm:ss");

        private string _aiInput = string.Empty;
        public string AiInput
        {
            get => _aiInput;
            set
            {
                if (SetProperty(ref _aiInput, value))
                {
                    SendAiCommand.NotifyCanExecuteChanged();
                }
            }
        }

        private bool _isAiBusy;
        public bool IsAiBusy
        {
            get => _isAiBusy;
            private set
            {
                if (SetProperty(ref _isAiBusy, value))
                {
                    SendAiCommand.NotifyCanExecuteChanged();
                }
            }
        }

        private string _status = "Ready";
        public string Status
        {
            get => _status;
            private set => SetProperty(ref _status, value);
        }

        public IAsyncRelayCommand RefreshMetricsCommand { get; }
        public IAsyncRelayCommand GenerateReportCommand { get; }
        public IAsyncRelayCommand SendAiCommand { get; }
        public IRelayCommand OpenLogsFolderCommand { get; }

        public DashboardViewModel()
        {
            _dispatcher = DispatcherQueue.GetForCurrentThread();

            RefreshMetricsCommand = new AsyncRelayCommand(RefreshMetricsAsync);
            GenerateReportCommand = new AsyncRelayCommand(GenerateReportAsync);
            SendAiCommand = new AsyncRelayCommand(SendAiAsync, CanSendAi);
            OpenLogsFolderCommand = new RelayCommand(OpenLogsFolder);

            AiMessages.Add(new AiMessageItem("NeoAI", "NeoAI · GPT4All ready. Ask AI about optimization or security."));

            EngineInterop.RegisterCallback();
            EngineInterop.ProgressReceived += OnEngineProgress;

            _ = InitializeAsync();
        }

        private async Task InitializeAsync()
        {
            await LoadRecentLogsAsync().ConfigureAwait(false);
            await RefreshMetricsAsync().ConfigureAwait(false);
            _ = MetricsLoopAsync(_cts.Token);
        }

        private async Task LoadRecentLogsAsync()
        {
            var lines = await _logService.ReadRecentLinesAsync().ConfigureAwait(false);
            RunOnUi(() =>
            {
                ActivityLogs.Clear();
                foreach (var line in lines)
                {
                    ActivityLogs.Add(line);
                }
            });
        }

        private async Task MetricsLoopAsync(CancellationToken cancellationToken)
        {
            try
            {
                while (!cancellationToken.IsCancellationRequested)
                {
                    await Task.Delay(TimeSpan.FromSeconds(2), cancellationToken).ConfigureAwait(false);
                    await RefreshMetricsAsync().ConfigureAwait(false);
                }
            }
            catch (OperationCanceledException)
            {
            }
        }

        private async Task RefreshMetricsAsync()
        {
            await _refreshGate.WaitAsync(_cts.Token).ConfigureAwait(false);
            try
            {
                var snapshot = await _metricsService.CaptureAsync(_cts.Token).ConfigureAwait(false);
                _latestSnapshot = snapshot;
                RunOnUi(() =>
                {
                    CpuUsagePercent = snapshot.CpuUsagePercent;
                    RamUsagePercent = snapshot.RamUsagePercent;
                    DiskUsagePercent = snapshot.DiskUsagePercent;
                    LatencyMs = snapshot.LatencyMs;
                    LastUpdated = snapshot.CapturedAt.LocalDateTime;
                    Status = $"Metrics updated ({LastUpdatedText})";
                });
            }
            catch (OperationCanceledException)
            {
            }
            catch
            {
                RunOnUi(() => Status = "Metrics update failed");
            }
            finally
            {
                _refreshGate.Release();
            }
        }

        private void OnEngineProgress(string json)
        {
            _ = ProcessEngineEventAsync(json);
        }

        private async Task ProcessEngineEventAsync(string json)
        {
            try
            {
                string line = await _logService.AppendEngineEventAsync(json).ConfigureAwait(false);
                RunOnUi(() => AddLogLine(line));
            }
            catch
            {
            }
        }

        private bool CanSendAi()
        {
            return !IsAiBusy && !string.IsNullOrWhiteSpace(AiInput);
        }

        private async Task SendAiAsync()
        {
            string question = AiInput?.Trim() ?? string.Empty;
            if (string.IsNullOrEmpty(question))
            {
                return;
            }

            AiInput = string.Empty;
            IsAiBusy = true;

            AddAiMessage("You", question);
            var userLog = await _logService.AppendCustomEventAsync("ai.user", question).ConfigureAwait(false);
            RunOnUi(() => AddLogLine(userLog));

            string answer;
            try
            {
                answer = await _aiService.AskAsync(question, _latestSnapshot, _cts.Token).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                answer = "AI request failed: " + ex.Message;
            }

            AddAiMessage("NeoAI", answer);
            var aiLog = await _logService.AppendCustomEventAsync("ai.assistant", answer).ConfigureAwait(false);
            RunOnUi(() => AddLogLine(aiLog));
            RunOnUi(() => Status = "AI response received");

            IsAiBusy = false;
        }

        private async Task GenerateReportAsync()
        {
            string[] lines;
            if (_dispatcher != null && !_dispatcher.HasThreadAccess)
            {
                lines = ActivityLogs.ToArray();
            }
            else
            {
                lines = ActivityLogs.ToArray();
            }

            string reportPath = await _logService.GenerateHtmlReportAsync(lines).ConfigureAwait(false);
            var logLine = await _logService.AppendCustomEventAsync("report", $"generated: {reportPath}").ConfigureAwait(false);

            RunOnUi(() =>
            {
                AddLogLine(logLine);
                Status = $"Report generated: {reportPath}";
            });
        }

        private void OpenLogsFolder()
        {
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", _logService.LogsRootPath)
                {
                    UseShellExecute = true
                });
            }
            catch
            {
            }
        }

        private void AddAiMessage(string role, string text)
        {
            RunOnUi(() =>
            {
                AiMessages.Add(new AiMessageItem(role, text));
                while (AiMessages.Count > 80)
                {
                    AiMessages.RemoveAt(0);
                }
            });
        }

        private void AddLogLine(string line)
        {
            ActivityLogs.Add(line);
            while (ActivityLogs.Count > 300)
            {
                ActivityLogs.RemoveAt(0);
            }
        }

        private void RunOnUi(Action action)
        {
            if (_dispatcher == null || _dispatcher.HasThreadAccess)
            {
                action();
                return;
            }

            _dispatcher.TryEnqueue(() => action());
        }

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            EngineInterop.ProgressReceived -= OnEngineProgress;
            _cts.Cancel();
            _cts.Dispose();
            _refreshGate.Dispose();
            _metricsService.Dispose();
        }
    }

    public class AiMessageItem
    {
        public string Role { get; }
        public string Text { get; }

        public AiMessageItem(string role, string text)
        {
            Role = role;
            Text = text;
        }
    }
}
