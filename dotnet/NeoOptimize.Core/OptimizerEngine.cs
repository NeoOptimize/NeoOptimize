using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class OptimizerEngine
{
    public OperationResult RunSmartOptimize(
        SystemSnapshot snapshot,
        bool privacyPackEnabled,
        bool manualCpuTuning,
        bool manualRamTuning,
        bool manualDiskTuning,
        bool manualNetworkTuning)
    {
        var actions = new List<string>();

        if (snapshot.MemoryUsagePercent >= 80) actions.Add("RAM release");
        if (snapshot.CpuUsagePercent >= 80) actions.Add("process priority rebalance");
        if (snapshot.DiskUsagePercent >= 85) actions.Add("disk cleanup profile");
        if (snapshot.NetworkUsageMbps >= 120) actions.Add("dns flush");

        if (manualCpuTuning) actions.Add("manual cpu tuning");
        if (manualRamTuning) actions.Add("manual ram tuning");
        if (manualDiskTuning) actions.Add("manual disk tuning");
        if (manualNetworkTuning) actions.Add("manual network tuning");
        if (privacyPackEnabled) actions.Add("privacy pack");

        if (actions.Count == 0) actions.Add("no high pressure detected");

        var metrics = new Dictionary<string, string>
        {
            ["cpu"] = snapshot.CpuUsagePercent.ToString("F1"),
            ["ram"] = snapshot.MemoryUsagePercent.ToString("F1"),
            ["disk"] = snapshot.DiskUsagePercent.ToString("F1"),
            ["network_mbps"] = snapshot.NetworkUsageMbps.ToString("F1")
        };

        return OperationResult.Ok($"Smart Optimize completed: {string.Join(", ", actions)}.", metrics);
    }
}
