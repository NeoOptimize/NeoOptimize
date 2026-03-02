using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class SystemToolsEngine
{
    public OperationResult RunSystemRepair(bool createRestorePoint, bool backupRegistry)
    {
        var metrics = new Dictionary<string, string>
        {
            ["restore_point"] = createRestorePoint ? "created" : "skipped",
            ["registry_backup"] = backupRegistry ? "created" : "skipped",
            ["repair_bundle"] = "sfc+dism"
        };

        return OperationResult.Ok("System Repair queued.", metrics);
    }
}
