using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.Service;

public sealed class Worker(
    ILogger<Worker> logger,
    NeoOptimizeApiClient apiClient,
    SystemSnapshotProvider snapshotProvider,
    CommandExecutor commandExecutor,
    WindowsMaintenanceToolkit maintenanceToolkit,
    ConsentStore consentStore,
    IOptions<NeoOptimizeClientOptions> options) : BackgroundService
{
    private readonly ILogger<Worker> _logger = logger;
    private readonly NeoOptimizeApiClient _apiClient = apiClient;
    private readonly SystemSnapshotProvider _snapshotProvider = snapshotProvider;
    private readonly CommandExecutor _commandExecutor = commandExecutor;
    private readonly WindowsMaintenanceToolkit _maintenanceToolkit = maintenanceToolkit;
    private readonly ConsentStore _consentStore = consentStore;
    private readonly NeoOptimizeClientOptions _options = options.Value;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var registration = await _apiClient.EnsureRegistrationAsync(stoppingToken);
        _logger.LogInformation("NeoOptimize client registered as {ClientId}", registration.ClientId);

        var tasks = new[]
        {
            RunTelemetryLoopAsync(stoppingToken),
            RunHealthLoopAsync(stoppingToken),
            RunCommandLoopAsync(stoppingToken),
            RunSmartBoosterLoopAsync(stoppingToken),
            RunSmartOptimizeLoopAsync(stoppingToken),
            RunIntegrityLoopAsync(stoppingToken),
        };

        await Task.WhenAll(tasks);
    }

    private async Task RunTelemetryLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(_options.TelemetryIntervalSeconds));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.Telemetry)
                {
                    _logger.LogInformation("Telemetry consent not granted. Skipping telemetry push.");
                    continue;
                }

                var telemetry = _snapshotProvider.CollectTelemetry();
                var response = await _apiClient.PushTelemetryAsync(telemetry, cancellationToken);
                _logger.LogInformation("Telemetry pushed. Status={Status} Alerts={Alerts}", response.Status, string.Join(", ", response.Alerts));
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Telemetry push failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }

    private async Task RunHealthLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(_options.HealthIntervalMinutes));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.Diagnostics)
                {
                    _logger.LogInformation("Diagnostics consent not granted. Skipping health report.");
                    continue;
                }

                var result = await _maintenanceToolkit.RunHealthCheckAsync("pending_integrity_scan", cancellationToken);
                if (result.HealthPayload is not null)
                {
                    await _apiClient.ReportHealthAsync(result.HealthPayload, cancellationToken);
                    _logger.LogInformation("Health report pushed. {Summary}", result.Summary);
                }
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Health report failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }

    private async Task RunCommandLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(_options.CommandPollIntervalSeconds));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.RemoteControl)
                {
                    _logger.LogInformation("Remote control consent not granted. Skipping command polling.");
                    continue;
                }

                var command = await _apiClient.PollCommandAsync(cancellationToken);
                if (!string.Equals(command.Status, "pending", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var result = await _commandExecutor.ExecuteAsync(command, cancellationToken);
                await _apiClient.SubmitCommandResultAsync(result, cancellationToken);
                _logger.LogInformation("Command {CommandName} finished with {Status}", command.CommandName, result.Status);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Command polling failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }

    private async Task RunSmartBoosterLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromMinutes(_options.SmartBoosterIntervalMinutes));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.Maintenance)
                {
                    _logger.LogInformation("Maintenance consent not granted. Skipping scheduled Smart Booster.");
                    continue;
                }

                var result = await _maintenanceToolkit.RunSmartBoosterAsync(cancellationToken);
                _logger.LogInformation("Scheduled Smart Booster completed. {Summary}", result.Summary);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Scheduled Smart Booster failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }

    private async Task RunSmartOptimizeLoopAsync(CancellationToken cancellationToken)
    {
        if (_options.SmartOptimizeIntervalHours <= 0)
        {
            _logger.LogInformation("Smart Optimize interval disabled.");
            return;
        }

        using var timer = new PeriodicTimer(TimeSpan.FromHours(_options.SmartOptimizeIntervalHours));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.Maintenance)
                {
                    _logger.LogInformation("Maintenance consent not granted. Skipping scheduled Smart Optimize.");
                    continue;
                }

                var result = await _maintenanceToolkit.RunSmartOptimizeAsync(_options.EnableBloatwareRemoval, cancellationToken);
                _logger.LogInformation("Scheduled Smart Optimize completed. {Summary}", result.Summary);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Scheduled Smart Optimize failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }

    private async Task RunIntegrityLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromHours(_options.IntegrityIntervalHours));

        do
        {
            try
            {
                var consent = await _consentStore.LoadAsync(cancellationToken);
                if (!consent.Accepted || !consent.Diagnostics)
                {
                    _logger.LogInformation("Diagnostics consent not granted. Skipping integrity scan.");
                    continue;
                }

                var result = await _maintenanceToolkit.RunIntegrityScanAsync(AppContext.BaseDirectory, cancellationToken);
                if (result.HealthPayload is not null)
                {
                    await _apiClient.ReportHealthAsync(result.HealthPayload, cancellationToken);
                }

                _logger.LogInformation("Scheduled Integrity Scan completed. {Summary}", result.Summary);
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Scheduled Integrity Scan failed");
            }
        }
        while (await timer.WaitForNextTickAsync(cancellationToken));
    }
}
