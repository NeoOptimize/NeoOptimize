using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Options;
using NeoOptimize.Contracts;

namespace NeoOptimize.Infrastructure;

public sealed class NeoOptimizeApiClient(
    HttpClient httpClient,
    IOptions<NeoOptimizeClientOptions> options,
    RegistrationStore registrationStore,
    HardwareFingerprintService hardwareFingerprintService)
{
    private readonly HttpClient _httpClient = httpClient;
    private readonly NeoOptimizeClientOptions _options = options.Value;
    private readonly RegistrationStore _registrationStore = registrationStore;
    private readonly HardwareFingerprintService _hardwareFingerprintService = hardwareFingerprintService;

    public async Task<RegistrationState> EnsureRegistrationAsync(CancellationToken cancellationToken)
    {
        var existing = await _registrationStore.LoadAsync(cancellationToken);
        if (existing is not null)
        {
            return existing;
        }

        var fingerprint = _hardwareFingerprintService.BuildFingerprint();
        var payload = new ClientRegisterRequest
        {
            DeviceName = Environment.MachineName,
            OsVersion = RuntimeInformation.OSDescription,
            AppVersion = _options.AppVersion,
            Architecture = RuntimeInformation.OSArchitecture.ToString(),
            HardwareFingerprint = fingerprint,
            Metadata = new Dictionary<string, object?>
            {
                ["service"] = "NeoOptimize.Service",
                ["registered_at_utc"] = DateTimeOffset.UtcNow,
            },
        };

        using var response = await _httpClient.PostAsJsonAsync("api/v1/auth/register", payload, cancellationToken);
        response.EnsureSuccessStatusCode();

        var registration = await response.Content.ReadFromJsonAsync<ClientRegisterResponse>(cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException("Registration response is empty.");

        var state = new RegistrationState
        {
            ClientId = registration.ClientId,
            ClientApiKey = registration.ClientApiKey,
            FingerprintHash = registration.FingerprintHash,
            HardwareFingerprint = fingerprint,
            RegisteredAt = registration.IssuedAt,
        };

        await _registrationStore.SaveAsync(state, cancellationToken);
        return state;
    }

    public async Task<TelemetryIngestResponse> PushTelemetryAsync(TelemetryPayload payload, CancellationToken cancellationToken)
    {
        var registration = await EnsureRegistrationAsync(cancellationToken);
        using var request = CreateAuthenticatedRequest(HttpMethod.Post, "api/v1/telemetry/push", registration, payload);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<TelemetryIngestResponse>(cancellationToken: cancellationToken)
            ?? new TelemetryIngestResponse { Status = "recorded" };
    }

    public async Task ReportHealthAsync(SystemHealthPayload payload, CancellationToken cancellationToken)
    {
        var registration = await EnsureRegistrationAsync(cancellationToken);
        using var request = CreateAuthenticatedRequest(HttpMethod.Post, "api/v1/health/report", registration, payload);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
    }

    public async Task<RemoteCommandPollResponse> PollCommandAsync(CancellationToken cancellationToken)
    {
        var registration = await EnsureRegistrationAsync(cancellationToken);
        using var request = CreateAuthenticatedRequest<object?>(HttpMethod.Post, "api/v1/commands/poll", registration, null);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadFromJsonAsync<RemoteCommandPollResponse>(cancellationToken: cancellationToken)
            ?? new RemoteCommandPollResponse { Status = "idle" };
    }

    public async Task SubmitCommandResultAsync(CommandResultRequest payload, CancellationToken cancellationToken)
    {
        var registration = await EnsureRegistrationAsync(cancellationToken);
        using var request = CreateAuthenticatedRequest(HttpMethod.Post, "api/v1/commands/result", registration, payload);
        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
    }

    private static HttpRequestMessage CreateAuthenticatedRequest<TPayload>(
        HttpMethod method,
        string relativeUrl,
        RegistrationState registration,
        TPayload? payload)
    {
        var request = new HttpRequestMessage(method, relativeUrl);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.Add("X-Client-ID", registration.ClientId);
        request.Headers.Add("X-Client-API-Key", registration.ClientApiKey);
        request.Headers.Add("X-Hardware-Fingerprint", registration.HardwareFingerprint);

        if (payload is not null)
        {
            request.Content = JsonContent.Create(payload);
        }

        return request;
    }
}
