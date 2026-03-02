using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NeoOptimize.AIAdvisor.Models;

namespace NeoOptimize.AIAdvisor;

public sealed class RuleBasedAiAdvisor : IAiAdvisor
{
    public Task<AiAdviceResponse> GetAdviceAsync(AiAdviceRequest request, CancellationToken cancellationToken)
    {
        var recommendations = new List<string>();

        if (request.Snapshot.MemoryUsagePercent > 85)
        {
            recommendations.Add("RAM sering tinggi, aktifkan auto-clean tiap 20-30 menit.");
        }

        if (request.Snapshot.CpuUsagePercent > 80)
        {
            recommendations.Add("CPU tinggi, cek proses berat lalu jalankan Smart Optimize.");
        }

        if (request.Snapshot.DiskUsagePercent > 90)
        {
            recommendations.Add("Disk pressure tinggi, jalankan Cleaner advanced untuk file sementara.");
        }

        if (!recommendations.Any())
        {
            recommendations.Add("Sistem stabil. Jadwalkan maintenance harian untuk menjaga performa.");
        }

        if (request.RecentLogs.Any(l => l.Contains("error", StringComparison.OrdinalIgnoreCase)))
        {
            recommendations.Add("Terdeteksi error pada log. Review Log Center sebelum apply optimasi berat.");
        }

        var text = string.Join(" ", recommendations.Distinct());

        return Task.FromResult(new AiAdviceResponse(
            Success: true,
            Provider: "RuleBased",
            Recommendation: text,
            GeneratedAt: DateTimeOffset.Now));
    }
}
