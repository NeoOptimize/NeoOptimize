using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class BackupViewModel : BaseViewModel
    {
        private readonly BackupService _svc = new BackupService();
        public ObservableCollection<BackupInfo> Backups { get; } = new ObservableCollection<BackupInfo>();

        private BackupInfo? _selected;
        public BackupInfo? Selected
        {
            get => _selected; set => SetProperty(ref _selected, value);
        }

        public IAsyncRelayCommand RefreshCommand => new AsyncRelayCommand(RefreshAsync);
        public IAsyncRelayCommand ExploreCommand => new AsyncRelayCommand(ExploreAsync, () => Selected != null);
        public IAsyncRelayCommand DeleteCommand => new AsyncRelayCommand(DeleteAsync, () => Selected != null);

        public BackupViewModel()
        {
            _ = RefreshAsync();
        }

        public async Task RefreshAsync()
        {
            Backups.Clear();
            var list = await _svc.ListBackupsAsync();
            foreach (var b in list) Backups.Add(b);
        }

        public Task ExploreAsync()
        {
            if (Selected == null) return Task.CompletedTask;
            try
            {
                Process.Start(new ProcessStartInfo("explorer.exe", Selected.Path) { UseShellExecute = true });
            }
            catch { }
            return Task.CompletedTask;
        }

        public async Task DeleteAsync()
        {
            if (Selected == null) return;
            var ok = await _svc.DeleteBackupAsync(Selected.Path);
            if (ok) await RefreshAsync();
        }
    }
}
