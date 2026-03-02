namespace NeoOptimize.App.ViewModels;

public sealed class SystemToolsViewModel : ViewModelBase
{
    private bool _createRestorePoint = true;
    private bool _backupRegistry = true;

    public bool CreateRestorePoint
    {
        get => _createRestorePoint;
        set => SetProperty(ref _createRestorePoint, value);
    }

    public bool BackupRegistry
    {
        get => _backupRegistry;
        set => SetProperty(ref _backupRegistry, value);
    }
}
