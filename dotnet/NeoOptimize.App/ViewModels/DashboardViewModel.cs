namespace NeoOptimize.App.ViewModels;

public sealed class DashboardViewModel : ViewModelBase
{
    private string _lastQuickAction = "Ready";

    public string LastQuickAction
    {
        get => _lastQuickAction;
        set => SetProperty(ref _lastQuickAction, value);
    }

    public string StatusNote => "Core hub active. Gunakan quick actions untuk clean/optimize/fix, lalu monitor hasil di log stream.";
}
