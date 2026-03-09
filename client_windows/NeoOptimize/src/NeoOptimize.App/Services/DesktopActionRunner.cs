using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
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
    ReportStore reportStore,
    ILogger<DesktopActionRunner> logger)
{
    private readonly SystemSnapshotProvider _snapshotProvider = snapshotProvider;
    private readonly ReportStore _reportStore = reportStore;
    private readonly ILogger<DesktopActionRunner> _logger = logger;

    public Task<ActionExecutionResult> RunActionAsync(string action, CancellationToken cancellationToken)
    {
        return Normalize(action) switch
        {
            "smartboost" or "smartbooster" or "smart_booster" => RunSmartBoostAsync(cancellationToken),
            "smartoptimize" or "smart_optimize" => RunSmartOptimizeAsync(cancellationToken),
            "healthcheck" or "health_check" => RunHealthCheckAsync(cancellationToken),
            "integrityscan" or "integrity_scan" => RunIntegrityScanAsync(cancellationToken),
            "flushdns" or "flush_dns" => RunFlushDnsOnlyAsync(cancellationToken),
            "cleartempfiles" or "clear_temp_files" => RunClearTempOnlyAsync(cancellationToken),
            _ => Task.FromResult(new ActionExecutionResult(
                action,
                "Unsupported action",
                $"Action '{action}' belum didukung.",
                null,
                new Dictionary<string, object?> { ["action"] = action }))
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

    private async Task<ActionExecutionResult> RunSmartBoostAsync(CancellationToken cancellationToken)
    {
        var dns = await FlushDnsAsync(cancellationToken);
        var temp = ClearTempFiles();
        var summary = $"Smart Boost selesai. Temp dibersihkan: {temp.DeletedFiles}. Exit code flush DNS: {dns.ExitCode}.";
        var reportPath = _reportStore.CreateReport(
            "smart-boost",
            "Smart Boost",
            summary,
            [
                $"Flush DNS exit code: {dns.ExitCode}",
                $"Flush DNS stdout: {dns.Stdout}",
                $"Deleted temp files: {temp.DeletedFiles}",
                $"Temp path: {temp.TempPath}",
            ]);

        return new ActionExecutionResult(
            "smartBoost",
            "Smart Boost",
            summary,
            Path.GetFileName(reportPath),
            new Dictionary<string, object?>
            {
                ["flush_dns"] = new Dictionary<string, object?>
                {
                    ["exit_code"] = dns.ExitCode,
                    ["stdout"] = dns.Stdout,
                    ["stderr"] = dns.Stderr,
                },
                ["temp_cleanup"] = new Dictionary<string, object?>
                {
                    ["deleted_files"] = temp.DeletedFiles,
                    ["temp_path"] = temp.TempPath,
                }
            });
    }

    private async Task<ActionExecutionResult> RunSmartOptimizeAsync(CancellationToken cancellationToken)
    {
        var telemetry = _snapshotProvider.CollectTelemetry();
        var boostResult = await RunSmartBoostAsync(cancellationToken);
        var summary = $"Smart Optimize selesai. CPU {telemetry.CpuPercent?.ToString("0.0") ?? "n/a"}% dan RAM {telemetry.RamPercent?.ToString("0.0") ?? "n/a"}% sebelum optimasi.";
        var reportPath = _reportStore.CreateReport(
            "smart-optimize",
            "Smart Optimize",
            summary,
            [
                $"CPU: {telemetry.CpuPercent?.ToString("0.0") ?? "n/a"}%",
                $"RAM: {telemetry.RamPercent?.ToString("0.0") ?? "n/a"}%",
                $"Disk: {telemetry.DiskUsagePercent?.ToString("0.0") ?? "n/a"}%",
                $"Top processes: {string.Join(", ", telemetry.TopProcesses.Select(p => p.TryGetValue("name", out var name) ? name : "unknown"))}",
                $"Smart boost report: {boostResult.ReportFileName}",
            ]);

        return new ActionExecutionResult(
            "smartOptimize",
            "Smart Optimize",
            summary,
            Path.GetFileName(reportPath),
            new Dictionary<string, object?>
            {
                ["telemetry_snapshot"] = telemetry.Snapshot,
                ["boost_report"] = boostResult.ReportFileName,
            });
    }

    private Task<ActionExecutionResult> RunHealthCheckAsync(CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        var health = _snapshotProvider.CollectHealth("local_manual_scan");
        var summary = $"Health Check selesai. Score {health.OverallScore} dengan status {health.HealthState}.";
        var reportPath = _reportStore.CreateReport(
            "health-check",
            "Health Check",
            summary,
            [
                $"SFC status: {health.SfcStatus}",
                $"DISM status: {health.DismStatus}",
                $"Thermal status: {health.ThermalStatus}",
                $"Integrity status: {health.IntegrityStatus}",
                $"Recommendations: {string.Join(", ", health.Recommendations)}",
            ]);

        return Task.FromResult(new ActionExecutionResult(
            "healthCheck",
            "Health Check",
            summary,
            Path.GetFileName(reportPath),
            new Dictionary<string, object?>
            {
                ["overall_score"] = health.OverallScore,
                ["health_state"] = health.HealthState,
                ["report"] = health.Report,
            }));
    }

    private Task<ActionExecutionResult> RunIntegrityScanAsync(CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        var files = Directory.EnumerateFiles(AppContext.BaseDirectory, "*.*", SearchOption.AllDirectories)
            .Where(path => path.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".html", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".css", StringComparison.OrdinalIgnoreCase)
                || path.EndsWith(".js", StringComparison.OrdinalIgnoreCase))
            .Take(300)
            .ToList();

        var sample = files.Take(12)
            .Select(path => $"{Path.GetFileName(path)} :: {ComputeSha256(path)}")
            .ToList();
        var summary = $"Integrity Scan selesai. {files.Count} file dipindai dengan SHA-256 lokal.";
        var reportPath = _reportStore.CreateReport(
            "integrity-scan",
            "Integrity Scan",
            summary,
            sample);

        return Task.FromResult(new ActionExecutionResult(
            "integrityScan",
            "Integrity Scan",
            summary,
            Path.GetFileName(reportPath),
            new Dictionary<string, object?>
            {
                ["scanned_files"] = files.Count,
                ["sample_hashes"] = sample,
            }));
    }

    private async Task<ActionExecutionResult> RunFlushDnsOnlyAsync(CancellationToken cancellationToken)
    {
        var dns = await FlushDnsAsync(cancellationToken);
        var summary = dns.ExitCode == 0
            ? "Flush DNS berhasil dijalankan."
            : "Flush DNS gagal atau membutuhkan izin lebih tinggi.";
        return new ActionExecutionResult(
            "flush_dns",
            "Flush DNS",
            summary,
            null,
            new Dictionary<string, object?>
            {
                ["exit_code"] = dns.ExitCode,
                ["stdout"] = dns.Stdout,
                ["stderr"] = dns.Stderr,
            });
    }

    private Task<ActionExecutionResult> RunClearTempOnlyAsync(CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        var temp = ClearTempFiles();
        var summary = $"Temp cleanup selesai. {temp.DeletedFiles} file dihapus.";
        return Task.FromResult(new ActionExecutionResult(
            "clear_temp_files",
            "Clear Temp Files",
            summary,
            null,
            new Dictionary<string, object?>
            {
                ["deleted_files"] = temp.DeletedFiles,
                ["temp_path"] = temp.TempPath,
            }));
    }

    private static async Task<(int ExitCode, string Stdout, string Stderr)> FlushDnsAsync(CancellationToken cancellationToken)
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
        return (process.ExitCode, stdout, stderr);
    }

    private static (string TempPath, int DeletedFiles) ClearTempFiles()
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
                // Best effort only.
            }
        }

        return (tempPath, deleted);
    }

    private static string ComputeSha256(string path)
    {
        using var sha = SHA256.Create();
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(sha.ComputeHash(stream)).ToLowerInvariant();
    }

    private static string Normalize(string value)
    {
        return new string(value.Where(char.IsLetterOrDigit).ToArray()).ToLowerInvariant();
    }
}
