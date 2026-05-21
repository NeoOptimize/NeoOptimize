using System.Text.Json.Serialization;

namespace NeoOptimize.Agent.Models;

// ─── Check-In ────────────────────────────────────────────────────
public class CheckInRequest
{
    [JsonPropertyName("uuid")]     public string Uuid     { get; set; } = "";
    [JsonPropertyName("hostname")] public string Hostname { get; set; } = "";
    [JsonPropertyName("version")]  public string Version  { get; set; } = "";
    [JsonPropertyName("meta")]     public Dictionary<string, string> Meta { get; set; } = new();
}

public class CheckInResponse
{
    [JsonPropertyName("id")]   public string? Id   { get; set; }
    [JsonPropertyName("cmd")]  public string? Cmd  { get; set; }
    [JsonPropertyName("args")] public Dictionary<string, object>? Args { get; set; }
    [JsonPropertyName("sig")]  public string? Sig  { get; set; }
    [JsonPropertyName("timeout_secs")] public int TimeoutSecs { get; set; } = 300;
}

// ─── Telemetry ───────────────────────────────────────────────────
public class TelemetryRequest
{
    [JsonPropertyName("uuid")]          public string Uuid      { get; set; } = "";
    [JsonPropertyName("hostname")]      public string Hostname  { get; set; } = "";
    [JsonPropertyName("ts")]            public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    [JsonPropertyName("schema_version")] public int SchemaVersion { get; set; } = 2;
    [JsonPropertyName("sample_kind")]   public string SampleKind { get; set; } = "periodic";
    [JsonPropertyName("active_command_id")] public string? ActiveCommandId { get; set; }

    // ── Performance ──
    [JsonPropertyName("cpu_pct")]       public float? CpuPct      { get; set; }
    [JsonPropertyName("cpu_kernel_pct")] public float? CpuKernelPct { get; set; }
    [JsonPropertyName("cpu_clock_mhz")] public float? CpuClockMhz { get; set; }
    [JsonPropertyName("ram_used_mb")]   public int?   RamUsedMb   { get; set; }
    [JsonPropertyName("memory_available_mb")] public int? MemoryAvailableMb { get; set; }
    [JsonPropertyName("memory_committed_pct")] public float? MemoryCommittedPct { get; set; }
    [JsonPropertyName("memory_cache_faults_sec")] public float? MemoryCacheFaultsSec { get; set; }
    [JsonPropertyName("disk_free_gb")]  public float? DiskFreeGb  { get; set; }
    [JsonPropertyName("disk_read_bytes_sec")] public double? DiskReadBytesSec { get; set; }
    [JsonPropertyName("disk_write_bytes_sec")] public double? DiskWriteBytesSec { get; set; }
    [JsonPropertyName("disk_rw_bytes_sec")] public double? DiskRwBytesSec { get; set; }
    [JsonPropertyName("disk_queue_length")] public float? DiskQueueLength { get; set; }
    [JsonPropertyName("disk_time_pct")] public float? DiskTimePct { get; set; }
    [JsonPropertyName("disk_latency_ms")] public float? DiskLatencyMs { get; set; }
    [JsonPropertyName("net_rx_kbps")]   public float? NetRxKbps   { get; set; }
    [JsonPropertyName("net_tx_kbps")]   public float? NetTxKbps   { get; set; }
    [JsonPropertyName("network_bandwidth_bps")] public double? NetworkBandwidthBps { get; set; }
    [JsonPropertyName("network_bytes_total_sec")] public double? NetworkBytesTotalSec { get; set; }
    [JsonPropertyName("network_output_queue_length")] public float? NetworkOutputQueueLength { get; set; }
    [JsonPropertyName("network_latency_ms")] public float? NetworkLatencyMs { get; set; }
    [JsonPropertyName("power_profile")] public string? PowerProfile { get; set; }
    [JsonPropertyName("on_battery")]    public bool? OnBattery { get; set; }
    [JsonPropertyName("handle_count")]  public int? HandleCount { get; set; }
    [JsonPropertyName("thread_count")]  public int? ThreadCount { get; set; }
    [JsonPropertyName("process_count")] public int? ProcessCount { get; set; }

    // ── GPU / Temperature (NEW v5.0) ──
    [JsonPropertyName("gpu_pct")]       public float? GpuPct      { get; set; }
    [JsonPropertyName("gpu_temp_c")]    public float? GpuTempC    { get; set; }
    [JsonPropertyName("cpu_temp_c")]    public float? CpuTempC    { get; set; }
    [JsonPropertyName("gpu_name")]      public string? GpuName    { get; set; }

    // ── Sensors ──
    [JsonPropertyName("cam_active")]    public bool? CamActive    { get; set; }
    [JsonPropertyName("mic_active")]    public bool? MicActive    { get; set; }
    [JsonPropertyName("camera_available")] public bool? CameraAvailable { get; set; }
    [JsonPropertyName("microphone_available")] public bool? MicrophoneAvailable { get; set; }
    [JsonPropertyName("biometric_available")] public bool? BiometricAvailable { get; set; }

    // ── Network / Location ──
    [JsonPropertyName("public_ip")]     public string? PublicIp   { get; set; }
    [JsonPropertyName("geo_city")]      public string? GeoCity    { get; set; }
    [JsonPropertyName("geo_country")]   public string? GeoCountry { get; set; }
    [JsonPropertyName("geo_lat")]       public double? GeoLat     { get; set; }
    [JsonPropertyName("geo_lon")]       public double? GeoLon     { get; set; }
    [JsonPropertyName("location_label")] public string? LocationLabel { get; set; }
    [JsonPropertyName("location_detail")] public Dictionary<string, object?> LocationDetail { get; set; } = new();

    // ── AI telemetry envelope ──
    [JsonPropertyName("metrics")]        public Dictionary<string, object?> Metrics { get; set; } = new();
    [JsonPropertyName("host_baseline")]  public Dictionary<string, object?> HostBaseline { get; set; } = new();
    [JsonPropertyName("security_state")] public Dictionary<string, object?> SecurityState { get; set; } = new();
    [JsonPropertyName("device_info")]    public Dictionary<string, object?> DeviceInfo { get; set; } = new();
    [JsonPropertyName("bugs")]           public Dictionary<string, object?> Bugs { get; set; } = new();
    [JsonPropertyName("verbose_info")]   public Dictionary<string, object?> VerboseInfo { get; set; } = new();
}

// ─── Report ──────────────────────────────────────────────────────
public class ReportRequest
{
    [JsonPropertyName("uuid")]    public string Uuid   { get; set; } = "";
    [JsonPropertyName("cmd_id")] public string CmdId  { get; set; } = "";
    [JsonPropertyName("status")] public string Status { get; set; } = "";
    [JsonPropertyName("result")] public Dictionary<string, object> Result { get; set; } = new();
}
