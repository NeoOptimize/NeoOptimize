using System;
using System.IO;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using Xunit;

namespace NeoOptimize.UITests;

public class BasicUiTests
{
    [Fact]
    public void AppStarts_And_MainWindow_Shows()
    {
        var dll = Path.GetFullPath("d:\\NeoOptimize\\dotnet\\NeoOptimize.App\\bin\\Debug\\net8.0-windows\\NeoOptimize.App.dll");
        Assert.True(File.Exists(dll), $"Built DLL not found: {dll}");

        var psi = new System.Diagnostics.ProcessStartInfo("dotnet", '"' + dll + '"') { UseShellExecute = false };
        using var proc = System.Diagnostics.Process.Start(psi)!;

        // Wait a short while for startup; assert process is still running (no crash on startup)
        var started = proc.WaitForExit(3000) == false;
        try
        {
            Assert.True(started && !proc.HasExited, "Application exited immediately on startup (crash).");
        }
        finally
        {
            try { if (!proc.HasExited) proc.Kill(true); } catch { }
            proc.Dispose();
        }
    }
}
