using System;
using NeoOptimize.Core.Models;

namespace NeoOptimize.AIAdvisor.Models;

public sealed record AiAdviceRequest(
    SystemSnapshot Snapshot,
    string[] RecentLogs,
    string ExperienceMode,
    string Language,
    DateTimeOffset RequestedAt);
