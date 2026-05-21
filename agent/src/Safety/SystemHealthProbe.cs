using System.Diagnostics;
using Microsoft.Extensions.Logging;
using NeoOptimize.Agent.Services;

namespace NeoOptimize.Agent.Safety;

public sealed class SystemHealthProbe
{
    private readonly ISystemCollector _collector;
    private readonly ILogger<SystemHealthProbe> _logger;

    public SystemHealthProbe(ISystemCollector collector, ILogger<SystemHealthProbe> logger)
    {
        _collector = collector;
        _logger = logger;
    }

    public HealthSnapshot Capture()
    {
        try
        {
            var telemetry = _collector.GetTelemetry();
            return new HealthSnapshot
            {
                TimestampUtc = DateTime.UtcNow,
                CpuUsagePercent = telemetry.CpuPct,
                RamUsedMb = telemetry.RamUsedMb,
                DiskFreeGb = telemetry.DiskFreeGb,
                NetRxKbps = telemetry.NetRxKbps,
                NetTxKbps = telemetry.NetTxKbps,
                GpuUsagePercent = telemetry.GpuPct,
                GpuTempC = telemetry.GpuTempC,
                CpuTempC = telemetry.CpuTempC,
                MemoryCommittedPercent = telemetry.MemoryCommittedPct,
                DiskQueueLength = telemetry.DiskQueueLength,
                DiskLatencyMs = telemetry.DiskLatencyMs,
                HandleCount = telemetry.HandleCount,
                ThreadCount = telemetry.ThreadCount,
                ProcessCount = telemetry.ProcessCount
            };
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[SAFETY] Health probe capture failed");
            return new HealthSnapshot { TimestampUtc = DateTime.UtcNow, Error = ex.Message };
        }
    }

    public IReadOnlyList<ForbiddenEventHit> FindForbiddenSystemEvents(IEnumerable<int> eventIds, DateTime sinceUtc)
    {
        var ids = eventIds.ToHashSet();
        if (ids.Count == 0 || !OperatingSystem.IsWindows()) return Array.Empty<ForbiddenEventHit>();

        var hits = new List<ForbiddenEventHit>();
        try
        {
            using var log = new EventLog("System");
            var sinceLocal = sinceUtc.ToLocalTime();

            for (var i = log.Entries.Count - 1; i >= 0; i--)
            {
                var entry = log.Entries[i];
                if (entry.TimeGenerated < sinceLocal) break;

                var eventId = unchecked((int)(entry.InstanceId & 0xFFFF));
                if (ids.Contains(eventId))
                {
                    hits.Add(new ForbiddenEventHit
                    {
                        EventId = eventId,
                        Source = entry.Source,
                        TimeGeneratedUtc = entry.TimeGenerated.ToUniversalTime(),
                        Message = entry.Message.Length > 500 ? entry.Message[..500] : entry.Message
                    });
                }

                if (hits.Count >= 10) break;
            }
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "[SAFETY] Forbidden event scan skipped");
        }

        return hits;
    }

    public static Dictionary<string, object> BuildImpact(HealthSnapshot baseline, HealthSnapshot post)
    {
        var impact = new Dictionary<string, object>
        {
            ["cpu_usage_baseline_percent"] = Box(baseline.CpuUsagePercent),
            ["cpu_usage_post_percent"] = Box(post.CpuUsagePercent),
            ["ram_used_baseline_mb"] = Box(baseline.RamUsedMb),
            ["ram_used_post_mb"] = Box(post.RamUsedMb),
            ["disk_free_baseline_gb"] = Box(baseline.DiskFreeGb),
            ["disk_free_post_gb"] = Box(post.DiskFreeGb),
            ["net_rx_baseline_kbps"] = Box(baseline.NetRxKbps),
            ["net_rx_post_kbps"] = Box(post.NetRxKbps),
            ["net_tx_baseline_kbps"] = Box(baseline.NetTxKbps),
            ["net_tx_post_kbps"] = Box(post.NetTxKbps),
            ["gpu_usage_baseline_percent"] = Box(baseline.GpuUsagePercent),
            ["gpu_usage_post_percent"] = Box(post.GpuUsagePercent),
            ["memory_committed_baseline_percent"] = Box(baseline.MemoryCommittedPercent),
            ["memory_committed_post_percent"] = Box(post.MemoryCommittedPercent),
            ["disk_queue_baseline"] = Box(baseline.DiskQueueLength),
            ["disk_queue_post"] = Box(post.DiskQueueLength),
            ["disk_latency_baseline_ms"] = Box(baseline.DiskLatencyMs),
            ["disk_latency_post_ms"] = Box(post.DiskLatencyMs),
            ["handle_count"] = Box(post.HandleCount),
            ["thread_count"] = Box(post.ThreadCount),
            ["process_count"] = Box(post.ProcessCount)
        };

        if (baseline.RamUsedMb.HasValue && post.RamUsedMb.HasValue)
        {
            var deltaMb = post.RamUsedMb.Value - baseline.RamUsedMb.Value;
            impact["ram_used_mb_delta"] = deltaMb;
            impact["ram_used_bytes_delta"] = deltaMb * 1024L * 1024L;
        }

        if (baseline.DiskFreeGb.HasValue && post.DiskFreeGb.HasValue)
            impact["disk_free_gb_delta"] = Math.Round(post.DiskFreeGb.Value - baseline.DiskFreeGb.Value, 2);

        if (baseline.CpuUsagePercent.HasValue && post.CpuUsagePercent.HasValue)
            impact["cpu_usage_delta_percent"] = Math.Round(post.CpuUsagePercent.Value - baseline.CpuUsagePercent.Value, 2);

        if (baseline.DiskLatencyMs.HasValue && post.DiskLatencyMs.HasValue)
            impact["disk_latency_delta_ms"] = Math.Round(post.DiskLatencyMs.Value - baseline.DiskLatencyMs.Value, 2);

        if (baseline.DiskQueueLength.HasValue && post.DiskQueueLength.HasValue)
            impact["disk_queue_delta"] = Math.Round(post.DiskQueueLength.Value - baseline.DiskQueueLength.Value, 2);

        return impact;
    }

    private static object Box<T>(T? value) where T : struct
    {
        return value.HasValue ? value.Value : "";
    }
}

public sealed class HealthSnapshot
{
    public DateTime TimestampUtc { get; set; } = DateTime.UtcNow;
    public float? CpuUsagePercent { get; set; }
    public int? RamUsedMb { get; set; }
    public float? DiskFreeGb { get; set; }
    public float? NetRxKbps { get; set; }
    public float? NetTxKbps { get; set; }
    public float? GpuUsagePercent { get; set; }
    public float? GpuTempC { get; set; }
    public float? CpuTempC { get; set; }
    public float? MemoryCommittedPercent { get; set; }
    public float? DiskQueueLength { get; set; }
    public float? DiskLatencyMs { get; set; }
    public int? HandleCount { get; set; }
    public int? ThreadCount { get; set; }
    public int? ProcessCount { get; set; }
    public string? Error { get; set; }
}

public sealed class ForbiddenEventHit
{
    public int EventId { get; set; }
    public string Source { get; set; } = "";
    public DateTime TimeGeneratedUtc { get; set; }
    public string Message { get; set; } = "";
}
