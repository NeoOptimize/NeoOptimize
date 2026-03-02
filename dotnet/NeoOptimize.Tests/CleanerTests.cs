using NeoOptimize.Core;

namespace NeoOptimize.Tests;

public class CleanerTests
{
    [Fact]
    public void RunSmartClean_ReturnsSuccessAndMetrics()
    {
        var engine = new CleanerEngine();

        var result = engine.RunSmartClean(true, true, false, false);

        Assert.True(result.Success);
        Assert.NotNull(result.Metrics);
        Assert.Equal("adaptive-advanced", result.Metrics!["scope"]);
    }
}
