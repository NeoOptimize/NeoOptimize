using System.Diagnostics;
using Microsoft.Extensions.Logging;
using NeoOptimize.Contracts;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.Service;

public sealed class CommandExecutor(SystemSnapshotProvider snapshotProvider, ILogger<CommandExecutor> logger)
{
    private readonly SystemSnapshotProvider _snapshotProvider = snapshotProvider;
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
            var output = command.CommandName switch
            {
                "flush_dns" => await FlushDnsAsync(cancellationToken),
                "clear_temp_files" => ClearTempFiles(),
                "smart_booster" => await SmartBoosterAsync(cancellationToken),
                "health_check" => HealthCheck(),
                _ => new Dictionary<string, object?>
                {
                    ["message"] = $"Command '{command.CommandName}' is not implemented yet.",
                },
            };

            return new CommandResultRequest
            {
                CommandId = command.CommandId,
                Status = command.CommandName is "flush_dns" or "clear_temp_files" or "smart_booster" or "health_check"
                    ? "completed"
                    : "failed",
                Output = output,
                ErrorMessage = command.CommandName is "flush_dns" or "clear_temp_files" or "smart_booster" or "health_check"
                    ? null
                    : $"Unsupported command: {command.CommandName}",
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

    private static async Task<Dictionary<string, object?>> FlushDnsAsync(CancellationToken cancellationToken)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "ipconfig",
                Arguments = "/flushdns",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true,
            },
        };

        process.Start();
        var stdout = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);

        return new Dictionary<string, object?>
        {
            ["exit_code"] = process.ExitCode,
            ["stdout"] = stdout,
            ["stderr"] = stderr,
        };
    }

    private static Dictionary<string, object?> ClearTempFiles()
    {
        var tempPath = Path.GetTempPath();
        var deleted = 0;

        foreach (var file in Directory.EnumerateFiles(tempPath))
        {
            try
            {
                File.Delete(file);
                deleted++;
            }
            catch
            {
                // Best-effort cleanup only.
            }
        }

        return new Dictionary<string, object?>
        {
            ["temp_path"] = tempPath,
            ["deleted_files"] = deleted,
        };
    }

    private static async Task<Dictionary<string, object?>> SmartBoosterAsync(CancellationToken cancellationToken)
    {
        var dns = await FlushDnsAsync(cancellationToken);
        var temp = ClearTempFiles();

        return new Dictionary<string, object?>
        {
            ["dns_flush"] = dns,
            ["temp_cleanup"] = temp,
        };
    }

    private Dictionary<string, object?> HealthCheck()
    {
        var health = _snapshotProvider.CollectHealth("scheduled_local_scan");
        return new Dictionary<string, object?>
        {
            ["overall_score"] = health.OverallScore,
            ["health_state"] = health.HealthState,
            ["report"] = health.Report,
        };
    }
}
