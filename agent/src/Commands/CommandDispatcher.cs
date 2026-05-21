using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;
using NeoOptimize.Agent.Safety;

namespace NeoOptimize.Agent.Commands;

public class CommandDispatcher
{
    private readonly ILogger<CommandDispatcher> _logger;
    private readonly IConfiguration _config;
    private readonly CommandSafetyRuntime _safetyRuntime;
    private readonly string _psModulesPath;
    private readonly string _libPath;

    public CommandDispatcher(ILogger<CommandDispatcher> logger, IConfiguration config, CommandSafetyRuntime safetyRuntime)
    {
        _logger = logger;
        _config = config;
        _safetyRuntime = safetyRuntime;
        // Fix for single-file publish path resolution
        var exePath = Process.GetCurrentProcess().MainModule?.FileName;
        var baseDir = Path.GetDirectoryName(exePath) ?? AppDomain.CurrentDomain.BaseDirectory;

        _psModulesPath = Path.Combine(baseDir, "modules");
        _libPath = Path.Combine(baseDir, "lib");
    }

    public async Task<Dictionary<string, object>> ExecuteAsync(string cmdType, Dictionary<string, object>? args, CancellationToken ct)
    {
        _logger.LogInformation("Executing command: {Type}", cmdType);

        return await _safetyRuntime.RunAsync(cmdType, args, ct, () => ExecuteCoreAsync(cmdType, args, ct));
    }

    public Task<Dictionary<string, object>?> RecoverPendingExecutionAsync(CancellationToken ct)
    {
        return _safetyRuntime.RecoverPendingExecutionAsync(ct);
    }

    private async Task<Dictionary<string, object>> ExecuteCoreAsync(string cmdType, Dictionary<string, object>? args, CancellationToken ct)
    {
        return cmdType switch
        {
            // ── Optimization & Maintenance ─────────────────────────────
            "OPTIMIZE"      => await RunPsModuleAsync("02_Performance.ps1", args, ct),
            "PERFORMANCE"   => await RunPsModuleAsync("02_Performance.ps1", args, ct),
            "CLEAN"         => await RunPsModuleAsync("01_Cleaner.ps1", args, ct),
            "DEEP_SCAN"     => await RunPsModuleWithJsonArgsAsync("15_DeepScan.ps1", args, ct),
            "UPDATES"       => await RunPsModuleAsync("07_Updates.ps1", args, ct),
            "PRIVACY"       => await RunPsModuleAsync("03_Privacy.ps1", args, ct),
            "POWER"         => await RunPsModuleAsync("08_Power.ps1", args, ct),
            "APP_MANAGER"   => await RunPsModuleAsync("09_Apps.ps1", args, ct),
            "SYSTEM_REPAIR" => await RunPsModuleWithJsonArgsAsync("10_SystemRepair.ps1", args, ct),
            "SYSTEM_DIAGNOSTICS" => await RunPsModuleWithJsonArgsAsync("16_SystemDiagnostics.ps1", args, ct),
            "BACKUP_OPS"    => await RunPsModuleAsync("11_Backup.ps1", args, ct),
            "NEOUPDATE"     => await RunPsModuleWithJsonArgsAsync("17_NeoOptimizeUpdate.ps1", args, ct),

            // ── Security & Network ─────────────────────────────────────
            "SECURITY_SCAN" => await RunPsModuleAsync("05_Security.ps1", args, ct),
            "NETWORK_TEST"  => await RunPsModuleAsync("04_Network.ps1", args, ct),
            "THREAT_SCAN"   => await RunPsModuleAsync("12_ThreatMonitor.ps1", args, ct),
            "AUTOIMMUNE"    => await RunPsModuleAsync("13_Autoimmune.ps1", args, ct),
            "INTEGRITY_SCAN"=> await RunPsModuleAsync("14_IntegrityScan.ps1", args, ct),

            // ── Hardware & Telemetry Collection ────────────────────────
            "COLLECT"       => await RunPsModuleAsync("06_Collect.ps1", args, ct),
            "SYSINFO"       => await RunPsInlineAsync(
                @"$o=@{hostname=$env:COMPUTERNAME;os=(Get-CimInstance Win32_OperatingSystem).Caption;" +
                @"cpu=(Get-CimInstance Win32_Processor)[0].Name;ram=[math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,1);" +
                @"disk=(Get-PSDrive C | Select-Object -ExpandProperty Free);uptime=(New-TimeSpan (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours};" +
                @"$o | ConvertTo-Json -Compress", ct),

            // ── Real-Time Location ─────────────────────────────────────
            "GEOLOCATE"     => SensitiveCommandRejected("GEOLOCATE", "location collection is telemetry opt-in only"),

            // ── Multimedia / Remote Observation ───────────────────────
            "SNAPSHOT"      => SensitiveCommandRejected("SNAPSHOT", "camera capture is not shipped in the distribution build"),
            "LISTEN"        => SensitiveCommandRejected("LISTEN", "microphone recording is not shipped in the distribution build"),
            "SERVICES"      => await RunPsModuleAsync("06_Services.ps1", args, ct),

            // ── Health Check ───────────────────────────────────────────
            "PING"          => new Dictionary<string, object> { { "pong", DateTime.UtcNow.ToString("O") }, { "ts", DateTime.UtcNow } },
            "SAFETY_ROLLBACK_TEST" => await RunSafetyRollbackTestAsync(args, ct),

            _               => throw new NotSupportedException($"Command '{cmdType}' not supported. Available: OPTIMIZE,PERFORMANCE,CLEAN,DEEP_SCAN,UPDATES,PRIVACY,POWER,SYSTEM_REPAIR,SYSTEM_DIAGNOSTICS,NEOUPDATE,SECURITY_SCAN,NETWORK_TEST,COLLECT,SYSINFO,SERVICES,PING,SAFETY_ROLLBACK_TEST")
        };
    }

    private static Dictionary<string, object> SensitiveCommandRejected(string command, string reason)
    {
        return new Dictionary<string, object>
        {
            ["executed"] = false,
            ["rejected"] = true,
            ["command"] = command,
            ["reason"] = reason
        };
    }

    private Task<Dictionary<string, object>> RunSafetyRollbackTestAsync(Dictionary<string, object>? args, CancellationToken ct)
    {
        if (!LabCommandsEnabled(args))
        {
            return Task.FromResult(SensitiveCommandRejected(
                "SAFETY_ROLLBACK_TEST",
                "lab command disabled; set Safety:EnableLabCommands=true and lab_self_healing_test=true"));
        }

        if (!OperatingSystem.IsWindows())
        {
            return Task.FromResult(new Dictionary<string, object>
            {
                ["executed"] = false,
                ["error"] = "SAFETY_ROLLBACK_TEST requires Windows"
            });
        }

        ct.ThrowIfCancellationRequested();

        var registryPath = GetArg(args, "registry_path", "HKLM\\SOFTWARE\\NeoOptimizeTest");
        if (!registryPath.Equals("HKLM\\SOFTWARE\\NeoOptimizeTest", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("SAFETY_ROLLBACK_TEST only allows HKLM\\SOFTWARE\\NeoOptimizeTest.");

        var valueName = GetArg(args, "value_name", "OptimizationLevel");
        var value = GetArg(args, "value", "Extreme");
        var cpuBurnSeconds = Math.Clamp(GetArgInt(args, "cpu_burn_seconds", 45), 5, 120);

        using var key = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\NeoOptimizeTest", RegistryKeyPermissionCheck.ReadWriteSubTree);
        if (key == null) throw new InvalidOperationException("Unable to create HKLM\\SOFTWARE\\NeoOptimizeTest.");

        key.SetValue(valueName, value, RegistryValueKind.String);
        var burnerPid = StartCpuBurner(cpuBurnSeconds);

        return Task.FromResult(new Dictionary<string, object>
        {
            ["executed"] = true,
            ["lab_self_healing_test"] = true,
            ["registry_path"] = registryPath,
            ["value_name"] = valueName,
            ["value"] = value,
            ["cpu_burn_seconds"] = cpuBurnSeconds,
            ["background_cpu_burner_pid"] = burnerPid
        });
    }

    private bool LabCommandsEnabled(Dictionary<string, object>? args)
    {
        var configEnabled = ReadBool(_config, "Safety:EnableLabCommands", false);
        var envEnabled = IsTruthy(Environment.GetEnvironmentVariable("NEO_ENABLE_AGENT_LAB_COMMANDS"));
        var argEnabled = GetArgBool(args, "lab_self_healing_test", false);
        return (configEnabled || envEnabled) && argEnabled;
    }

    private static int StartCpuBurner(int seconds)
    {
        var ps = $"$end=(Get-Date).AddSeconds({seconds}); while((Get-Date) -lt $end) {{ for($i=0; $i -lt 200000; $i++) {{ [void][Math]::Sqrt($i) }} }}";
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -Command \"{ps}\"",
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = Process.Start(psi);
        return process?.Id ?? 0;
    }

    private static string GetArg(Dictionary<string, object>? args, string key, string fallback)
    {
        if (args == null || !args.TryGetValue(key, out var value) || value == null) return fallback;
        if (value is JsonElement element)
        {
            return element.ValueKind == JsonValueKind.String ? element.GetString() ?? fallback : element.ToString();
        }
        return Convert.ToString(value) ?? fallback;
    }

    private static int GetArgInt(Dictionary<string, object>? args, string key, int fallback)
    {
        var text = GetArg(args, key, fallback.ToString());
        return int.TryParse(text, out var value) ? value : fallback;
    }

    private static bool GetArgBool(Dictionary<string, object>? args, string key, bool fallback)
    {
        var text = GetArg(args, key, fallback.ToString());
        return bool.TryParse(text, out var value) ? value : fallback;
    }

    private static bool ReadBool(IConfiguration configuration, string key, bool fallback)
    {
        var value = configuration[key] ?? configuration[$"Agent:{key}"];
        return bool.TryParse(value, out var parsed) ? parsed : fallback;
    }

    private static bool IsTruthy(string? value)
    {
        return value != null &&
               (value.Equals("1", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
                value.Equals("yes", StringComparison.OrdinalIgnoreCase));
    }

    private async Task<Dictionary<string, object>> RunPsInlineAsync(string psCode, CancellationToken ct)
    {
        return await ExecuteProcessAsync($"-NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -Command \"{psCode}\"", ct);
    }

    private async Task<Dictionary<string, object>> RunPsModuleAsync(string scriptName, Dictionary<string, object>? args, CancellationToken ct)
    {
        var scriptPath = Path.Combine(_psModulesPath, scriptName);
        if (!scriptName.EndsWith(".ps1") || !File.Exists(scriptPath))
        {
            return new Dictionary<string, object> { { "error", "Invalid or missing script: " + scriptPath } };
        }

        // The agent is always non-interactive. High-risk modules are blocked by
        // the PowerShell safety gate unless the signed command explicitly asks
        // for enforce mode.
        var enforce = AgentEnforceRequested(args) ? "$true" : "$false";
        string psCommand =
            $"$Global:NeoOptimizeNonInteractive=$true; " +
            $"$Global:NeoOptimizeAssumeYes=$false; " +
            $"$Global:NeoOptimizeEnforce={enforce}; " +
            $"function Wait-AnyKey {{}}; function Read-Host {{ return '' }}; & '{scriptPath}'";
        string arguments = $"-NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -Command \"{psCommand}\"";

        var result = await ExecuteProcessAsync(arguments, ct);
        result["script"] = scriptName;
        return result;
    }

    private async Task<Dictionary<string, object>> RunPsModuleWithJsonArgsAsync(string scriptName, Dictionary<string, object>? args, CancellationToken ct)
    {
        var scriptPath = Path.Combine(_psModulesPath, scriptName);
        if (!scriptName.EndsWith(".ps1") || !File.Exists(scriptPath))
        {
            return new Dictionary<string, object> { { "error", "Invalid or missing script: " + scriptPath } };
        }

        var argsJson = JsonSerializer.Serialize(args ?? new Dictionary<string, object>());
        var escapedJson = argsJson.Replace("'", "''");
        var enforce = AgentEnforceRequested(args) ? "$true" : "$false";
        string psCommand =
            $"$Global:NeoOptimizeNonInteractive=$true; " +
            $"$Global:NeoOptimizeAssumeYes=$false; " +
            $"$Global:NeoOptimizeEnforce={enforce}; " +
            $"function Wait-AnyKey {{}}; function Read-Host {{ return '' }}; & '{scriptPath}' -ArgsJson '{escapedJson}'";
        string arguments = $"-NoProfile -ExecutionPolicy RemoteSigned -NonInteractive -Command \"{psCommand}\"";

        var result = await ExecuteProcessAsync(arguments, ct);
        result["script"] = scriptName;
        return result;
    }

    private async Task<Dictionary<string, object>> ExecuteProcessAsync(string arguments, CancellationToken ct)
    {
        var result = new Dictionary<string, object> { { "executed", true } };
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        try
        {
            using var process = Process.Start(psi);
            if (process != null)
            {
                string output = await process.StandardOutput.ReadToEndAsync(ct);
                string error = await process.StandardError.ReadToEndAsync(ct);
                await process.WaitForExitAsync(ct);

                result["exitCode"] = process.ExitCode;
                result["output"] = output;
                if (!string.IsNullOrEmpty(error)) result["error"] = error;
            }
            else
            {
                result["error"] = "Failed to start powershell.exe";
            }
        }
        catch (Exception ex)
        {
            result["error"] = ex.Message;
        }

        return result;
    }

    private static bool AgentEnforceRequested(Dictionary<string, object>? args)
    {
        return GetArgBool(args, "enforce", false) ||
               GetArgBool(args, "allow_high_risk", false);
    }
}
