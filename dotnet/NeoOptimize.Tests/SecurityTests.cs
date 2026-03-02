using NeoOptimize.Core;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Tests;

public class SecurityTests
{
    [Fact]
    public void UnifiedScan_FailsWhenNoEngineSelected()
    {
        var engine = new SecurityEngine();
        var profile = new SecurityScanProfile(false, false, false);

        var result = engine.RunUnifiedScan(profile, true);

        Assert.False(result.Success);
        Assert.Equal("No security engine selected.", result.Message);
    }
}
