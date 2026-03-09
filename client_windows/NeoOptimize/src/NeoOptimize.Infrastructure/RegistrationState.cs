namespace NeoOptimize.Infrastructure;

public sealed class RegistrationState
{
    public required string ClientId { get; init; }
    public required string ClientApiKey { get; init; }
    public required string FingerprintHash { get; init; }
    public required string HardwareFingerprint { get; init; }
    public required DateTimeOffset RegisteredAt { get; init; }
}
