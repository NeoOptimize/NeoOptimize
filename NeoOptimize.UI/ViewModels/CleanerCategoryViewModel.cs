using CommunityToolkit.Mvvm.ComponentModel;

namespace NeoOptimize.UI.ViewModels
{
    public class CleanerCategoryViewModel : ObservableObject
    {
        private string _name = string.Empty;
        public string Name
        {
            get => _name;
            set => SetProperty(ref _name, value);
        }

        private int _progress;
        public int Progress
        {
            get => _progress;
            set => SetProperty(ref _progress, value);
        }

        public CleanerCategoryViewModel(string name, int progress = 0)
        {
            _name = name;
            _progress = progress;
        }
    }
}
