using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using NeoOptimize.Contracts;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.Service;

public sealed class CommandExecutor(
    WindowsMaintenanceToolkit maintenanceToolkit,
    ConsentStore consentStore,
    IOptions<NeoOptimizeClientOptions> options,
    ILogger<CommandExecutor> logger)
{
    private readonly WindowsMaintenanceToolkit _maintenanceToolkit = maintenanceToolkit;
    private readonly ConsentStore _consentStore = consentStore;
    private readonly NeoOptimizeClientOptions _options = options.Value;
    private readonly ILogger<CommandExecutor> _logger = logger;

    public async Task<CommandResultRequest> ExecuteAsync(RemoteCommandPollResponse command, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(command.CommandId) || string.IsNullOrWhiteSpace(command.CommandName))
        {
            return new CommandResultRequest
            {
                CommandId = command.CommandId ?? Guid.Empty.ToString(),
                Status = "failed",
                ErrorMessage = "Command payload is incomplete.",
            };
        }

        try
        {
            var consent = await _consentStore.LoadAsync(cancellationToken);
            if (!consent.Accepted || !consent.RemoteControl)
            {
                return new CommandResultRequest
                {
                    CommandId = command.CommandId,
                    Status = "failed",
                    ErrorMessage = "Remote control consent belum diaktifkan.",
                };
            }

            var result = await _maintenanceToolkit.RunActionAsync(
                command.CommandName,
                AppContext.BaseDirectory,
                _options.EnableBloatwareRemoval,
                cancellationToken);
            return new CommandResultRequest
            {
                CommandId = command.CommandId,
                Status = result.Title == "Unsupported action" ? "failed" : "completed",
                Output = result.Output,
                ErrorMessage = result.Title == "Unsupported action" ? result.Summary : null,
            };
        }
        catch (Exception exception)
        {
            _logger.LogError(exception, "Failed to execute command {CommandName}", command.CommandName);
            return new CommandResultRequest
            {
                CommandId = command.CommandId,
                Status = "failed",
                ErrorMessage = exception.Message,
            };
        }
    }
}
