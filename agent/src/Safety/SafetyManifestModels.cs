using System.Text.Json;
using System.Text.Json.Serialization;

namespace NeoOptimize.Agent.Safety;

public sealed class SafetyManifestEnvelope
{
    [JsonPropertyName("manifest")] public SafetyManifest Manifest { get; set; } = new();
    [JsonPropertyName("manifest_sha256")] public string ManifestSha256 { get; set; } = "";
    [JsonPropertyName("signature")] public string Signature { get; set; } = "";

    public static SafetyManifestEnvelope? TryExtract(Dictionary<string, object>? args)
    {
        if (args == null || !args.TryGetValue("safety_manifest", out var raw) || raw == null)
            return null;

        try
        {
            string json = raw is JsonElement element ? element.GetRawText() : JsonSerializer.Serialize(raw);
            return JsonSerializer.Deserialize<SafetyManifestEnvelope>(json, JsonOptions.Default);
        }
        catch
        {
            return null;
        }
    }
}

public sealed class SafetyManifest
{
    [JsonPropertyName("$schema")] public string Schema { get; set; } = "";
    [JsonPropertyName("command_id")] public string CommandId { get; set; } = "";
    [JsonPropertyName("version")] public string Version { get; set; } = "";
    [JsonPropertyName("metadata")] public SafetyManifestMetadata Metadata { get; set; } = new();
    [JsonPropertyName("policy_gate")] public SafetyPolicyGate PolicyGate { get; set; } = new();
    [JsonPropertyName("execution_control")] public SafetyExecutionControl ExecutionControl { get; set; } = new();
    [JsonPropertyName("pre_flight_safety")] public PreFlightSafety PreFlightSafety { get; set; } = new();
    [JsonPropertyName("action")] public SafetyAction Action { get; set; } = new();
    [JsonPropertyName("impact_guardrails")] public ImpactGuardrails ImpactGuardrails { get; set; } = new();
    [JsonPropertyName("rollback")] public RollbackPolicy Rollback { get; set; } = new();
}

public sealed class SafetyManifestMetadata
{
    [JsonPropertyName("author")] public string Author { get; set; } = "";
    [JsonPropertyName("description")] public string Description { get; set; } = "";
    [JsonPropertyName("created_at")] public DateTime? CreatedAt { get; set; }
}

public sealed class SafetyPolicyGate
{
    [JsonPropertyName("min_agent_version")] public string MinAgentVersion { get; set; } = "0.0.0";
    [JsonPropertyName("supported_windows_builds")] public List<string> SupportedWindowsBuilds { get; set; } = new();
    [JsonPropertyName("required_privileges")] public string RequiredPrivileges { get; set; } = "";
    [JsonPropertyName("risk_level")] public string RiskLevel { get; set; } = "HIGH";
}

public sealed class SafetyExecutionControl
{
    [JsonPropertyName("dry_run")] public bool DryRun { get; set; }
    [JsonPropertyName("global_kill_switch_enabled")] public bool GlobalKillSwitchEnabled { get; set; } = true;
    [JsonPropertyName("timeout_seconds")] public int TimeoutSeconds { get; set; } = 300;
    [JsonPropertyName("canary_policy")] public CanaryPolicy CanaryPolicy { get; set; } = new();
}

public sealed class CanaryPolicy
{
    [JsonPropertyName("enabled")] public bool Enabled { get; set; }
    [JsonPropertyName("current_phase")] public string CurrentPhase { get; set; } = "PHASE_3_FULL";
    [JsonPropertyName("target_percentage")] public double TargetPercentage { get; set; } = 100;
    [JsonPropertyName("bake_time_minutes")] public int BakeTimeMinutes { get; set; }
    [JsonPropertyName("max_allowed_failure_rate")] public double MaxAllowedFailureRate { get; set; } = 0.05;
}

public sealed class PreFlightSafety
{
    [JsonPropertyName("create_windows_restore_point")] public bool CreateWindowsRestorePoint { get; set; }
    [JsonPropertyName("restore_point_description")] public string RestorePointDescription { get; set; } = "NeoOptimize Before Command";
    [JsonPropertyName("snapshot_registry_keys")] public List<string> SnapshotRegistryKeys { get; set; } = new();
}

public sealed class SafetyAction
{
    [JsonPropertyName("type")] public string Type { get; set; } = "";
    [JsonPropertyName("command_type")] public string CommandType { get; set; } = "";
    [JsonPropertyName("payload_sha256")] public string PayloadSha256 { get; set; } = "";
}

public sealed class ImpactGuardrails
{
    [JsonPropertyName("metrics_check_interval_seconds")] public int MetricsCheckIntervalSeconds { get; set; } = 15;
    [JsonPropertyName("monitoring_duration_minutes")] public int MonitoringDurationMinutes { get; set; } = 5;
    [JsonPropertyName("thresholds")] public GuardrailThresholds Thresholds { get; set; } = new();
}

public sealed class GuardrailThresholds
{
    [JsonPropertyName("max_cpu_utilization_percent")] public double MaxCpuUtilizationPercent { get; set; } = 90;
    [JsonPropertyName("max_agent_crash_count")] public int MaxAgentCrashCount { get; set; }
    [JsonPropertyName("forbidden_event_ids")] public List<int> ForbiddenEventIds { get; set; } = new();
}

public sealed class RollbackPolicy
{
    [JsonPropertyName("trigger_on_failure")] public bool TriggerOnFailure { get; set; }
    [JsonPropertyName("type")] public string Type { get; set; } = "NOOP_SAFE_REPORT";
    [JsonPropertyName("fallback_command")] public string? FallbackCommand { get; set; }
}

internal static class JsonOptions
{
    public static readonly JsonSerializerOptions Default = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };
}
