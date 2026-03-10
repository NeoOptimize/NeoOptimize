using System.IO;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using NeoOptimize.App.Models;
using NeoOptimize.Contracts;
using NeoOptimize.Infrastructure;

namespace NeoOptimize.App.Services;

public sealed record ActionExecutionResult(
    string ActionKey,
    string Title,
    string Summary,
    string? ReportFileName,
    Dictionary<string, object?> Output);

public sealed class DesktopActionRunner(
    SystemSnapshotProvider snapshotProvider,
    WindowsMaintenanceToolkit maintenanceToolkit,
    ReportStore reportStore,
    ILogger<DesktopActionRunner> logger)
{
    private readonly SystemSnapshotProvider _snapshotProvider = snapshotProvider;
    private readonly WindowsMaintenanceToolkit _maintenanceToolkit = maintenanceToolkit;
    private readonly ReportStore _reportStore = reportStore;
    private readonly ILogger<DesktopActionRunner> _logger = logger;

    public async Task<ActionExecutionResult> RunActionAsync(string action, CancellationToken cancellationToken)
    {
        var normalized = Normalize(action);
        return normalized switch
        {
            "smartboost" or "smartbooster" or "smart_booster" => await WrapWithReportAsync(
                await _maintenanceToolkit.RunSmartBoosterAsync(cancellationToken),
                "smart-boost",
                cancellationToken),
            "smartoptimize" or "smart_optimize" => await RunSmartOptimizeAsync(cancellationToken),
            "healthcheck" or "health_check" => await WrapWithReportAsync(
                await _maintenanceToolkit.RunHealthCheckAsync("local_manual_scan", cancellationToken),
                "health-check",
                cancellationToken),
            "integrityscan" or "integrity_scan" => await WrapWithReportAsync(
                await _maintenanceToolkit.RunIntegrityScanAsync(AppContext.BaseDirectory, cancellationToken),
                "integrity-scan",
                cancellationToken),
            "flushdns" or "flush_dns" => ToExecutionResult(await _maintenanceToolkit.RunFlushDnsAsync(cancellationToken), null),
            "cleartempfiles" or "clear_temp_files" => ToExecutionResult(_maintenanceToolkit.RunClearTempFiles(), null),
            _ => new ActionExecutionResult(
                action,
                "Unsupported action",
                $"Action '{action}' belum didukung.",
                null,
                new Dictionary<string, object?> { ["action"] = action })
        };
    }

    public async Task<CommandResultRequest> ExecuteCommandAsync(RemoteCommandPollResponse command, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(command.CommandId) || string.IsNullOrWhiteSpace(command.CommandName))
        {
            return new CommandResultRequest
            {
                CommandId = command.CommandId ?? Guid.NewGuid().ToString(),
                Status = "failed",
                ErrorMessage = "Command payload is incomplete.",
            };
        }

        try
        {
            var result = await RunActionAsync(command.CommandName, cancellationToken);
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
            _logger.LogError(exception, "Failed to execute remote command {CommandName}", command.CommandName);
            return new CommandResultRequest
            {
                CommandId = command.CommandId,
                Status = "failed",
                ErrorMessage = exception.Message,
            };
        }
    }

    private async Task<ActionExecutionResult> RunSmartOptimizeAsync(CancellationToken cancellationToken)
    {
        var telemetryBefore = _snapshotProvider.CollectTelemetry();
        var maintenanceResult = await _maintenanceToolkit.RunSmartBoosterAsync(cancellationToken);
        var output = new Dictionary<string, object?>(maintenanceResult.Output)
        {
            ["telemetry_snapshot"] = telemetryBefore.Snapshot,
            ["cpu_percent"] = telemetryBefore.CpuPercent,
            ["ram_percent"] = telemetryBefore.RamPercent,
            ["disk_usage_percent"] = telemetryBefore.DiskUsagePercent,
            ["gpu_percent"] = telemetryBefore.GpuPercent,
        };

        var wrapped = maintenanceResult with
        {
            ActionKey = "smart_optimize",
            Title = "Smart Optimize",
            Summary = $"Smart Optimize selesai. CPU {FormatMetric(telemetryBefore.CpuPercent)}%, RAM {FormatMetric(telemetryBefore.RamPercent)}%, Disk {FormatMetric(telemetryBefore.DiskUsagePercent)}% sebelum optimasi."
        };

        return await WrapWithReportAsync(wrapped with { Output = output }, "smart-optimize", cancellationToken);
    }

    private async Task<ActionExecutionResult> WrapWithReportAsync(MaintenanceActionResult result, string reportSlug, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        var reportPath = _reportStore.CreateReport(
            reportSlug,
            result.Title,
            result.Summary,
            BuildReportLines(result));
        return ToExecutionResult(result, Path.GetFileName(reportPath));
    }

    private static ActionExecutionResult ToExecutionResult(MaintenanceActionResult result, string? reportFileName)
    {
        return new ActionExecutionResult(
            result.ActionKey,
            result.Title,
            result.Summary,
            reportFileName,
            result.Output);
    }

    private static IEnumerable<string> BuildReportLines(MaintenanceActionResult result)
    {
        yield return $"Action: {result.ActionKey}";
        yield return $"Summary: {result.Summary}";
        yield return string.Empty;
        yield return "Output:";
        yield return JsonSerializer.Serialize(result.Output, new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            WriteIndented = true,
        });

        if (result.HealthPayload is not null)
        {
            yield return string.Empty;
            yield return "Health Payload:";
            yield return JsonSerializer.Serialize(result.HealthPayload, new JsonSerializerOptions(JsonSerializerDefaults.Web)
            {
                WriteIndented = true,
            });
        }
    }

    private static string FormatMetric(double? value)
    {
        return value is null ? "n/a" : value.Value.ToString("0.0");
    }

    private static string Normalize(string value)
    {
        return new string(value.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
    }
}

