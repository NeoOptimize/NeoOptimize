using System.Windows;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using NeoOptimize.App.Services;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.App;

public partial class App : Application
{
    private IHost? _host;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        var builder = Host.CreateApplicationBuilder();
        builder.Configuration.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
        builder.Configuration.AddJsonFile($"appsettings.{builder.Environment.EnvironmentName}.json", optional: true, reloadOnChange: true);
        builder.Configuration.AddEnvironmentVariables();

        builder.Services.AddOptions<NeoOptimizeClientOptions>()
            .Bind(builder.Configuration.GetSection(NeoOptimizeClientOptions.SectionName));

        builder.Services.AddSingleton<HardwareFingerprintService>();
        builder.Services.AddSingleton<RegistrationStore>();
        builder.Services.AddSingleton<SystemSnapshotProvider>();
        builder.Services.AddSingleton<ReportStore>();
        builder.Services.AddSingleton<DesktopActionRunner>();
        builder.Services.AddHttpClient<NeoOptimizeApiClient>((serviceProvider, client) =>
        {
            var options = serviceProvider.GetRequiredService<Microsoft.Extensions.Options.IOptions<NeoOptimizeClientOptions>>().Value;
            client.BaseAddress = new Uri(options.BackendBaseUrl);
            client.Timeout = TimeSpan.FromSeconds(60);
        });
        builder.Services.AddSingleton<MainWindow>();

        _host = builder.Build();
        await _host.StartAsync();

        var mainWindow = _host.Services.GetRequiredService<MainWindow>();
        MainWindow = mainWindow;
        mainWindow.Show();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_host is not null)
        {
            await _host.StopAsync();
            _host.Dispose();
        }

        base.OnExit(e);
    }
}
