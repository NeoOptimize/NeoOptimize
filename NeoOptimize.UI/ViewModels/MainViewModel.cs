using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.ViewModels;

namespace NeoOptimize.UI.ViewModels
{
    public class MainViewModel : BaseViewModel
    {
        public DashboardViewModel Dashboard { get; }
        public CleanerViewModel Cleaner { get; }
        public AppManagerViewModel AppManager { get; }
        public OptimizerViewModel Optimizer { get; }
        public SecurityViewModel Security { get; }
        public SchedulerViewModel Scheduler { get; }
        public SettingsViewModel Settings { get; }
        public BackupViewModel Backups { get; }

        private string _engineVersion = string.Empty;
        public string EngineVersion
        {
            get => _engineVersion;
            set => SetProperty(ref _engineVersion, value);
        }

        public IRelayCommand? RefreshEngineVersionCommand { get; private set; }

        public MainViewModel()
        {
            Dashboard = new DashboardViewModel();
            Cleaner = new CleanerViewModel();
            AppManager = new AppManagerViewModel();
            Optimizer = new OptimizerViewModel();
            Security = new SecurityViewModel();
            Scheduler = new SchedulerViewModel();
            Settings = new SettingsViewModel();
            Backups = new BackupViewModel();

            RefreshEngineVersionCommand = new CommunityToolkit.Mvvm.Input.RelayCommand(RefreshEngineVersion);
            RefreshEngineVersion();
        }

        public void Dispose()
        {
            Dashboard.Dispose();
            Cleaner.Dispose();
            AppManager.Dispose();
            Optimizer.Dispose();
            Security.Dispose();
            Scheduler.Dispose();
            
        }

        private void RefreshEngineVersion()
        {
            try
            {
                EngineVersion = NeoOptimize.UI.Services.EngineInterop.GetVersion();
            }
            catch { EngineVersion = string.Empty; }
        }
    }
}
