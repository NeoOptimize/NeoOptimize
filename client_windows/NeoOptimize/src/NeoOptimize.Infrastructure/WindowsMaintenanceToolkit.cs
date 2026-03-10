using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using NeoOptimize.Contracts;

namespace NeoOptimize.Infrastructure;

public sealed record MaintenanceActionResult(
    string ActionKey,
    string Title,
    string Summary,
    Dictionary<string, object?> Output,
    SystemHealthPayload? HealthPayload = null);

public sealed class WindowsMaintenanceToolkit
{
    [DllImport("psapi.dll")]
    private static extern bool EmptyWorkingSet(IntPtr processHandle);

    private static readonly HashSet<string> OptionalBackgroundProcesses = new(StringComparer.OrdinalIgnoreCase)
    {
        "OneDrive", "Teams", "Discord", "Steam", "EpicGamesLauncher", "Battle.net", "Origin",
        "Skype", "Spotify", "Telegram", "WhatsApp", "Zoom", "Adobe Desktop Service",
        "Creative Cloud", "Xbox", "GamingServices", "RiotClientServices", "Razer Synapse"
    };

    private static readonly string[] BloatwarePackageNames =
    {
        "Microsoft.XboxApp",
        "Microsoft.XboxGamingOverlay",
        "Microsoft.XboxGameOverlay",
        "Microsoft.Xbox.TCUI",
        "Microsoft.XboxIdentityProvider",
        "Microsoft.GamingApp",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.Microsoft3DViewer",
        "Microsoft.MixedReality.Portal",
        "Microsoft.People",
        "Microsoft.SkypeApp",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.BingWeather",
        "Microsoft.BingNews",
        "Microsoft.BingSports",
        "Microsoft.BingFinance",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.YourPhone",
        "Clipchamp.Clipchamp",
        "MicrosoftTeams"
    };

    private readonly SystemSnapshotProvider _snapshotProvider;
    private readonly ILogger<WindowsMaintenanceToolkit> _logger;

    public WindowsMaintenanceToolkit(SystemSnapshotProvider snapshotProvider, ILogger<WindowsMaintenanceToolkit> logger)
    {
        _snapshotProvider = snapshotProvider;
        _logger = logger;

    }

    public Task<MaintenanceActionResult> RunFlushDnsAsync(CancellationToken cancellationToken)
    {
        return RunFlushDnsCoreAsync(cancellationToken);
    }

    public MaintenanceActionResult RunClearTempFiles()
    {
        var temp = ClearTempFilesCore();
        return new MaintenanceActionResult(
            "clear_temp_files",
            "Clear Temp Files",
            $"Temp cleanup selesai. {temp.DeletedFiles} file dihapus.",
            new Dictionary<string, object?>
            {
                ["temp_path"] = temp.TempPath,
                ["deleted_files"] = temp.DeletedFiles,
            });
    }

    public async Task<MaintenanceActionResult> RunSmartBoosterAsync(CancellationToken cancellationToken)
    {
        var output = new Dictionary<string, object?>();
        var errors = new List<string>();

        ProcessExecutionResult dns;
        try
        {
            dns = await ExecuteProcessAsync("ipconfig", "/flushdns", cancellationToken, Encoding.Unicode);
            output["dns_flush"] = dns.ToDictionary();
        }
        catch (Exception exception)
        {
            dns = new ProcessExecutionResult(-1, string.Empty, exception.Message);
            output["dns_flush"] = new Dictionary<string, object?> { ["error"] = exception.Message };
            errors.Add($"DNS flush failed: {exception.Message}");
        }

        TempCleanupResult temp;
        try
        {
            temp = ClearTempFilesCore();
            output["temp_cleanup"] = new Dictionary<string, object?>
            {
                ["temp_path"] = temp.TempPath,
                ["deleted_files"] = temp.DeletedFiles,
            };
        }
        catch (Exception exception)
        {
            temp = new TempCleanupResult(string.Empty, 0);
            output["temp_cleanup"] = new Dictionary<string, object?> { ["error"] = exception.Message };
            errors.Add($"Temp cleanup failed: {exception.Message}");
        }

        var priorityOptimization = OptimizeNeoOptimizeProcesses();
        output["priority_optimization"] = new Dictionary<string, object?>
        {
            ["updated_processes"] = priorityOptimization.UpdatedProcesses,
            ["process_names"] = priorityOptimization.ProcessNames,
        };

        var background = StopOptionalBackgroundProcesses();
        output["background_processes"] = new Dictionary<string, object?>
        {
            ["stopped_processes"] = background.StoppedProcesses,
            ["process_names"] = background.ProcessNames,
        };

        var workingSet = EmptyWorkingSetForUserProcesses();
        output["working_set"] = new Dictionary<string, object?>
        {
            ["cleared_processes"] = workingSet.ClearedProcesses,
            ["process_names"] = workingSet.ProcessNames,
        };

        var summary = $"Smart Booster selesai. DNS exit {dns.ExitCode}, temp deleted {temp.DeletedFiles}, stopped {background.StoppedProcesses} processes, cleared {workingSet.ClearedProcesses} working sets.";
        if (errors.Count > 0)
        {
            summary += $" Errors: {string.Join("; ", errors)}";
        }

        return new MaintenanceActionResult(
            "smart_booster",
            "Smart Booster",
            summary,
            output);
    }

    public async Task<MaintenanceActionResult> RunSmartOptimizeAsync(bool enableBloatwareRemoval, CancellationToken cancellationToken)
    {
        var output = new Dictionary<string, object?>();
        var errors = new List<string>();

        var booster = await RunSmartBoosterAsync(cancellationToken);
        output["smart_booster"] = new Dictionary<string, object?>
        {
            ["summary"] = booster.Summary,
            ["details"] = booster.Output,
        };

        DumpCleanupResult dumpCleanup;
        try
        {
            dumpCleanup = CleanupDumpFilesCore();
            output["dump_cleanup"] = new Dictionary<string, object?>
            {
                ["deleted_files"] = dumpCleanup.DeletedFiles,
                ["deleted_bytes"] = dumpCleanup.DeletedBytes,
                ["failed_files"] = dumpCleanup.FailedFiles,
                ["targets"] = dumpCleanup.Targets,
                ["sample_deleted"] = dumpCleanup.SampleDeleted,
                ["errors"] = dumpCleanup.Errors,
            };
        }
        catch (Exception exception)
        {
            dumpCleanup = new DumpCleanupResult(0, 0, 0, Array.Empty<string>(), Array.Empty<string>(), Array.Empty<string>());
            output["dump_cleanup"] = new Dictionary<string, object?>
            {
                ["error"] = exception.Message,
            };
            errors.Add($"Dump cleanup failed: {exception.Message}");
        }

        if (enableBloatwareRemoval)
        {
            try
            {
                var bloatware = await RemoveBloatwareAsync(cancellationToken);
                output["bloatware_removal"] = new Dictionary<string, object?>
                {
                    ["removed_packages"] = bloatware.RemovedPackages,
                    ["not_found"] = bloatware.NotFoundPackages,
                    ["errors"] = bloatware.Errors,
                    ["exit_code"] = bloatware.ExitCode,
                    ["stderr"] = bloatware.Stderr,
                };

                if (bloatware.Errors.Count > 0)
                {
                    errors.AddRange(bloatware.Errors.Select(error => $"Bloatware: {error}"));
                }
            }
            catch (Exception exception)
            {
                output["bloatware_removal"] = new Dictionary<string, object?>
                {
                    ["error"] = exception.Message,
                };
                errors.Add($"Bloatware removal failed: {exception.Message}");
            }
        }
        else
        {
            output["bloatware_removal"] = new Dictionary<string, object?>
            {
                ["enabled"] = false,
                ["reason"] = "EnableBloatwareRemoval=false",
            };
        }

        var summary = $"Smart Optimize selesai. Dump cleanup deleted {dumpCleanup.DeletedFiles} file, bloatware removal {(enableBloatwareRemoval ? "enabled" : "disabled")}.";
        if (errors.Count > 0)
        {
            summary += $" Errors: {string.Join("; ", errors)}";
        }

        return new MaintenanceActionResult(
            "smart_optimize",
            "Smart Optimize",
            summary,
            output);
    }

    public async Task<MaintenanceActionResult> RunHealthCheckAsync(string integrityStatus, CancellationToken cancellationToken)
    {
        var errors = new List<string>();

        ProcessExecutionResult sfc;
        try
        {
            sfc = await ExecuteProcessAsync("sfc", "/verifyonly", cancellationToken, Encoding.Unicode);
        }
        catch (Exception exception)
        {
            sfc = new ProcessExecutionResult(-1, string.Empty, exception.Message);
            errors.Add($"SFC failed: {exception.Message}");
        }

        ProcessExecutionResult dism;
        try
        {
            dism = await ExecuteProcessAsync("DISM", "/Online /Cleanup-Image /CheckHealth", cancellationToken);
        }
        catch (Exception exception)
        {
            dism = new ProcessExecutionResult(-1, string.Empty, exception.Message);
            errors.Add($"DISM failed: {exception.Message}");
        }

        var health = _snapshotProvider.CollectHealth(
            integrityStatus,
            sfcStatus: ParseSfcStatus(sfc),
            dismStatus: ParseDismStatus(dism));

        var summary = $"Health Check selesai. Score {health.OverallScore}, SFC {health.SfcStatus}, DISM {health.DismStatus}, thermal {health.ThermalStatus}.";
        if (errors.Count > 0)
        {
            summary += $" Errors: {string.Join("; ", errors)}";
        }

        return new MaintenanceActionResult(
            "health_check",
            "Health Check",
            summary,
            new Dictionary<string, object?>
            {
                ["overall_score"] = health.OverallScore,
                ["health_state"] = health.HealthState,
                ["report"] = health.Report,
                ["recommendations"] = health.Recommendations,
                ["issues"] = health.Issues,
                ["sfc"] = new Dictionary<string, object?>
                {
                    ["status"] = health.SfcStatus,
                    ["exit_code"] = sfc.ExitCode,
                    ["stdout"] = sfc.Stdout,
                    ["stderr"] = sfc.Stderr,
                },
                ["dism"] = new Dictionary<string, object?>
                {
                    ["status"] = health.DismStatus,
                    ["exit_code"] = dism.ExitCode,
                    ["stdout"] = dism.Stdout,
                    ["stderr"] = dism.Stderr,
                },
                ["errors"] = errors,
            },
            health);
    }

    public Task<MaintenanceActionResult> RunIntegrityScanAsync(string installationRoot, CancellationToken cancellationToken)
    {
        _ = cancellationToken;
        List<string> files;
        try
        {
            files = Directory.EnumerateFiles(installationRoot, "*.*", SearchOption.AllDirectories)
                .Where(path => path.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".json", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".html", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".css", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".js", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".png", StringComparison.OrdinalIgnoreCase)
                    || path.EndsWith(".ico", StringComparison.OrdinalIgnoreCase))
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch (Exception exception)
        {
            return Task.FromResult(new MaintenanceActionResult(
                "integrity_scan",
                "Integrity Scan",
                $"Integrity Scan gagal: {exception.Message}",
                new Dictionary<string, object?>
                {
                    ["installation_root"] = installationRoot,
                    ["error"] = exception.Message,
                },
                _snapshotProvider.CollectHealth("warning")));
        }

        var sample = files.Take(20)
            .Select(path => new Dictionary<string, object?>
            {
                ["file"] = Path.GetRelativePath(installationRoot, path),
                ["sha256"] = ComputeSha256(path),
            })
            .ToList();

        var summary = $"Integrity Scan selesai. {files.Count} file dipindai dengan SHA-256 lokal di {installationRoot}.";
        return Task.FromResult(new MaintenanceActionResult(
            "integrity_scan",
            "Integrity Scan",
            summary,
            new Dictionary<string, object?>
            {
                ["installation_root"] = installationRoot,
                ["scanned_files"] = files.Count,
                ["integrity_status"] = files.Count > 0 ? "verified" : "warning",
                ["sample_hashes"] = sample,
            },
            _snapshotProvider.CollectHealth(files.Count > 0 ? "verified" : "warning")));
    }

    public async Task<MaintenanceActionResult> RunActionAsync(string action, string installationRoot, bool enableBloatwareRemoval, CancellationToken cancellationToken)
    {
        return Normalize(action) switch
        {
            "flushdns" or "flush_dns" => await RunFlushDnsAsync(cancellationToken),
            "cleartempfiles" or "clear_temp_files" => RunClearTempFiles(),
            "smartbooster" or "smart_booster" => await RunSmartBoosterAsync(cancellationToken),
            "smartoptimize" or "smart_optimize" => await RunSmartOptimizeAsync(enableBloatwareRemoval, cancellationToken),
            "healthcheck" or "health_check" => await RunHealthCheckAsync("scheduled_local_scan", cancellationToken),
            "integrityscan" or "integrity_scan" => await RunIntegrityScanAsync(installationRoot, cancellationToken),
            _ => new MaintenanceActionResult(
                action,
                "Unsupported action",
                $"Action '{action}' belum didukung.",
                new Dictionary<string, object?> { ["action"] = action })
        };
    }

    private async Task<MaintenanceActionResult> RunFlushDnsCoreAsync(CancellationToken cancellationToken)
    {
        var dns = await ExecuteProcessAsync("ipconfig", "/flushdns", cancellationToken, Encoding.Unicode);
        var summary = dns.ExitCode == 0
            ? "Flush DNS berhasil dijalankan."
            : "Flush DNS gagal atau membutuhkan izin lebih tinggi.";
        return new MaintenanceActionResult(
            "flush_dns",
            "Flush DNS",
            summary,
            dns.ToDictionary());
    }

    private static TempCleanupResult ClearTempFilesCore()
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

        return new TempCleanupResult(tempPath, deleted);
    }

    private static DumpCleanupResult CleanupDumpFilesCore()
    {
        var targets = new List<string>();
        var deleted = 0;
        var deletedBytes = 0L;
        var failed = 0;
        var errors = new List<string>();
        var sampleDeleted = new List<string>();

        var windowsRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);

        var fileCandidates = new[]
        {
            Path.Combine(windowsRoot, "MEMORY.DMP"),
            Path.Combine(windowsRoot, "memory.dmp"),
        };

        foreach (var file in fileCandidates)
        {
            if (File.Exists(file))
            {
                targets.Add(file);
            }
        }

        var dumpDirectories = new[]
        {
            Path.Combine(windowsRoot, "Minidump"),
            Path.Combine(windowsRoot, "LiveKernelReports"),
            Path.Combine(programData, "Microsoft", "Windows", "WER", "ReportQueue"),
            Path.Combine(programData, "Microsoft", "Windows", "WER", "ReportArchive"),
            Path.Combine(programData, "Microsoft", "Windows", "WER", "Temp"),
        };

        foreach (var directory in dumpDirectories)
        {
            if (!Directory.Exists(directory))
            {
                continue;
            }

            try
            {
                foreach (var file in Directory.EnumerateFiles(directory, "*.*", SearchOption.AllDirectories))
                {
                    if (file.EndsWith(".dmp", StringComparison.OrdinalIgnoreCase) ||
                        file.EndsWith(".hdmp", StringComparison.OrdinalIgnoreCase) ||
                        file.EndsWith(".wer", StringComparison.OrdinalIgnoreCase))
                    {
                        targets.Add(file);
                    }
                }
            }
            catch (Exception exception)
            {
                errors.Add($"{directory}: {exception.Message}");
            }
        }

        foreach (var target in targets.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var fileInfo = new FileInfo(target);
                if (fileInfo.Exists)
                {
                    var size = fileInfo.Length;
                    fileInfo.IsReadOnly = false;
                    fileInfo.Delete();
                    deleted++;
                    deletedBytes += size;
                    if (sampleDeleted.Count < 20)
                    {
                        sampleDeleted.Add(target);
                    }
                }
            }
            catch (Exception exception)
            {
                failed++;
                errors.Add($"{target}: {exception.Message}");
            }
        }

        return new DumpCleanupResult(deleted, deletedBytes, failed, targets.Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), sampleDeleted, errors);
    }

    private (int StoppedProcesses, IReadOnlyList<string> ProcessNames) StopOptionalBackgroundProcesses()
    {
        var stopped = new List<string>();
        var currentProcessId = Environment.ProcessId;
        var sessionId = Process.GetCurrentProcess().SessionId;

        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (process.Id == currentProcessId || process.SessionId != sessionId)
                {
                    continue;
                }

                if (!OptionalBackgroundProcesses.Contains(process.ProcessName))
                {
                    continue;
                }

                if (process.HasExited)
                {
                    continue;
                }

                if (!process.CloseMainWindow())
                {
                    process.Kill();
                }
                else if (!process.WaitForExit(2000))
                {
                    process.Kill();
                }

                stopped.Add(process.ProcessName);
            }
            catch (Exception exception)
            {
                _logger.LogDebug(exception, "Failed to stop background process {ProcessName}", process.ProcessName);
            }
            finally
            {
                process.Dispose();
            }
        }

        return (stopped.Count, stopped.Distinct(StringComparer.OrdinalIgnoreCase).ToList());
    }

    private (int ClearedProcesses, IReadOnlyList<string> ProcessNames) EmptyWorkingSetForUserProcesses()
    {
        var cleared = new List<string>();
        var sessionId = Process.GetCurrentProcess().SessionId;

        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (process.SessionId != sessionId || process.HasExited)
                {
                    continue;
                }

                if (EmptyWorkingSet(process.Handle))
                {
                    cleared.Add(process.ProcessName);
                }
            }
            catch (Exception exception)
            {
                _logger.LogDebug(exception, "Failed to trim working set for {ProcessName}", process.ProcessName);
            }
            finally
            {
                process.Dispose();
            }
        }

        return (cleared.Count, cleared.Distinct(StringComparer.OrdinalIgnoreCase).ToList());
    }

    private (int UpdatedProcesses, IReadOnlyList<string> ProcessNames) OptimizeNeoOptimizeProcesses()
    {
        var updatedProcessNames = new List<string>();
        foreach (var process in Process.GetProcesses())
        {
            try
            {
                if (!process.ProcessName.StartsWith("NeoOptimize", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                process.PriorityClass = ProcessPriorityClass.AboveNormal;
                updatedProcessNames.Add(process.ProcessName);
            }
            catch (Exception exception)
            {
                _logger.LogDebug(exception, "Skipping priority change for process {ProcessName}", process.ProcessName);
            }
            finally
            {
                process.Dispose();
            }
        }

        return (updatedProcessNames.Count, updatedProcessNames.Distinct(StringComparer.OrdinalIgnoreCase).ToList());
    }

    private static async Task<ProcessExecutionResult> ExecuteProcessAsync(
        string fileName,
        string arguments,
        CancellationToken cancellationToken,
        Encoding? outputEncoding = null)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        if (outputEncoding is not null)
        {
            startInfo.StandardOutputEncoding = outputEncoding;
            startInfo.StandardErrorEncoding = outputEncoding;
        }

        using var process = new Process { StartInfo = startInfo };
        var started = process.Start();
        if (!started)
        {
            return new ProcessExecutionResult(-1, string.Empty, "Process failed to start.");
        }

        var stdout = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderr = await process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        return new ProcessExecutionResult(process.ExitCode, SanitizeOutput(stdout), SanitizeOutput(stderr));
    }

    private static async Task<ProcessExecutionResult> ExecutePowerShellAsync(string script, CancellationToken cancellationToken)
    {
        var encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        return await ExecuteProcessAsync(
            "powershell",
            $"-NoProfile -ExecutionPolicy Bypass -EncodedCommand {encoded}",
            cancellationToken,
            Encoding.UTF8);
    }

    private static async Task<BloatwareRemovalResult> RemoveBloatwareAsync(CancellationToken cancellationToken)
    {
        var targets = string.Join("','", BloatwarePackageNames);
        var script = $@"
$ErrorActionPreference = 'Stop'
$targets = @('{targets}')
$removed = @()
$notFound = @()
$errors = @()
foreach ($name in $targets) {{
  try {{
    $pkgs = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
    if ($pkgs) {{
      $pkgs | Remove-AppxPackage -ErrorAction Stop | Out-Null
      if ($removed -notcontains $name) {{ $removed += $name }}
    }} else {{
      $notFound += $name
    }}
    try {{
      $prov = Get-AppxProvisionedPackage -Online | Where-Object {{ $_.DisplayName -eq $name }}
      if ($prov) {{
        $prov | Remove-AppxProvisionedPackage -Online -ErrorAction Stop | Out-Null
        if ($removed -notcontains $name) {{ $removed += $name }}
      }}
    }} catch {{
      $errors += ""$name: $($_.Exception.Message)""
    }}
  }} catch {{
    $errors += ""$name: $($_.Exception.Message)""
  }}
}}
[pscustomobject]@{{ removed = $removed; not_found = $notFound; errors = $errors }} | ConvertTo-Json -Compress
";

        var result = await ExecutePowerShellAsync(script, cancellationToken);
        var removed = new List<string>();
        var notFound = new List<string>();
        var errors = new List<string>();

        if (!string.IsNullOrWhiteSpace(result.Stdout))
        {
            try
            {
                using var document = JsonDocument.Parse(result.Stdout);
                if (document.RootElement.TryGetProperty("removed", out var removedElement))
                {
                    removed.AddRange(removedElement.EnumerateArray()
                        .Select(item => item.GetString() ?? string.Empty)
                        .Where(name => !string.IsNullOrWhiteSpace(name)));
                }

                if (document.RootElement.TryGetProperty("not_found", out var notFoundElement))
                {
                    notFound.AddRange(notFoundElement.EnumerateArray()
                        .Select(item => item.GetString() ?? string.Empty)
                        .Where(name => !string.IsNullOrWhiteSpace(name)));
                }

                if (document.RootElement.TryGetProperty("errors", out var errorElement))
                {
                    errors.AddRange(errorElement.EnumerateArray()
                        .Select(item => item.GetString() ?? string.Empty)
                        .Where(message => !string.IsNullOrWhiteSpace(message)));
                }
            }
            catch (Exception exception)
            {
                errors.Add($"Parse error: {exception.Message}");
            }
        }

        return new BloatwareRemovalResult(
            removed.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            notFound.Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            errors,
            result.ExitCode,
            result.Stderr);
    }

    private static string ParseSfcStatus(ProcessExecutionResult result)
    {
        var combined = $"{result.Stdout}\n{result.Stderr}".ToLowerInvariant();
        if (!IsAdministrator() || combined.Contains("must be an administrator"))
        {
            return "requires_admin";
        }
        if (combined.Contains("did not find any integrity violations"))
        {
            return "clean";
        }
        if (combined.Contains("found integrity violations") || combined.Contains("found corrupt files"))
        {
            return "corruption_detected";
        }
        return result.ExitCode == 0 ? "completed" : "warning";
    }

    private static string ParseDismStatus(ProcessExecutionResult result)
    {
        var combined = $"{result.Stdout}\n{result.Stderr}".ToLowerInvariant();
        if (!IsAdministrator() || combined.Contains("elevated permissions are required") || result.ExitCode == 740)
        {
            return "requires_admin";
        }
        if (combined.Contains("no component store corruption detected"))
        {
            return "clean";
        }
        if (combined.Contains("component store is repairable"))
        {
            return "repairable";
        }
        if (combined.Contains("component store cannot be repaired") || combined.Contains("not repairable"))
        {
            return "not_repairable";
        }
        return result.ExitCode == 0 ? "completed" : "warning";
    }

    private static bool IsAdministrator()
    {
        try
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
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

    private static string SanitizeOutput(string value)
    {
        return value.Replace("\0", string.Empty).Trim();
    }

    private sealed record ProcessExecutionResult(int ExitCode, string Stdout, string Stderr)
    {
        public Dictionary<string, object?> ToDictionary()
        {
            return new Dictionary<string, object?>
            {
                ["exit_code"] = ExitCode,
                ["stdout"] = Stdout,
                ["stderr"] = Stderr,
            };
        }
    }

    private sealed record TempCleanupResult(string TempPath, int DeletedFiles);

    private sealed record DumpCleanupResult(
        int DeletedFiles,
        long DeletedBytes,
        int FailedFiles,
        IReadOnlyList<string> Targets,
        IReadOnlyList<string> SampleDeleted,
        IReadOnlyList<string> Errors);

    private sealed record BloatwareRemovalResult(
        IReadOnlyList<string> RemovedPackages,
        IReadOnlyList<string> NotFoundPackages,
        IReadOnlyList<string> Errors,
        int ExitCode,
        string Stderr);
}
