namespace NeoOptimize.Core.Models;

public sealed record ScheduledTask(
    string Id,
    string Cron,
    string Description,
    bool Enabled);
