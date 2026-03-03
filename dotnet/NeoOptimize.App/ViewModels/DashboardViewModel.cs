using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Input;
using NeoOptimize.Core;

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

    public ObservableCollection<LogFileInfo> Logs { get; } = new ObservableCollection<LogFileInfo>();

    public TraySettings MiniTraySettings { get; } = new TraySettings();

    public ICommand RefreshLogsCommand { get; }
    public ICommand DeleteLogCommand { get; }
    public ICommand ExportLogCommand { get; }

    private TrayService _trayService;

    public DashboardViewModel()
    {
        RefreshLogsCommand = new RelayCommand(async _ => await RefreshLogsAsync());
        DeleteLogCommand = new RelayCommand(async p => await DeleteLogAsync(p as LogFileInfo));
        ExportLogCommand = new RelayCommand(async p => await ExportLogAsync(p as LogFileInfo));

        // start tray service with settings and hook to append logs
        _trayService = new TrayService(MiniTraySettings);
        _trayService.OnActionExecuted += async (msg) =>
        {
            await LogManager.AppendAsync(msg);
            await RefreshLogsAsync();
        };
        _trayService.Start();

        // initial load
        _ = RefreshLogsAsync();
    }

    private Task RefreshLogsAsync()
    {
        Logs.Clear();
        foreach (var l in LogManager.GetAllLogs())
            Logs.Add(l);
        return Task.CompletedTask;
    }

    private async Task DeleteLogAsync(LogFileInfo file)
    {
        if (file == null) return;
        LogManager.DeleteLog(file.Path);
        await RefreshLogsAsync();
    }

    private async Task ExportLogAsync(LogFileInfo file)
    {
        if (file == null) return;
        try
        {
            var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            var dest = Path.Combine(desktop, Path.GetFileNameWithoutExtension(file.DisplayName) + ".zip");
            var ok = LogManager.ExportLog(file.Path, dest);
            if (ok)
            {
                await LogManager.AppendAsync($"Log exported: {dest}");
                await RefreshLogsAsync();
            }
        }
        catch { }
    }
}

