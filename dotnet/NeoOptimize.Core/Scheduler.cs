using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class Scheduler
{
    private readonly List<ScheduledTask> _tasks =
    [
        new ScheduledTask("daily-clean", "0 */6 * * *", "Auto Smart Clean", true),
        new ScheduledTask("health-scan", "*/30 * * * *", "System health snapshot", true),
        new ScheduledTask("weekly-repair", "0 4 * * 0", "System repair reminder", false)
    ];

    public IReadOnlyList<ScheduledTask> GetAll() => _tasks.AsReadOnly();
}
