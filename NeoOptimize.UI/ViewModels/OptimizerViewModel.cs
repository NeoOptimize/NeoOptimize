using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System.Collections.ObjectModel;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class OptimizerViewModel : BaseViewModel, IDisposable
    {
        private readonly OptimizerService _service;
        private static readonly IReadOnlyList<string> DefaultOperations = new[]
        {
            "sfc_scannow",
            "dism_checkhealth",
            "dism_restorehealth",
            "privacy_activity_history",
            "privacy_telemetry",
            "privacy_advertising_id",
            "net_flush_dns",
            "perf_power_plan"
        };
        public ObservableCollection<string> Logs { get; } = new ObservableCollection<string>();

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        public IAsyncRelayCommand StartCommand { get; }
        public IRelayCommand StopCommand { get; }

        public OptimizerViewModel()
        {
            _service = new OptimizerService();
            _service.Progress += Service_Progress;
            StartCommand = new AsyncRelayCommand(StartAsync);
            StopCommand = new RelayCommand(() => _service.Stop());
        }

        private void Service_Progress(object? sender, OptimizerProgressEventArgs e)
        {
            try
            {
                Logs.Add(e.Json);
                var idx = e.Json.IndexOf("\"progress\":", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    var substr = e.Json.Substring(idx + 11);
                    int end = substr.IndexOfAny(new char[] { ',', '}', '"' });
                    if (end > 0 && int.TryParse(substr.Substring(0, end), out var p))
                    {
                        Progress = p;
                    }
                }
            }
            catch { }
        }

        public Task StartAsync() => _service.StartOperationsAsync(DefaultOperations);

        public void Dispose()
        {
            _service.Progress -= Service_Progress;
            _service.Dispose();
        }
    }
}
