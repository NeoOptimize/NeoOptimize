namespace NeoOptimize.App.ViewModels;

public sealed class SecurityViewModel : ViewModelBase
{
    private bool _useClamAv = true;
    private bool _useKicomAv = true;
    private bool _useDefenderToggle;
    private bool _usbAutorunBlockerEnabled = true;

    public bool UseClamAv
    {
        get => _useClamAv;
        set => SetProperty(ref _useClamAv, value);
    }

    public bool UseKicomAv
    {
        get => _useKicomAv;
        set => SetProperty(ref _useKicomAv, value);
    }

    public bool UseDefenderToggle
    {
        get => _useDefenderToggle;
        set => SetProperty(ref _useDefenderToggle, value);
    }

    public bool UsbAutorunBlockerEnabled
    {
        get => _usbAutorunBlockerEnabled;
        set => SetProperty(ref _usbAutorunBlockerEnabled, value);
    }
}
