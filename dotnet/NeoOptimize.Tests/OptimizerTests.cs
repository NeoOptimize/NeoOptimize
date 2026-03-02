using System;
using NeoOptimize.Core;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Tests;

public class OptimizerTests
{
    [Fact]
    public void RunSmartOptimize_ReturnsActionForHighRam()
    {
        var engine = new OptimizerEngine();
        var snapshot = new SystemSnapshot(40, 89, 55, 22, DateTimeOffset.Now);

        var result = engine.RunSmartOptimize(snapshot, true, false, false, false, false);

        Assert.True(result.Success);
        Assert.Contains("RAM release", result.Message);
    }
}
