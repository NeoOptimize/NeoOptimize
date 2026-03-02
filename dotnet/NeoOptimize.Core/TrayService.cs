using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class TrayService
{
    public IReadOnlyList<string> EvaluateThresholds(SystemSnapshot snapshot)
    {
        var actions = new List<string>();

        if (snapshot.CpuUsagePercent > 80) actions.Add("CPU > 80%, advise RAM release.");
        if (snapshot.MemoryUsagePercent > 85) actions.Add("RAM > 85%, advise cache flush.");
        if (snapshot.DiskUsagePercent > 90) actions.Add("Disk pressure high, advise cleanup.");
        if (snapshot.NetworkUsageMbps > 150) actions.Add("Network pressure high, advise DNS refresh.");

        return actions;
    }
}
