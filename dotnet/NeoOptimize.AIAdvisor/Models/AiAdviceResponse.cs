using System;

namespace NeoOptimize.AIAdvisor.Models;

public sealed record AiAdviceResponse(
    bool Success,
    string Provider,
    string Recommendation,
    DateTimeOffset GeneratedAt);
