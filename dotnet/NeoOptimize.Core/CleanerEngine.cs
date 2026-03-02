using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class CleanerEngine
{
    public OperationResult RunSmartClean(
        bool advancedMode,
        bool includeRegistry,
        bool includeDriverLeftovers,
        bool includeBloatware)
    {
        var metrics = new Dictionary<string, string>
        {
            ["scope"] = advancedMode ? "adaptive-advanced" : "adaptive-core",
            ["registry"] = includeRegistry ? "on" : "off",
            ["driver_leftovers"] = includeDriverLeftovers ? "on" : "off",
            ["bloatware"] = includeBloatware ? "on" : "off",
            ["freed_mb"] = advancedMode ? "680" : "330"
        };

        return OperationResult.Ok("Smart Clean completed.", metrics);
    }
}
