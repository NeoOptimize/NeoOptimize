using System;

namespace NeoOptimize.Core.Models;

public sealed record SystemSnapshot(
    double CpuUsagePercent,
    double MemoryUsagePercent,
    double DiskUsagePercent,
    double NetworkUsageMbps,
    DateTimeOffset CapturedAt);
