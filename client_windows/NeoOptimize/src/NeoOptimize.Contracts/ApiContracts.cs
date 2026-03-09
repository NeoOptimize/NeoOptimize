using System.Text.Json.Serialization;

namespace NeoOptimize.Contracts;

public sealed class ClientRegisterRequest
{
    [JsonPropertyName("owner_user_id")]
    public string? OwnerUserId { get; init; }

    [JsonPropertyName("device_name")]
    public string? DeviceName { get; init; }

    [JsonPropertyName("os_version")]
    public string? OsVersion { get; init; }

    [JsonPropertyName("app_version")]
    public string? AppVersion { get; init; }

    [JsonPropertyName("architecture")]
    public string? Architecture { get; init; }

    [JsonPropertyName("hardware_fingerprint")]
    public required string HardwareFingerprint { get; init; }

    [JsonPropertyName("metadata")]
    public Dictionary<string, object?> Metadata { get; init; } = new();
}

public sealed class ClientRegisterResponse
{
    [JsonPropertyName("client_id")]
    public required string ClientId { get; init; }

    [JsonPropertyName("client_api_key")]
    public required string ClientApiKey { get; init; }

    [JsonPropertyName("fingerprint_hash")]
    public required string FingerprintHash { get; init; }

    [JsonPropertyName("issued_at")]
    public required DateTimeOffset IssuedAt { get; init; }
}

public sealed class TelemetryPayload
{
    [JsonPropertyName("cpu_percent")]
    public double? CpuPercent { get; init; }

    [JsonPropertyName("ram_percent")]
    public double? RamPercent { get; init; }

    [JsonPropertyName("gpu_percent")]
    public double? GpuPercent { get; init; }

    [JsonPropertyName("disk_usage_percent")]
    public double? DiskUsagePercent { get; init; }

    [JsonPropertyName("disk_read_mbps")]
    public double? DiskReadMbps { get; init; }

    [JsonPropertyName("disk_write_mbps")]
    public double? DiskWriteMbps { get; init; }

    [JsonPropertyName("temperature_celsius")]
    public double? TemperatureCelsius { get; init; }

    [JsonPropertyName("process_count")]
    public int? ProcessCount { get; init; }

    [JsonPropertyName("top_processes")]
    public List<Dictionary<string, object?>> TopProcesses { get; init; } = new();

    [JsonPropertyName("snapshot")]
    public Dictionary<string, object?> Snapshot { get; init; } = new();
}

public sealed class TelemetryIngestResponse
{
    [JsonPropertyName("status")]
    public required string Status { get; init; }

    [JsonPropertyName("alerts")]
    public List<string> Alerts { get; init; } = new();
}

public sealed class SystemHealthPayload
{
    [JsonPropertyName("overall_score")]
    public int? OverallScore { get; init; }

    [JsonPropertyName("health_state")]
    public required string HealthState { get; init; }

    [JsonPropertyName("sfc_status")]
    public string? SfcStatus { get; init; }

    [JsonPropertyName("dism_status")]
    public string? DismStatus { get; init; }

    [JsonPropertyName("thermal_status")]
    public string? ThermalStatus { get; init; }

    [JsonPropertyName("integrity_status")]
    public string? IntegrityStatus { get; init; }

    [JsonPropertyName("issues")]
    public List<Dictionary<string, object?>> Issues { get; init; } = new();

    [JsonPropertyName("recommendations")]
    public List<string> Recommendations { get; init; } = new();

    [JsonPropertyName("report")]
    public Dictionary<string, object?> Report { get; init; } = new();
}

public sealed class RemoteCommandPollResponse
{
    [JsonPropertyName("status")]
    public required string Status { get; init; }

    [JsonPropertyName("command_id")]
    public string? CommandId { get; init; }

    [JsonPropertyName("command_name")]
    public string? CommandName { get; init; }

    [JsonPropertyName("payload")]
    public Dictionary<string, object?> Payload { get; init; } = new();

    [JsonPropertyName("correlation_id")]
    public string? CorrelationId { get; init; }
}

public sealed class CommandResultRequest
{
    [JsonPropertyName("command_id")]
    public required string CommandId { get; init; }

    [JsonPropertyName("status")]
    public required string Status { get; init; }

    [JsonPropertyName("output")]
    public Dictionary<string, object?> Output { get; init; } = new();

    [JsonPropertyName("error_message")]
    public string? ErrorMessage { get; init; }
}

public sealed class PlannedAction
{
    [JsonPropertyName("command_name")]
    public required string CommandName { get; init; }

    [JsonPropertyName("reason")]
    public required string Reason { get; init; }

    [JsonPropertyName("payload")]
    public Dictionary<string, object?> Payload { get; init; } = new();

    [JsonPropertyName("priority")]
    public int Priority { get; init; }

    [JsonPropertyName("dispatched")]
    public bool Dispatched { get; init; }
}

public sealed class AIChatRequest
{
    [JsonPropertyName("message")]
    public required string Message { get; init; }

    [JsonPropertyName("client_id")]
    public string? ClientId { get; init; }

    [JsonPropertyName("dispatch_actions")]
    public bool DispatchActions { get; init; }
}

public sealed class AIChatResponse
{
    [JsonPropertyName("reply")]
    public required string Reply { get; init; }

    [JsonPropertyName("correlation_id")]
    public required string CorrelationId { get; init; }

    [JsonPropertyName("planned_actions")]
    public List<PlannedAction> PlannedActions { get; init; } = new();

    [JsonPropertyName("context_summary")]
    public Dictionary<string, object?> ContextSummary { get; init; } = new();
}
