using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using WinForms = System.Windows.Forms;
using System.Net.Http;
using System.Text.Json;
using System.Net.Http.Json;
using System.IO;
using NeoOptimize.AIAdvisor;
using NeoOptimize.App.ViewModels;
using NeoOptimize.Core;
using NeoOptimize.Services;

namespace NeoOptimize.App;

public partial class MainWindow : Window
{
    private WinForms.NotifyIcon? _notifyIcon;
    private WinForms.ToolStripMenuItem? _autoCleanMenuItem;
    private WinForms.ToolStripMenuItem? _preShutdownMenuItem;
    private System.Drawing.Icon? _trayIcon;
    private DispatcherTimer? _autoCleanTimer;
    private bool _exitRequested;
    private bool _isSessionEnding;

    public MainWindow()
    {
        InitializeComponent();

        var loadedSettings = ViewModels.SettingsViewModel.Load();

        var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(Math.Max(1, loadedSettings.Gpt4AllTimeoutSeconds)) };
        var gpt4All = new Gpt4AllAiAdvisor(
            endpoint: string.IsNullOrWhiteSpace(loadedSettings.Gpt4AllEndpoint) ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_ENDPOINT") : loadedSettings.Gpt4AllEndpoint,
            model: null,
            cliPath: string.IsNullOrWhiteSpace(loadedSettings.Gpt4AllCliPath) ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_CLI") : loadedSettings.Gpt4AllCliPath,
            cliArgsTemplate: null,
            httpClient: httpClient);

        var aiAdvisor = new CompositeAiAdvisor(
            new RuleBasedAiAdvisor(),
            gpt4All,
            new RuleBasedAiAdvisor());

        DataContext = new MainWindowViewModel(
            new CleanerEngine(),
            new OptimizerEngine(),
            new SystemToolsEngine(),
            new SecurityEngine(),
            new LogManager(),
            new Scheduler(),
            new TrayService(),
            new UpdateService(),
            new LocalizationService(),
            new RemoteAssistService(),
            aiAdvisor);

        // Apply loaded settings into ViewModel.Settings (copy values)
        if (DataContext is MainWindowViewModel vm)
        {
            vm.Settings.ExperienceMode = loadedSettings.ExperienceMode;
            vm.Settings.Theme = loadedSettings.Theme;
            vm.Settings.Language = loadedSettings.Language;
            vm.Settings.AiProvider = loadedSettings.AiProvider;
            vm.Settings.Gpt4AllCliPath = loadedSettings.Gpt4AllCliPath;
            vm.Settings.Gpt4AllEndpoint = loadedSettings.Gpt4AllEndpoint;
            vm.Settings.Gpt4AllTimeoutSeconds = loadedSettings.Gpt4AllTimeoutSeconds;
        }

        // Start AI health-check in background and report status to UI
        _ = CheckAiHealthAsync(gpt4All, loadedSettings);

        Loaded += OnLoaded;
        StateChanged += OnStateChanged;
        Closing += OnClosing;
        Closed += OnClosed;
        Application.Current.SessionEnding += OnSessionEnding;
    }

    private async Task CheckAiHealthAsync(Gpt4AllAiAdvisor gpt4All, ViewModels.SettingsViewModel loadedSettings)
    {
        try
        {
            var endpointEnv = string.IsNullOrWhiteSpace(loadedSettings.Gpt4AllEndpoint)
                ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_ENDPOINT")
                : loadedSettings.Gpt4AllEndpoint;

            var cliEnv = string.IsNullOrWhiteSpace(loadedSettings.Gpt4AllCliPath)
                ? Environment.GetEnvironmentVariable("NEO_GPT4ALL_CLI")
                : loadedSettings.Gpt4AllCliPath;

            string status;

            if (!string.IsNullOrWhiteSpace(cliEnv) && File.Exists(cliEnv))
            {
                status = $"AI: GPT4All CLI available ({Path.GetFileName(cliEnv)}).";
            }
            else if (!string.IsNullOrWhiteSpace(endpointEnv))
            {
                // Quick HTTP health check
                using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };

                var payload = new
                {
                    model = "health-check",
                    messages = new[] { new { role = "user", content = "health check" } }
                };

                try
                {
                    using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(3));
                    var resp = await http.PostAsJsonAsync(endpointEnv, payload, cts.Token).ConfigureAwait(false);
                    if (resp.IsSuccessStatusCode)
                    {
                        status = "AI: GPT4All HTTP endpoint reachable.";
                    }
                    else
                    {
                        status = $"AI: GPT4All HTTP unreachable (status {(int)resp.StatusCode}).";
                    }
                }
                catch
                {
                    status = "AI: GPT4All HTTP unreachable (timeout/error).";
                }
            }
            else
            {
                status = "AI: No GPT4All configuration found. Set NEO_GPT4ALL_CLI or NEO_GPT4ALL_ENDPOINT.";
            }

            // Update UI friendly message
            Dispatcher.Invoke(() =>
            {
                if (DataContext is MainWindowViewModel vm)
                {
                    vm.UpdateStatus = status;
                }
            });
        }
        catch (Exception ex)
        {
            Dispatcher.Invoke(() =>
            {
                if (DataContext is MainWindowViewModel vm)
                {
                    vm.UpdateStatus = "AI health-check failed: " + ex.Message;
                }
            });
        }
    }

    private MainWindowViewModel ViewModel => (MainWindowViewModel)DataContext;

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        EnsureNotifyIcon();
        EnsureAutoCleanTimer();
    }

    private void EnsureNotifyIcon()
    {
        if (_notifyIcon is not null)
        {
            return;
        }

        var menu = new WinForms.ContextMenuStrip();

        var openItem = new WinForms.ToolStripMenuItem("Open NeoOptimize");
        openItem.Click += (_, _) => Dispatcher.Invoke(RestoreFromTray);
        menu.Items.Add(openItem);

        menu.Items.Add(new WinForms.ToolStripSeparator());

        var cleanNowItem = new WinForms.ToolStripMenuItem("Clean Now");
        cleanNowItem.Click += (_, _) => Dispatcher.Invoke(() => ExecuteCommand(ViewModel.SmartCleanCommand));
        menu.Items.Add(cleanNowItem);

        var optimizeNowItem = new WinForms.ToolStripMenuItem("Optimize Now");
        optimizeNowItem.Click += (_, _) => Dispatcher.Invoke(() => ExecuteCommand(ViewModel.SmartOptimizeCommand));
        menu.Items.Add(optimizeNowItem);

        var smartFixItem = new WinForms.ToolStripMenuItem("Smart Fix");
        smartFixItem.Click += (_, _) => Dispatcher.Invoke(() => ExecuteCommand(ViewModel.SmartFixCommand));
        menu.Items.Add(smartFixItem);

        menu.Items.Add(new WinForms.ToolStripSeparator());

        _autoCleanMenuItem = new WinForms.ToolStripMenuItem($"Auto Clean ({ViewModel.MiniTrayAutoCleanIntervalMinutes} min)")
        {
            CheckOnClick = true,
            Checked = ViewModel.MiniTrayAutoCleanEnabled
        };
        _autoCleanMenuItem.Click += (_, _) => Dispatcher.Invoke(() =>
        {
            if (_autoCleanMenuItem is null) return;
            ViewModel.MiniTrayAutoCleanEnabled = _autoCleanMenuItem.Checked;
        });
        menu.Items.Add(_autoCleanMenuItem);

        _preShutdownMenuItem = new WinForms.ToolStripMenuItem("Pre-Shutdown Cleaner")
        {
            CheckOnClick = true,
            Checked = ViewModel.MiniTrayPreShutdownCleanerEnabled
        };
        _preShutdownMenuItem.Click += (_, _) => Dispatcher.Invoke(() =>
        {
            if (_preShutdownMenuItem is null) return;
            ViewModel.MiniTrayPreShutdownCleanerEnabled = _preShutdownMenuItem.Checked;
        });
        menu.Items.Add(_preShutdownMenuItem);

        menu.Items.Add(new WinForms.ToolStripSeparator());

        var exitItem = new WinForms.ToolStripMenuItem("Exit");
        exitItem.Click += (_, _) => Dispatcher.Invoke(ExitFromTray);
        menu.Items.Add(exitItem);

        menu.Opening += (_, _) => SyncTrayMenuState();
        ViewModel.PropertyChanged += OnViewModelPropertyChanged;

        _trayIcon = ResolveTrayIcon();
        _notifyIcon = new WinForms.NotifyIcon
        {
            Icon = _trayIcon,
            Text = "NeoOptimize v1.0.0",
            Visible = true,
            ContextMenuStrip = menu
        };
        _notifyIcon.DoubleClick += (_, _) => Dispatcher.Invoke(RestoreFromTray);
    }

    private void EnsureAutoCleanTimer()
    {
        if (_autoCleanTimer is not null)
        {
            return;
        }

        _autoCleanTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMinutes(ViewModel.MiniTrayAutoCleanIntervalMinutes)
        };
        _autoCleanTimer.Tick += (_, _) =>
        {
            if (ViewModel.MiniTrayAutoCleanEnabled)
            {
                ExecuteCommand(ViewModel.SmartCleanCommand);
            }
        };
        _autoCleanTimer.Start();
    }

    private static System.Drawing.Icon ResolveTrayIcon()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrWhiteSpace(processPath))
        {
            var associatedIcon = System.Drawing.Icon.ExtractAssociatedIcon(processPath);
            if (associatedIcon is not null)
            {
                return associatedIcon;
            }
        }

        return System.Drawing.SystemIcons.Application;
    }

    private void SyncTrayMenuState()
    {
        if (_autoCleanMenuItem is not null)
        {
            _autoCleanMenuItem.Checked = ViewModel.MiniTrayAutoCleanEnabled;
        }

        if (_preShutdownMenuItem is not null)
        {
            _preShutdownMenuItem.Checked = ViewModel.MiniTrayPreShutdownCleanerEnabled;
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(MainWindowViewModel.MiniTrayAutoCleanEnabled)
            or nameof(MainWindowViewModel.MiniTrayPreShutdownCleanerEnabled))
        {
            SyncTrayMenuState();
        }
    }

    private void OnStateChanged(object? sender, EventArgs e)
    {
        if (WindowState != WindowState.Minimized)
        {
            return;
        }

        Hide();
        ShowTrayInfo("NeoOptimize berjalan di MiniTray.", "Klik icon tray untuk open atau jalankan aksi cepat.");
    }

    private void OnClosing(object? sender, CancelEventArgs e)
    {
        if (_exitRequested || _isSessionEnding)
        {
            return;
        }

        e.Cancel = true;
        Hide();
        ShowTrayInfo("NeoOptimize tetap aktif.", "Pilih Exit dari tray menu untuk menutup aplikasi.");
    }

    private void OnSessionEnding(object? sender, SessionEndingCancelEventArgs e)
    {
        _isSessionEnding = true;
        if (ViewModel.MiniTrayPreShutdownCleanerEnabled)
        {
            ExecuteCommand(ViewModel.SmartCleanCommand);
        }
    }

    private void RestoreFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    private void ExitFromTray()
    {
        _exitRequested = true;
        Close();
    }

    private static void ExecuteCommand(ICommand command)
    {
        if (command.CanExecute(null))
        {
            command.Execute(null);
        }
    }

    private void ShowTrayInfo(string title, string message)
    {
        if (_notifyIcon is null)
        {
            return;
        }

        _notifyIcon.BalloonTipTitle = title;
        _notifyIcon.BalloonTipText = message;
        _notifyIcon.BalloonTipIcon = WinForms.ToolTipIcon.Info;
        _notifyIcon.ShowBalloonTip(2000);
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        Application.Current.SessionEnding -= OnSessionEnding;
        ViewModel.PropertyChanged -= OnViewModelPropertyChanged;

        if (_autoCleanTimer is not null)
        {
            _autoCleanTimer.Stop();
            _autoCleanTimer = null;
        }

        if (_notifyIcon is not null)
        {
            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _notifyIcon = null;
        }

        _trayIcon?.Dispose();
        _trayIcon = null;
    }
}
