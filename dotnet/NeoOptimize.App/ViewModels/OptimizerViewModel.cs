namespace NeoOptimize.App.ViewModels;

public sealed class OptimizerViewModel : ViewModelBase
{
    private bool _privacyPackEnabled = true;
    private bool _manualCpuTuning;
    private bool _manualRamTuning;
    private bool _manualDiskTuning;
    private bool _manualNetworkTuning;

    public bool PrivacyPackEnabled
    {
        get => _privacyPackEnabled;
        set => SetProperty(ref _privacyPackEnabled, value);
    }

    public bool ManualCpuTuning
    {
        get => _manualCpuTuning;
        set => SetProperty(ref _manualCpuTuning, value);
    }

    public bool ManualRamTuning
    {
        get => _manualRamTuning;
        set => SetProperty(ref _manualRamTuning, value);
    }

    public bool ManualDiskTuning
    {
        get => _manualDiskTuning;
        set => SetProperty(ref _manualDiskTuning, value);
    }

    public bool ManualNetworkTuning
    {
        get => _manualNetworkTuning;
        set => SetProperty(ref _manualNetworkTuning, value);
    }
}
