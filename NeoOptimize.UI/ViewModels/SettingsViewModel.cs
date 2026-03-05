using CommunityToolkit.Mvvm.Input;
using NeoOptimize.UI.Services;
using System.Collections.ObjectModel;
using System.Threading.Tasks;

namespace NeoOptimize.UI.ViewModels
{
    public class SettingsViewModel : BaseViewModel
    {
        private readonly SettingsService _service = new SettingsService();

        public ObservableCollection<string> ThemeOptions { get; } = new ObservableCollection<string>
        {
            "System",
            "Light",
            "Dark"
        };

        public ObservableCollection<string> LanguageOptions { get; } = new ObservableCollection<string>
        {
            "English",
            "Indonesia"
        };

        private string _theme = "System";
        public string Theme
        {
            get => _theme;
            set => SetProperty(ref _theme, value);
        }

        private string _language = "English";
        public string Language
        {
            get => _language;
            set => SetProperty(ref _language, value);
        }

        private bool _autoUpdate = true;
        public bool AutoUpdate
        {
            get => _autoUpdate;
            set => SetProperty(ref _autoUpdate, value);
        }

        private string _currentVersion = "1.0.0";
        public string CurrentVersion
        {
            get => _currentVersion;
            set => SetProperty(ref _currentVersion, value);
        }

        private string _clamAvPath = @"C:\Program Files\ClamAV";
        public string ClamAvPath
        {
            get => _clamAvPath;
            set => SetProperty(ref _clamAvPath, value);
        }

        private string _gpt4AllModel = "mistral-7b.gguf";
        public string Gpt4AllModel
        {
            get => _gpt4AllModel;
            set => SetProperty(ref _gpt4AllModel, value);
        }

        private string _status = string.Empty;
        public string Status
        {
            get => _status;
            set => SetProperty(ref _status, value);
        }

        public IAsyncRelayCommand LoadCommand { get; }
        public IAsyncRelayCommand SaveCommand { get; }

        public SettingsViewModel()
        {
            LoadCommand = new AsyncRelayCommand(LoadAsync);
            SaveCommand = new AsyncRelayCommand(SaveAsync);
            _ = LoadAsync();
        }

        public async Task LoadAsync()
        {
            var settings = await _service.LoadAsync();
            Theme = settings.Theme;
            Language = settings.Language;
            AutoUpdate = settings.AutoUpdate;
            CurrentVersion = settings.CurrentVersion;
            ClamAvPath = settings.ClamAvPath;
            Gpt4AllModel = settings.Gpt4AllModel;
            Status = "Settings loaded";
        }

        public async Task SaveAsync()
        {
            var settings = new AppSettings
            {
                Theme = Theme,
                Language = Language,
                AutoUpdate = AutoUpdate,
                CurrentVersion = CurrentVersion,
                ClamAvPath = ClamAvPath,
                Gpt4AllModel = Gpt4AllModel
            };

            bool ok = await _service.SaveAsync(settings);
            Status = ok ? "Settings saved" : "Save failed";
        }
    }
}
