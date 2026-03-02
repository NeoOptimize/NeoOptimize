namespace NeoOptimize.Services;

public sealed record UpdateCheckResult(bool Success, bool UpdateAvailable, string Message);

public sealed class UpdateService
{
    public UpdateCheckResult CheckForUpdates(bool onlineModeEnabled)
    {
        if (!onlineModeEnabled)
        {
            return new UpdateCheckResult(
                Success: true,
                UpdateAvailable: false,
                Message: "Offline mode enabled. Update checks are disabled by design.");
        }

        return new UpdateCheckResult(
            Success: true,
            UpdateAvailable: false,
            Message: "Online update check endpoint is not configured in this scaffold.");
    }
}
