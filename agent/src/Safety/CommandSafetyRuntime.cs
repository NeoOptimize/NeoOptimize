using System.Diagnostics;
using System.Reflection;
using System.Security.Principal;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace NeoOptimize.Agent.Safety;

public sealed class CommandSafetyRuntime
{
    private static readonly HashSet<string> ActiveStates = new(StringComparer.OrdinalIgnoreCase)
    {
        "PRE_FLIGHT",
        "EXECUTING",
        "MONITORING",
        "ROLLBACK"
    };

    private readonly AgentSecureStore _store;
    private readonly RegistrySnapshotManager _registrySnapshots;
    private readonly WindowsRestorePointManager _restorePoints;
    private readonly SystemHealthProbe _healthProbe;
    private readonly ILogger<CommandSafetyRuntime> _logger;
    private readonly int _crashLoopThreshold;
    private readonly int _maxMonitoringSeconds;

    public CommandSafetyRuntime(
        AgentSecureStore store,
        RegistrySnapshotManager registrySnapshots,
        WindowsRestorePointManager restorePoints,
        SystemHealthProbe healthProbe,
        IConfiguration configuration,
        ILogger<CommandSafetyRuntime> logger)
    {
        _store = store;
        _registrySnapshots = registrySnapshots;
        _restorePoints = restorePoints;
        _healthProbe = healthProbe;
        _logger = logger;
        _crashLoopThreshold = ReadInt(configuration, "Safety:CrashLoopThreshold", 2);
        _maxMonitoringSeconds = ReadInt(configuration, "Safety:MaxMonitoringSeconds", 900);
    }

    public async Task<Dictionary<string, object>> RunAsync(
        string cmdType,
        Dictionary<string, object>? args,
        CancellationToken ct,
        Func<Task<Dictionary<string, object>>> executeCore)
    {
        var envelope = SafetyManifestEnvelope.TryExtract(args);
        if (envelope == null || string.IsNullOrWhiteSpace(envelope.Manifest.CommandId))
        {
            return await executeCore();
        }

        var manifest = envelope.Manifest;
        var commandId = manifest.CommandId;
        var risk = NormalizeRisk(manifest.PolicyGate.RiskLevel);
        var startedAtUtc = DateTime.UtcNow;
        var stopwatch = Stopwatch.StartNew();

        var state = new SafetyExecutionState
        {
            CommandId = commandId,
            CommandType = cmdType,
            ManifestSha256 = envelope.ManifestSha256,
            Status = "PRE_FLIGHT",
            RiskLevel = risk,
            StartedAtUtc = startedAtUtc,
            Metadata =
            {
                ["canary_phase"] = manifest.ExecutionControl.CanaryPolicy.CurrentPhase,
                ["dry_run"] = manifest.ExecutionControl.DryRun,
                ["manifest_version"] = manifest.Version
            }
        };

        _store.WriteState(state);
        _logger.LogInformation("[SAFETY] Pre-flight started for {Command} {CommandId} risk={Risk}", cmdType, commandId, risk);

        var validation = ValidateManifest(cmdType, manifest);
        if (!validation.Ok)
        {
            state.Status = "REJECTED";
            _store.WriteState(state);
            return RejectedResult(commandId, cmdType, risk, validation.Reason);
        }

        var baseline = _healthProbe.Capture();
        state.Baseline = baseline;
        _store.WriteState(state);

        var safety = CreateSafetySummary(commandId, cmdType, risk, manifest, envelope);
        safety["baseline"] = baseline;

        RestorePointResult? restorePoint = null;
        if (manifest.PreFlightSafety.CreateWindowsRestorePoint)
        {
            restorePoint = await _restorePoints.CreateAsync(manifest.PreFlightSafety.RestorePointDescription, ct);
            safety["restore_point"] = restorePoint;

            if (risk == "CRITICAL" && !restorePoint.Success)
            {
                state.Status = "REJECTED";
                state.Metadata["reject_reason"] = "restore_point_required_but_failed";
                _store.WriteState(state);
                return RejectedResult(commandId, cmdType, risk, "restore_point_required_but_failed", safety);
            }
        }

        var snapshotResults = await _registrySnapshots.CaptureAsync(
            manifest.PreFlightSafety.SnapshotRegistryKeys,
            commandId,
            ct);
        safety["registry_snapshots"] = snapshotResults;

        state.SnapshotFiles = snapshotResults
            .Where(result => result.Success && !string.IsNullOrWhiteSpace(result.FileName))
            .Select(result => result.FileName!)
            .ToList();
        _store.WriteState(state);

        if (manifest.Rollback.TriggerOnFailure &&
            risk == "CRITICAL" &&
            manifest.PreFlightSafety.SnapshotRegistryKeys.Count > 0 &&
            state.SnapshotFiles.Count == 0)
        {
            state.Status = "REJECTED";
            state.Metadata["reject_reason"] = "critical_snapshot_required_but_failed";
            _store.WriteState(state);
            return RejectedResult(commandId, cmdType, risk, "critical_snapshot_required_but_failed", safety);
        }

        if (manifest.ExecutionControl.DryRun)
        {
            state.Status = "SUCCESS";
            _store.WriteState(state);
            _store.ResetCrashCounter();

            return new Dictionary<string, object>
            {
                ["executed"] = false,
                ["dry_run"] = true,
                ["command"] = cmdType,
                ["report_status"] = "success",
                ["self_healing"] = safety,
                ["impact"] = SystemHealthProbe.BuildImpact(baseline, _healthProbe.Capture())
            };
        }

        state.Status = "EXECUTING";
        _store.WriteState(state);

        Dictionary<string, object> result;
        try
        {
            result = await executeCore();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            result = new Dictionary<string, object>
            {
                ["executed"] = false,
                ["error"] = ex.Message,
                ["exception"] = ex.GetType().Name
            };
        }

        if (ResultIndicatesFailure(result))
        {
            safety["execution_failed"] = true;
            if (manifest.Rollback.TriggerOnFailure)
            {
                return await RollbackResultAsync(state, manifest, baseline, result, "execution_failed", safety);
            }

            state.Status = "FAILED";
            _store.WriteState(state);
            result["report_status"] = "failed";
            result["self_healing"] = safety;
            result["impact"] = SystemHealthProbe.BuildImpact(baseline, _healthProbe.Capture());
            return result;
        }

        state.Status = "MONITORING";
        _store.WriteState(state);

        GuardrailObservationResult guardrail;
        try
        {
            guardrail = await ObserveGuardrailsAsync(manifest, startedAtUtc, stopwatch.Elapsed, ct);
        }
        catch (OperationCanceledException)
        {
            return await RollbackResultAsync(state, manifest, baseline, result, "command_timeout_during_guardrail", safety, reportStatus: "timeout");
        }

        safety["guardrail"] = guardrail;
        var post = guardrail.FinalSnapshot ?? _healthProbe.Capture();
        var impact = SystemHealthProbe.BuildImpact(baseline, post);

        if (guardrail.Violated && manifest.Rollback.TriggerOnFailure)
        {
            return await RollbackResultAsync(state, manifest, baseline, result, guardrail.Reason, safety, impact);
        }

        state.Status = "SUCCESS";
        _store.WriteState(state);
        _store.ResetCrashCounter();

        result["report_status"] = "success";
        result["self_healing"] = safety;
        result["impact"] = impact;
        return result;
    }

    public async Task<Dictionary<string, object>?> RecoverPendingExecutionAsync(CancellationToken ct)
    {
        var state = _store.ReadState();
        if (state == null || !ActiveStates.Contains(state.Status)) return null;

        var count = _store.IncrementCrashCounter();
        _logger.LogWarning(
            "[SAFETY] Pending command state detected on startup: {CommandId} state={State} crash_count={Count}/{Threshold}",
            state.CommandId,
            state.Status,
            count,
            _crashLoopThreshold);

        if (count < _crashLoopThreshold) return null;

        state.Status = "ROLLBACK";
        _store.WriteState(state);

        var restore = await _registrySnapshots.RestoreAsync(state.SnapshotFiles, CancellationToken.None);
        state.Status = "EMERGENCY_ROLLBACK";
        state.Metadata["rollback_reason"] = "crash_loop_detected";
        state.Metadata["crash_count"] = count;
        _store.WriteState(state);
        _store.ResetCrashCounter();

        return new Dictionary<string, object>
        {
            ["command_id"] = state.CommandId,
            ["command"] = state.CommandType,
            ["report_status"] = "failed",
            ["rollback"] = true,
            ["rolled_back"] = true,
            ["error"] = "crash_loop_detected",
            ["self_healing"] = new Dictionary<string, object>
            {
                ["status"] = "EMERGENCY_ROLLBACK",
                ["reason"] = "crash_loop_detected",
                ["risk_level"] = state.RiskLevel,
                ["registry_restore"] = restore
            }
        };
    }

    private async Task<Dictionary<string, object>> RollbackResultAsync(
        SafetyExecutionState state,
        SafetyManifest manifest,
        HealthSnapshot baseline,
        Dictionary<string, object> originalResult,
        string reason,
        Dictionary<string, object> safety,
        Dictionary<string, object>? impact = null,
        string reportStatus = "failed")
    {
        state.Status = "ROLLBACK";
        state.Metadata["rollback_reason"] = reason;
        _store.WriteState(state);

        var restore = await _registrySnapshots.RestoreAsync(state.SnapshotFiles, CancellationToken.None);
        var postRollback = _healthProbe.Capture();
        var finalImpact = impact ?? SystemHealthProbe.BuildImpact(baseline, postRollback);

        safety["status"] = "ROLLBACK";
        safety["rollback_reason"] = reason;
        safety["registry_restore"] = restore;
        safety["fallback_command"] = manifest.Rollback.FallbackCommand ?? "";

        state.Status = "ROLLBACK_COMPLETE";
        _store.WriteState(state);
        _store.ResetCrashCounter();

        var result = new Dictionary<string, object>(originalResult)
        {
            ["report_status"] = reportStatus,
            ["rollback"] = true,
            ["rolled_back"] = true,
            ["error"] = originalResult.TryGetValue("error", out var error) ? error : reason,
            ["self_healing"] = safety,
            ["impact"] = finalImpact
        };
        return result;
    }

    private async Task<GuardrailObservationResult> ObserveGuardrailsAsync(
        SafetyManifest manifest,
        DateTime sinceUtc,
        TimeSpan elapsed,
        CancellationToken ct)
    {
        var risk = NormalizeRisk(manifest.PolicyGate.RiskLevel);
        var desiredSeconds = risk switch
        {
            "LOW" => 0,
            "MEDIUM" => Math.Min(15, manifest.ImpactGuardrails.MonitoringDurationMinutes * 60),
            _ => manifest.ImpactGuardrails.MonitoringDurationMinutes * 60
        };

        var timeoutBudget = manifest.ExecutionControl.TimeoutSeconds > 0
            ? Math.Max(0, manifest.ExecutionControl.TimeoutSeconds - (int)Math.Ceiling(elapsed.TotalSeconds) - 15)
            : desiredSeconds;

        var monitorSeconds = Math.Min(Math.Min(desiredSeconds, _maxMonitoringSeconds), timeoutBudget);
        var intervalSeconds = Math.Clamp(manifest.ImpactGuardrails.MetricsCheckIntervalSeconds, 5, 60);
        var result = new GuardrailObservationResult
        {
            ObservedSeconds = monitorSeconds,
            CheckIntervalSeconds = intervalSeconds
        };

        if (monitorSeconds <= 0)
        {
            result.FinalSnapshot = _healthProbe.Capture();
            result.Reason = "guardrail_skipped_or_no_timeout_budget";
            return result;
        }

        var end = DateTime.UtcNow.AddSeconds(monitorSeconds);
        while (DateTime.UtcNow < end)
        {
            ct.ThrowIfCancellationRequested();

            var snapshot = _healthProbe.Capture();
            result.FinalSnapshot = snapshot;
            result.Samples++;

            var maxCpu = manifest.ImpactGuardrails.Thresholds.MaxCpuUtilizationPercent;
            if (snapshot.CpuUsagePercent.HasValue && maxCpu > 0 && snapshot.CpuUsagePercent.Value > maxCpu)
            {
                result.Violated = true;
                result.Reason = $"cpu_above_threshold_{maxCpu}";
                return result;
            }

            var forbidden = _healthProbe.FindForbiddenSystemEvents(manifest.ImpactGuardrails.Thresholds.ForbiddenEventIds, sinceUtc);
            if (forbidden.Count > 0)
            {
                result.Violated = true;
                result.Reason = "forbidden_system_event_detected";
                result.ForbiddenEvents = forbidden;
                return result;
            }

            var remaining = end - DateTime.UtcNow;
            if (remaining <= TimeSpan.Zero) break;
            await Task.Delay(TimeSpan.FromSeconds(Math.Min(intervalSeconds, Math.Max(1, remaining.TotalSeconds))), ct);
        }

        result.FinalSnapshot ??= _healthProbe.Capture();
        result.Reason = "guardrail_passed";
        return result;
    }

    private static Dictionary<string, object> RejectedResult(
        string commandId,
        string cmdType,
        string risk,
        string reason,
        Dictionary<string, object>? safety = null)
    {
        safety ??= CreateBaseSafetySummary(commandId, cmdType, risk);
        safety["status"] = "REJECTED";
        safety["reject_reason"] = reason;

        return new Dictionary<string, object>
        {
            ["executed"] = false,
            ["rejected"] = true,
            ["report_status"] = "failed",
            ["command"] = cmdType,
            ["reason"] = reason,
            ["error"] = reason,
            ["self_healing"] = safety
        };
    }

    private Dictionary<string, object> CreateSafetySummary(
        string commandId,
        string cmdType,
        string risk,
        SafetyManifest manifest,
        SafetyManifestEnvelope envelope)
    {
        var safety = CreateBaseSafetySummary(commandId, cmdType, risk);
        safety["status"] = "PRE_FLIGHT";
        safety["manifest_sha256"] = envelope.ManifestSha256;
        safety["manifest_signature_present"] = !string.IsNullOrWhiteSpace(envelope.Signature);
        safety["canary_phase"] = manifest.ExecutionControl.CanaryPolicy.CurrentPhase;
        safety["dry_run"] = manifest.ExecutionControl.DryRun;
        safety["secure_store"] = _store.RootPath;
        return safety;
    }

    private static Dictionary<string, object> CreateBaseSafetySummary(string commandId, string cmdType, string risk)
    {
        return new Dictionary<string, object>
        {
            ["runtime"] = "NeoOptimize Windows Agent Self-Healing",
            ["command_id"] = commandId,
            ["command"] = cmdType,
            ["risk_level"] = risk,
            ["timestamp_utc"] = DateTime.UtcNow.ToString("O")
        };
    }

    private static ValidationResult ValidateManifest(string cmdType, SafetyManifest manifest)
    {
        if (string.IsNullOrWhiteSpace(manifest.CommandId))
            return ValidationResult.Fail("manifest_command_id_missing");

        if (!string.IsNullOrWhiteSpace(manifest.Action.CommandType) &&
            !string.Equals(manifest.Action.CommandType, cmdType, StringComparison.OrdinalIgnoreCase))
        {
            return ValidationResult.Fail("manifest_action_command_mismatch");
        }

        var minVersion = manifest.PolicyGate.MinAgentVersion;
        var agentVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";
        if (!string.IsNullOrWhiteSpace(minVersion) && CompareVersions(agentVersion, minVersion) < 0)
            return ValidationResult.Fail($"agent_version_below_{minVersion}");

        if (OperatingSystem.IsWindows() && manifest.PolicyGate.SupportedWindowsBuilds.Count > 0)
        {
            var osVersion = Environment.OSVersion.Version.ToString();
            if (!manifest.PolicyGate.SupportedWindowsBuilds.Any(build => osVersion.Contains(build, StringComparison.OrdinalIgnoreCase)))
                return ValidationResult.Fail("unsupported_windows_build");
        }

        if (OperatingSystem.IsWindows() &&
            manifest.PolicyGate.RequiredPrivileges.Contains("SYSTEM", StringComparison.OrdinalIgnoreCase) &&
            IsHighRisk(manifest.PolicyGate.RiskLevel) &&
            !IsRunningAsLocalSystem())
        {
            return ValidationResult.Fail("required_privilege_not_satisfied");
        }

        return ValidationResult.Pass();
    }

    private static bool ResultIndicatesFailure(Dictionary<string, object> result)
    {
        if (TryGetBool(result, "rejected") || TryGetBool(result, "rollback") || TryGetBool(result, "rolled_back"))
            return true;

        if (TryGetInt(result, "exitCode", out var exitCode) && exitCode != 0)
            return true;

        return result.TryGetValue("error", out var error) &&
               error != null &&
               !string.IsNullOrWhiteSpace(Convert.ToString(error));
    }

    private static bool TryGetBool(Dictionary<string, object> result, string key)
    {
        return result.TryGetValue(key, out var value) && value switch
        {
            bool boolValue => boolValue,
            string text => bool.TryParse(text, out var parsed) && parsed,
            _ => false
        };
    }

    private static bool TryGetInt(Dictionary<string, object> result, string key, out int number)
    {
        number = 0;
        if (!result.TryGetValue(key, out var value) || value == null) return false;
        try
        {
            number = Convert.ToInt32(value);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsRunningAsLocalSystem()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            return identity.User?.IsWellKnown(WellKnownSidType.LocalSystemSid) == true;
        }
        catch
        {
            return false;
        }
    }

    private static bool IsHighRisk(string risk)
    {
        var normalized = NormalizeRisk(risk);
        return normalized is "HIGH" or "CRITICAL";
    }

    private static string NormalizeRisk(string? risk)
    {
        var normalized = (risk ?? "HIGH").Trim().ToUpperInvariant();
        return normalized is "LOW" or "MEDIUM" or "HIGH" or "CRITICAL" ? normalized : "HIGH";
    }

    private static int CompareVersions(string actual, string minimum)
    {
        var left = ParseVersion(actual);
        var right = ParseVersion(minimum);
        var length = Math.Max(left.Count, right.Count);
        for (var i = 0; i < length; i++)
        {
            var a = i < left.Count ? left[i] : 0;
            var b = i < right.Count ? right[i] : 0;
            if (a > b) return 1;
            if (a < b) return -1;
        }
        return 0;
    }

    private static List<int> ParseVersion(string version)
    {
        return version
            .Split('.', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => int.TryParse(new string(part.TakeWhile(char.IsDigit).ToArray()), out var value) ? value : 0)
            .ToList();
    }

    private static int ReadInt(IConfiguration configuration, string key, int fallback)
    {
        var value = configuration[key] ?? configuration[$"Agent:{key}"];
        return int.TryParse(value, out var parsed) && parsed > 0 ? parsed : fallback;
    }

    private sealed record ValidationResult(bool Ok, string Reason)
    {
        public static ValidationResult Pass() => new(true, "");
        public static ValidationResult Fail(string reason) => new(false, reason);
    }
}

public sealed class GuardrailObservationResult
{
    public bool Violated { get; set; }
    public string Reason { get; set; } = "";
    public int ObservedSeconds { get; set; }
    public int CheckIntervalSeconds { get; set; }
    public int Samples { get; set; }
    public HealthSnapshot? FinalSnapshot { get; set; }
    public IReadOnlyList<ForbiddenEventHit> ForbiddenEvents { get; set; } = Array.Empty<ForbiddenEventHit>();
}
