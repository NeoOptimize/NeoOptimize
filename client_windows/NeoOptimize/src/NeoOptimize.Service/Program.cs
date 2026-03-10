using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using NeoOptimize.Infrastructure;
using NeoOptimize.Service;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "NeoOptimize Service";
});

builder.Services.AddOptions<NeoOptimizeClientOptions>()
    .Bind(builder.Configuration.GetSection(NeoOptimizeClientOptions.SectionName));

builder.Services.AddSingleton<HardwareFingerprintService>();
builder.Services.AddSingleton<RegistrationStore>();
builder.Services.AddSingleton<ConsentStore>();
builder.Services.AddSingleton<SystemSnapshotProvider>();
builder.Services.AddSingleton<WindowsMaintenanceToolkit>();
builder.Services.AddSingleton<CommandExecutor>();
builder.Services.AddHttpClient<NeoOptimizeApiClient>((serviceProvider, client) =>
{
    var options = serviceProvider.GetRequiredService<Microsoft.Extensions.Options.IOptions<NeoOptimizeClientOptions>>().Value;
    client.BaseAddress = new Uri(options.BackendBaseUrl);
    client.Timeout = TimeSpan.FromSeconds(60);
});
builder.Services.AddHostedService<Worker>();

var host = builder.Build();
host.Run();
