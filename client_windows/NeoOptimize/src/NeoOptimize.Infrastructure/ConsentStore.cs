using System.Text.Json;
using Microsoft.Extensions.Options;

namespace NeoOptimize.Infrastructure;

public sealed record ConsentState
{
    public bool Accepted { get; init; }
    public DateTimeOffset? AcceptedAt { get; init; }
    public DateTimeOffset? UpdatedAt { get; init; }
    public bool Telemetry { get; init; } = true;
    public bool Diagnostics { get; init; } = true;
    public bool Maintenance { get; init; } = true;
    public bool RemoteControl { get; init; }
    public bool AutoExecution { get; init; }
    public bool Location { get; init; }
    public bool Camera { get; init; }
}

public sealed class ConsentStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    private readonly string _path;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public ConsentStore(IOptions<NeoOptimizeClientOptions> options)
    {
        _path = options.Value.ConsentStatePath;
        var directory = Path.GetDirectoryName(_path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }
    }

    public async Task<ConsentState> LoadAsync(CancellationToken cancellationToken)
    {
        await _lock.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(_path))
            {
                return CreateDefault();
            }

            var json = await File.ReadAllTextAsync(_path, cancellationToken);
            return JsonSerializer.Deserialize<ConsentState>(json, JsonOptions) ?? CreateDefault();
        }
        catch
        {
            return CreateDefault();
        }
        finally
        {
            _lock.Release();
        }
    }

    public async Task<ConsentState> SaveAsync(ConsentState state, CancellationToken cancellationToken)
    {
        await _lock.WaitAsync(cancellationToken);
        try
        {
            var now = DateTimeOffset.UtcNow;
            var updated = state with { UpdatedAt = now, AcceptedAt = state.Accepted ? state.AcceptedAt ?? now : null };
            var json = JsonSerializer.Serialize(updated, JsonOptions);
            await File.WriteAllTextAsync(_path, json, cancellationToken);
            return updated;
        }
        finally
        {
            _lock.Release();
        }
    }

    private static ConsentState CreateDefault()
    {
        return new ConsentState
        {
            Accepted = false,
            Telemetry = true,
            Diagnostics = true,
            Maintenance = true,
            RemoteControl = false,
            AutoExecution = false,
            Location = false,
            Camera = false,
        };
    }
}
