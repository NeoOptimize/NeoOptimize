using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class SchedulerViewModel : BaseViewModel, IDisposable
    {
        private readonly SchedulerService _service;

        public ObservableCollection<string> Logs { get; } = new ObservableCollection<string>();

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        public IAsyncRelayCommand ApplyRecommendedCommand { get; }
        public IAsyncRelayCommand StartupDelayCommand { get; }
        public IAsyncRelayCommand Periodic5Command { get; }
        public IAsyncRelayCommand Periodic10Command { get; }
        public IAsyncRelayCommand Periodic30Command { get; }
        public IAsyncRelayCommand Periodic60Command { get; }
        public IAsyncRelayCommand CleanBeforeShutdownCommand { get; }
        public IRelayCommand StopCommand { get; }

        public SchedulerViewModel()
        {
            _service = new SchedulerService();
            _service.Progress += OnProgress;

            ApplyRecommendedCommand = new AsyncRelayCommand(ApplyRecommendedAsync);
            StartupDelayCommand = new AsyncRelayCommand(StartupDelayAsync);
            Periodic5Command = new AsyncRelayCommand(Periodic5Async);
            Periodic10Command = new AsyncRelayCommand(Periodic10Async);
            Periodic30Command = new AsyncRelayCommand(Periodic30Async);
            Periodic60Command = new AsyncRelayCommand(Periodic60Async);
            CleanBeforeShutdownCommand = new AsyncRelayCommand(CleanBeforeShutdownAsync);
            StopCommand = new RelayCommand(() => _service.Stop());
        }

        private void OnProgress(object? sender, SchedulerProgressEventArgs e)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(e.Json) || e.Json.IndexOf("\"module\":\"scheduler\"", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    return;
                }

                Logs.Add(e.Json);
                var idx = e.Json.IndexOf("\"progress\":", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    var substr = e.Json.Substring(idx + 11);
                    int end = substr.IndexOfAny(new[] { ',', '}', '"' });
                    if (end > 0 && int.TryParse(substr.Substring(0, end), out var p))
                    {
                        Progress = p;
                    }
                }
            }
            catch
            {
            }
        }

        private Task ApplyRecommendedAsync() => _service.StartOperationsAsync(new[] { "ai_recommended_schedule" });

        private Task StartupDelayAsync() => _service.StartOperationsAsync(new[] { "startup_delay_5min" });

        private Task Periodic5Async() => _service.StartOperationsAsync(new[] { "periodic_5min" });

        private Task Periodic10Async() => _service.StartOperationsAsync(new[] { "periodic_10min" });

        private Task Periodic30Async() => _service.StartOperationsAsync(new[] { "periodic_30min" });

        private Task Periodic60Async() => _service.StartOperationsAsync(new[] { "periodic_60min" });

        private Task CleanBeforeShutdownAsync() => _service.StartOperationsAsync(new[] { "clean_before_shutdown" });

        public void Dispose()
        {
            _service.Progress -= OnProgress;
            _service.Dispose();
        }
    }
}
