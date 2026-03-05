using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Threading.Tasks;
using System;

namespace NeoOptimize.UI.ViewModels
{
    public class AppManagerViewModel : BaseViewModel, IDisposable
    {
        private readonly AppManagerService _service = new AppManagerService();
        private static readonly IReadOnlyList<string> DefaultOperations = new[]
        {
            "bloatware_microsoft",
            "startup_disable_all",
            "background_disable_all",
            "app_cache_all",
            "deep_clean_app_data"
        };

        public ObservableCollection<AppInfoViewModel> Apps { get; } = new ObservableCollection<AppInfoViewModel>();
        public ObservableCollection<string> Logs { get; } = new ObservableCollection<string>();

        private AppInfoViewModel? _selectedApp;
        public AppInfoViewModel? SelectedApp
        {
            get => _selectedApp;
            set
            {
                if (SetProperty(ref _selectedApp, value))
                {
                    UninstallCommand.NotifyCanExecuteChanged();
                }
            }
        }

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        public IAsyncRelayCommand ListAppsCommand { get; }
        public IAsyncRelayCommand UninstallCommand { get; }
        public IAsyncRelayCommand RunMaintenanceCommand { get; }

        public AppManagerViewModel()
        {
            _service.Progress += OnServiceProgress;
            ListAppsCommand = new AsyncRelayCommand(ListAppsAsync);
            UninstallCommand = new AsyncRelayCommand(UninstallAsync, () => SelectedApp != null);
            RunMaintenanceCommand = new AsyncRelayCommand(RunMaintenanceAsync);
        }

        private void OnServiceProgress(string json)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(json) || json.IndexOf("\"module\":\"appmanager\"", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    return;
                }

                Logs.Add(json);
                var idx = json.IndexOf("\"progress\":", StringComparison.OrdinalIgnoreCase);
                if (idx >= 0)
                {
                    var substr = json.Substring(idx + 11);
                    int end = substr.IndexOfAny(new char[] { ',', '}', '"' });
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

        private async Task ListAppsAsync()
        {
            var list = await _service.ListInstalledAppsAsync();
            Apps.Clear();
            foreach (var a in list)
            {
                Apps.Add(new AppInfoViewModel(a.Id, a.Name, a.Scope, a.Publisher, a.Uninstall, a.QuietUninstall));
            }
            OnPropertyChanged(nameof(Apps));
        }

        private async Task UninstallAsync()
        {
            if (SelectedApp == null) return;
            await _service.UninstallAppAsync(SelectedApp.Id);
        }

        private Task RunMaintenanceAsync()
        {
            return _service.RunOperationsAsync(DefaultOperations);
        }

        public void Dispose()
        {
            _service.Progress -= OnServiceProgress;
            _service.Dispose();
        }
    }

    public class AppInfoViewModel : BaseViewModel
    {
        public string Id { get; }
        public string Name { get; }
        public string Scope { get; }
        public string Publisher { get; }
        public string Uninstall { get; }
        public string QuietUninstall { get; }
        public AppInfoViewModel(string id, string name, string scope, string publisher, string uninstall, string quietUninstall)
        {
            Id = id;
            Name = name;
            Scope = scope;
            Publisher = publisher;
            Uninstall = uninstall;
            QuietUninstall = quietUninstall;
        }
        public override string ToString() => Name;
    }
}
