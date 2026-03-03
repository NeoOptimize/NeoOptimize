using System;
using System.Threading.Tasks;
using NeoOptimize.Core;
using Xunit;

namespace NeoOptimize.Tests;

public class TrayServiceTests
{
    [Fact]
    public void Start_Should_Invoke_OnActionExecuted_Immediately()
    {
        var settings = new TraySettings { AutoHide = true, Sensitivity = SensitivityLevel.Medium, CheckIntervalSeconds = 1 };
        var service = new TrayService(settings);
        var called = false;
        service.OnActionExecuted += (s) => { called = true; };

        service.Start();

        Assert.True(called, "OnActionExecuted should be invoked on Start");

        service.Stop();
    }
}
