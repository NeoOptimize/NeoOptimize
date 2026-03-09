namespace NeoOptimize.Infrastructure;

public sealed class NeoOptimizeClientOptions
{
    public const string SectionName = "NeoOptimize";

    public string BackendBaseUrl { get; set; } = "https://neooptimize-neooptimize.hf.space/";
    public string AppVersion { get; set; } = "0.1.0";
    public string RegistrationStatePath { get; set; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
        "NeoOptimize",
        "registration.json");
    public int TelemetryIntervalSeconds { get; set; } = 60;
    public int HealthIntervalMinutes { get; set; } = 60;
    public int CommandPollIntervalSeconds { get; set; } = 30;
    public int SmartBoosterIntervalMinutes { get; set; } = 30;
    public int IntegrityIntervalHours { get; set; } = 24;
}
