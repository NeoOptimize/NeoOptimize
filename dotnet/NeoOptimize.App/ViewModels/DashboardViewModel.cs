namespace NeoOptimize.App.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private string _lastQuickAction = "Ready";

    public string LastQuickAction
    {
        get => _lastQuickAction;
        set => SetProperty(ref _lastQuickAction, value);
    }

    public string StatusNote => "Progressive disclosure: mode simple menampilkan kontrol inti, mode advanced membuka modul lanjutan.";
}
