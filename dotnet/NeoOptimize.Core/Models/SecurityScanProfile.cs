namespace NeoOptimize.Core.Models;

public sealed record SecurityScanProfile(
    bool UseClamAv,
    bool UseKicomAv,
    bool UseDefenderToggle);
