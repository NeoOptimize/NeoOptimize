using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class SecurityViewModel : BaseViewModel, IDisposable
    {
        private readonly SecurityService _service;

        private static readonly IReadOnlyList<string> QuickScanOps = new[]
        {
            "clamav_quick_scan"
        };

        private static readonly IReadOnlyList<string> FullScanOps = new[]
        {
            "clamav_full_scan"
        };

        private static readonly IReadOnlyList<string> KicomavOps = new[]
        {
            "kicomav_scan_folder"
        };

        public ObservableCollection<string> Logs { get; } = new ObservableCollection<string>();

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        private bool _realtimeEnabled;
        public bool RealtimeEnabled
        {
            get => _realtimeEnabled;
            set => SetProperty(ref _realtimeEnabled, value);
        }

        public IAsyncRelayCommand QuickScanCommand { get; }
        public IAsyncRelayCommand FullScanCommand { get; }
        public IAsyncRelayCommand KicomavScanCommand { get; }
        public IAsyncRelayCommand ToggleRealtimeCommand { get; }
        public IRelayCommand StopCommand { get; }

        public SecurityViewModel()
        {
            _service = new SecurityService();
            _service.Progress += OnProgress;

            QuickScanCommand = new AsyncRelayCommand(QuickScanAsync);
            FullScanCommand = new AsyncRelayCommand(FullScanAsync);
            KicomavScanCommand = new AsyncRelayCommand(KicomavScanAsync);
            ToggleRealtimeCommand = new AsyncRelayCommand(ToggleRealtimeAsync);
            StopCommand = new RelayCommand(() => _service.Stop());
        }

        private void OnProgress(object? sender, SecurityProgressEventArgs e)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(e.Json) || e.Json.IndexOf("\"module\":\"security\"", StringComparison.OrdinalIgnoreCase) < 0)
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

        private Task QuickScanAsync() => _service.StartOperationsAsync(QuickScanOps);

        private Task FullScanAsync() => _service.StartOperationsAsync(FullScanOps);

        private Task KicomavScanAsync() => _service.StartOperationsAsync(KicomavOps);

        private Task ToggleRealtimeAsync()
        {
            var op = RealtimeEnabled ? "realtime_protection_disable" : "realtime_protection_enable";
            RealtimeEnabled = !RealtimeEnabled;
            return _service.StartOperationsAsync(new[] { op });
        }

        public void Dispose()
        {
            _service.Progress -= OnProgress;
            _service.Dispose();
        }
    }
}

