using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System.Collections.ObjectModel;
using System;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class CleanerViewModel : BaseViewModel, IDisposable
    {
        private readonly CleanerService _service;
        public ObservableCollection<string> Logs { get; } = new ObservableCollection<string>();

        public ObservableCollection<CleanerCategoryViewModel> Categories { get; } = new ObservableCollection<CleanerCategoryViewModel>();

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        public IAsyncRelayCommand StartCommand { get; }
        public IRelayCommand StopCommand { get; }
        public IAsyncRelayCommand ExecuteCommand { get; }

        public CleanerViewModel()
        {
            _service = new CleanerService();
            _service.Progress += Service_Progress;
            StartCommand = new AsyncRelayCommand(StartAsync);
            StopCommand = new RelayCommand(() => _service.Stop());
            ExecuteCommand = new AsyncRelayCommand(ExecuteAsync);
        }

        private void Service_Progress(object? sender, CleanerProgressEventArgs e)
        {
            // progress events come from native thread; UI will marshal when bound
            try
            {
                // delegate to testable updater
                UpdateFromEngineJson(e.Json);
            }
            catch { }
        }

        // Public for unit testing
        public void UpdateFromEngineJson(string json)
        {
            try
            {
                Logs.Add(json);
                // try quick parse for progress and optional category
                string category = "default";
                int? p = null;

                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("category", out var catEl) && catEl.ValueKind == System.Text.Json.JsonValueKind.String)
                    {
                        category = catEl.GetString() ?? "default";
                    }
                    if (root.TryGetProperty("progress", out var progEl) && progEl.ValueKind == System.Text.Json.JsonValueKind.Number)
                    {
                        p = progEl.GetInt32();
                    }
                }
                catch { /* fall back to heuristic */ }

                if (p.HasValue)
                {
                    // update aggregate Progress if module-level
                    Progress = p.Value;
                    // update per-category entry
                    var existing = System.Linq.Enumerable.FirstOrDefault(Categories, c => string.Equals(c.Name, category, System.StringComparison.OrdinalIgnoreCase));
                    if (existing != null)
                    {
                        existing.Progress = p.Value;
                    }
                    else
                    {
                        Categories.Add(new CleanerCategoryViewModel(category, p.Value));
                    }
                }
            }
            catch { }
        }

        public Task StartAsync() => _service.StartAsync("{\"categories\":[\"temp\",\"browser\",\"recyclebin\",\"logs\",\"prefetch\",\"thumbnail\",\"windowsupdate\",\"appcache\"],\"dryRun\":true}");

        public Task ExecuteAsync() => _service.ExecuteAsync("{\"categories\":[\"temp\",\"browser\",\"recyclebin\",\"logs\",\"prefetch\",\"thumbnail\",\"windowsupdate\",\"appcache\"],\"dryRun\":false}");

        public void Dispose()
        {
            _service.Progress -= Service_Progress;
            _service.Dispose();
        }
    }
}
