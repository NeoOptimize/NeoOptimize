namespace NeoOptimize.App.ViewModels;

public sealed class CleanerViewModel : ViewModelBase
{
    private bool _advancedMode;
    private bool _includeRegistry;
    private bool _includeDriverLeftovers;
    private bool _includeBloatware;

    public bool AdvancedMode
    {
        get => _advancedMode;
        set
        {
            if (!SetProperty(ref _advancedMode, value)) return;
            if (_advancedMode) return;
            IncludeRegistry = false;
            IncludeDriverLeftovers = false;
            IncludeBloatware = false;
        }
    }

    public bool IncludeRegistry
    {
        get => _includeRegistry;
        set => SetProperty(ref _includeRegistry, value);
    }

    public bool IncludeDriverLeftovers
    {
        get => _includeDriverLeftovers;
        set => SetProperty(ref _includeDriverLeftovers, value);
    }

    public bool IncludeBloatware
    {
        get => _includeBloatware;
        set => SetProperty(ref _includeBloatware, value);
    }
}
