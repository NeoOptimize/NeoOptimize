using System.Text.Json;
using Microsoft.Extensions.Options;

namespace NeoOptimize.Infrastructure;

public sealed class RegistrationStore(IOptions<NeoOptimizeClientOptions> options)
{
    private readonly string _path = options.Value.RegistrationStatePath;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
    };

    public async Task<RegistrationState?> LoadAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(_path))
        {
            return null;
        }

        await using var stream = File.OpenRead(_path);
        return await JsonSerializer.DeserializeAsync<RegistrationState>(stream, JsonOptions, cancellationToken);
    }

    public async Task SaveAsync(RegistrationState state, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(_path);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using var stream = File.Create(_path);
        await JsonSerializer.SerializeAsync(stream, state, JsonOptions, cancellationToken);
    }

    public Task ClearAsync()
    {
        if (File.Exists(_path))
        {
            File.Delete(_path);
        }

        return Task.CompletedTask;
    }
}
