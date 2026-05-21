using System.Management;
using Microsoft.Extensions.Logging;

namespace NeoOptimize.Agent.Safety;

public sealed class WindowsRestorePointManager
{
    private readonly ILogger<WindowsRestorePointManager> _logger;

    public WindowsRestorePointManager(ILogger<WindowsRestorePointManager> logger)
    {
        _logger = logger;
    }

    public Task<RestorePointResult> CreateAsync(string description, CancellationToken ct)
    {
        if (!OperatingSystem.IsWindows())
        {
            return Task.FromResult(new RestorePointResult
            {
                Success = false,
                Skipped = true,
                Message = "System restore points require Windows."
            });
        }

        try
        {
            ct.ThrowIfCancellationRequested();
            var scope = new ManagementScope(@"\\.\root\default");
            using var sysRestoreClass = new ManagementClass(scope, new ManagementPath("SystemRestore"), null);
            using var inParams = sysRestoreClass.GetMethodParameters("CreateRestorePoint");

            inParams["Description"] = string.IsNullOrWhiteSpace(description) ? "NeoOptimize Before Command" : description;
            inParams["RestorePointType"] = 12; // MODIFY_SETTINGS
            inParams["EventType"] = 100;       // BEGIN_SYSTEM_CHANGE

            using var outParams = sysRestoreClass.InvokeMethod("CreateRestorePoint", inParams, null);
            var returnValue = Convert.ToUInt32(outParams?["ReturnValue"] ?? 1);

            return Task.FromResult(new RestorePointResult
            {
                Success = returnValue == 0,
                ReturnValue = returnValue,
                Message = returnValue == 0 ? "restore_point_created" : $"restore_point_failed_{returnValue}"
            });
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[SAFETY] Restore point creation failed");
            return Task.FromResult(new RestorePointResult
            {
                Success = false,
                Message = ex.Message
            });
        }
    }
}

public sealed class RestorePointResult
{
    public bool Success { get; set; }
    public bool Skipped { get; set; }
    public uint? ReturnValue { get; set; }
    public string Message { get; set; } = "";
}
