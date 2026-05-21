using System.Security.AccessControl;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Win32;

namespace NeoOptimize.Agent.Safety;

public sealed class RegistrySnapshotManager
{
    private readonly AgentSecureStore _store;
    private readonly ILogger<RegistrySnapshotManager> _logger;
    private readonly int _maxDepth;
    private readonly int _maxKeys;
    private readonly int _maxValues;

    public RegistrySnapshotManager(
        AgentSecureStore store,
        IConfiguration configuration,
        ILogger<RegistrySnapshotManager> logger)
    {
        _store = store;
        _logger = logger;
        _maxDepth = ReadInt(configuration, "Safety:RegistrySnapshotMaxDepth", 2);
        _maxKeys = ReadInt(configuration, "Safety:RegistrySnapshotMaxKeys", 2500);
        _maxValues = ReadInt(configuration, "Safety:RegistrySnapshotMaxValues", 10000);
    }

    public Task<IReadOnlyList<RegistrySnapshotResult>> CaptureAsync(
        IEnumerable<string> registryPaths,
        string commandId,
        CancellationToken ct)
    {
        var results = new List<RegistrySnapshotResult>();
        var paths = registryPaths
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (paths.Count == 0) return Task.FromResult<IReadOnlyList<RegistrySnapshotResult>>(results);

        if (!OperatingSystem.IsWindows())
        {
            results.AddRange(paths.Select(path => RegistrySnapshotResult.Skipped(path, "Registry snapshots require Windows.")));
            return Task.FromResult<IReadOnlyList<RegistrySnapshotResult>>(results);
        }

        foreach (var registryPath in paths)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                var fileName = _store.GetSnapshotFileName(commandId, registryPath);
                var snapshot = CapturePath(registryPath, ct);
                _store.WriteSnapshot(fileName, snapshot);

                results.Add(new RegistrySnapshotResult
                {
                    RegistryPath = registryPath,
                    FileName = fileName,
                    Success = snapshot.KeyExists,
                    Error = snapshot.KeyExists ? null : "registry_key_missing",
                    ValueCount = snapshot.ValueCount,
                    SubKeyCount = snapshot.SubKeyCount
                });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[SAFETY] Registry snapshot failed for {Path}", registryPath);
                results.Add(new RegistrySnapshotResult
                {
                    RegistryPath = registryPath,
                    Success = false,
                    Error = ex.Message
                });
            }
        }

        return Task.FromResult<IReadOnlyList<RegistrySnapshotResult>>(results);
    }

    public Task<IReadOnlyList<RegistryRestoreResult>> RestoreAsync(IEnumerable<string> snapshotFiles, CancellationToken ct)
    {
        var results = new List<RegistryRestoreResult>();
        var files = snapshotFiles.Where(file => !string.IsNullOrWhiteSpace(file)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (files.Count == 0) return Task.FromResult<IReadOnlyList<RegistryRestoreResult>>(results);

        if (!OperatingSystem.IsWindows())
        {
            results.AddRange(files.Select(file => RegistryRestoreResult.Skipped(file, "Registry restore requires Windows.")));
            return Task.FromResult<IReadOnlyList<RegistryRestoreResult>>(results);
        }

        foreach (var file in files)
        {
            ct.ThrowIfCancellationRequested();

            try
            {
                var snapshot = _store.ReadSnapshot<RegistryKeySnapshot>(file);
                if (snapshot == null)
                {
                    results.Add(new RegistryRestoreResult { FileName = file, Success = false, Error = "snapshot_not_found_or_unreadable" });
                    continue;
                }

                if (!snapshot.KeyExists)
                {
                    var deleted = DeleteEphemeralTestKeyIfPresent(snapshot.RegistryPath);
                    results.Add(new RegistryRestoreResult
                    {
                        FileName = file,
                        RegistryPath = snapshot.RegistryPath,
                        Success = true,
                        Error = deleted ? "original_key_missing_deleted" : "original_key_missing_noop"
                    });
                    continue;
                }

                RestorePath(snapshot, ct);
                results.Add(new RegistryRestoreResult
                {
                    FileName = file,
                    RegistryPath = snapshot.RegistryPath,
                    Success = true,
                    RestoredValueCount = snapshot.ValueCount,
                    RestoredSubKeyCount = snapshot.SubKeyCount
                });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[SAFETY] Registry restore failed for snapshot {File}", file);
                results.Add(new RegistryRestoreResult
                {
                    FileName = file,
                    Success = false,
                    Error = ex.Message
                });
            }
        }

        return Task.FromResult<IReadOnlyList<RegistryRestoreResult>>(results);
    }

    private RegistryKeySnapshot CapturePath(string registryPath, CancellationToken ct)
    {
        var parsed = ParseRegistryPath(registryPath);
        using var baseKey = RegistryKey.OpenBaseKey(parsed.Hive, RegistryView.Registry64);
        using var key = baseKey.OpenSubKey(parsed.SubPath, RegistryKeyPermissionCheck.ReadSubTree, RegistryRights.ReadKey);

        var snapshot = new RegistryKeySnapshot
        {
            RegistryPath = registryPath,
            CapturedAtUtc = DateTime.UtcNow,
            KeyExists = key != null
        };

        if (key == null) return snapshot;

        int keyCount = 0;
        int valueCount = 0;
        CaptureKey(key, snapshot, depth: 0, ref keyCount, ref valueCount, ct);
        snapshot.SubKeyCount = keyCount;
        snapshot.ValueCount = valueCount;
        return snapshot;
    }

    private void CaptureKey(
        RegistryKey key,
        RegistryKeySnapshot snapshot,
        int depth,
        ref int keyCount,
        ref int valueCount,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        if (keyCount >= _maxKeys || valueCount >= _maxValues)
        {
            snapshot.Errors.Add("snapshot_limit_reached");
            return;
        }

        foreach (var valueName in SafeGetValueNames(key, snapshot))
        {
            if (valueCount >= _maxValues)
            {
                snapshot.Errors.Add("value_limit_reached");
                break;
            }

            try
            {
                var kind = key.GetValueKind(valueName);
                var value = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
                snapshot.Values.Add(RegistryValueSnapshot.From(valueName, kind, value));
                valueCount++;
            }
            catch (Exception ex)
            {
                snapshot.Errors.Add($"value:{valueName}:{ex.Message}");
            }
        }

        if (depth >= _maxDepth) return;

        foreach (var subKeyName in SafeGetSubKeyNames(key, snapshot))
        {
            if (keyCount >= _maxKeys)
            {
                snapshot.Errors.Add("subkey_limit_reached");
                break;
            }

            try
            {
                using var subKey = key.OpenSubKey(subKeyName, RegistryKeyPermissionCheck.ReadSubTree, RegistryRights.ReadKey);
                if (subKey == null) continue;

                var child = new RegistryKeySnapshot
                {
                    RegistryPath = subKeyName,
                    CapturedAtUtc = DateTime.UtcNow,
                    KeyExists = true
                };
                snapshot.SubKeys.Add(child);
                keyCount++;
                CaptureKey(subKey, child, depth + 1, ref keyCount, ref valueCount, ct);
            }
            catch (Exception ex)
            {
                snapshot.Errors.Add($"subkey:{subKeyName}:{ex.Message}");
            }
        }
    }

    private void RestorePath(RegistryKeySnapshot snapshot, CancellationToken ct)
    {
        var parsed = ParseRegistryPath(snapshot.RegistryPath);
        using var baseKey = RegistryKey.OpenBaseKey(parsed.Hive, RegistryView.Registry64);
        using var key = baseKey.CreateSubKey(parsed.SubPath, RegistryKeyPermissionCheck.ReadWriteSubTree);
        if (key == null) throw new InvalidOperationException($"Cannot open registry key for restore: {snapshot.RegistryPath}");
        RestoreKey(key, snapshot, ct);
    }

    private static void RestoreKey(RegistryKey key, RegistryKeySnapshot snapshot, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        foreach (var value in snapshot.Values)
        {
            key.SetValue(value.Name, value.ToRegistryObject(), value.ToRegistryValueKind());
        }

        foreach (var child in snapshot.SubKeys.Where(child => child.KeyExists))
        {
            using var childKey = key.CreateSubKey(child.RegistryPath, RegistryKeyPermissionCheck.ReadWriteSubTree);
            if (childKey != null) RestoreKey(childKey, child, ct);
        }
    }

    private static bool DeleteEphemeralTestKeyIfPresent(string registryPath)
    {
        if (!registryPath.Equals("HKLM\\SOFTWARE\\NeoOptimizeTest", StringComparison.OrdinalIgnoreCase) &&
            !registryPath.Equals("HKEY_LOCAL_MACHINE\\SOFTWARE\\NeoOptimizeTest", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            baseKey.DeleteSubKeyTree(@"SOFTWARE\NeoOptimizeTest", throwOnMissingSubKey: false);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static IEnumerable<string> SafeGetValueNames(RegistryKey key, RegistryKeySnapshot snapshot)
    {
        try { return key.GetValueNames(); }
        catch (Exception ex)
        {
            snapshot.Errors.Add($"value_names:{ex.Message}");
            return Array.Empty<string>();
        }
    }

    private static IEnumerable<string> SafeGetSubKeyNames(RegistryKey key, RegistryKeySnapshot snapshot)
    {
        try { return key.GetSubKeyNames(); }
        catch (Exception ex)
        {
            snapshot.Errors.Add($"subkey_names:{ex.Message}");
            return Array.Empty<string>();
        }
    }

    private static RegistryPathParts ParseRegistryPath(string registryPath)
    {
        var normalized = registryPath.Trim().Replace('/', '\\');
        var index = normalized.IndexOf('\\');
        var hiveText = index >= 0 ? normalized[..index] : normalized;
        var subPath = index >= 0 ? normalized[(index + 1)..] : "";

        var hive = hiveText.ToUpperInvariant() switch
        {
            "HKLM" or "HKEY_LOCAL_MACHINE" => RegistryHive.LocalMachine,
            "HKCU" or "HKEY_CURRENT_USER" => RegistryHive.CurrentUser,
            "HKCR" or "HKEY_CLASSES_ROOT" => RegistryHive.ClassesRoot,
            "HKU" or "HKEY_USERS" => RegistryHive.Users,
            "HKCC" or "HKEY_CURRENT_CONFIG" => RegistryHive.CurrentConfig,
            _ => throw new ArgumentException($"Unsupported registry hive: {hiveText}")
        };

        return new RegistryPathParts(hive, subPath);
    }

    private static int ReadInt(IConfiguration configuration, string key, int fallback)
    {
        var value = configuration[key] ?? configuration[$"Agent:{key}"];
        return int.TryParse(value, out var parsed) && parsed > 0 ? parsed : fallback;
    }

    private sealed record RegistryPathParts(RegistryHive Hive, string SubPath);
}

public sealed class RegistrySnapshotResult
{
    public string RegistryPath { get; set; } = "";
    public string? FileName { get; set; }
    public bool Success { get; set; }
    public string? Error { get; set; }
    public int ValueCount { get; set; }
    public int SubKeyCount { get; set; }

    public static RegistrySnapshotResult Skipped(string path, string reason)
    {
        return new RegistrySnapshotResult { RegistryPath = path, Success = false, Error = reason };
    }
}

public sealed class RegistryRestoreResult
{
    public string FileName { get; set; } = "";
    public string RegistryPath { get; set; } = "";
    public bool Success { get; set; }
    public string? Error { get; set; }
    public int RestoredValueCount { get; set; }
    public int RestoredSubKeyCount { get; set; }

    public static RegistryRestoreResult Skipped(string file, string reason)
    {
        return new RegistryRestoreResult { FileName = file, Success = false, Error = reason };
    }
}

public sealed class RegistryKeySnapshot
{
    public string RegistryPath { get; set; } = "";
    public DateTime CapturedAtUtc { get; set; } = DateTime.UtcNow;
    public bool KeyExists { get; set; }
    public List<RegistryValueSnapshot> Values { get; set; } = new();
    public List<RegistryKeySnapshot> SubKeys { get; set; } = new();
    public List<string> Errors { get; set; } = new();
    public int ValueCount { get; set; }
    public int SubKeyCount { get; set; }
}

public sealed class RegistryValueSnapshot
{
    public string Name { get; set; } = "";
    public string Kind { get; set; } = RegistryValueKind.String.ToString();
    public string? StringValue { get; set; }
    public long? NumberValue { get; set; }
    public string[]? StringArrayValue { get; set; }
    public string? BinaryBase64Value { get; set; }

    public static RegistryValueSnapshot From(string name, RegistryValueKind kind, object? value)
    {
        var snapshot = new RegistryValueSnapshot { Name = name, Kind = kind.ToString() };
        switch (kind)
        {
            case RegistryValueKind.Binary:
                snapshot.BinaryBase64Value = value is byte[] bytes ? Convert.ToBase64String(bytes) : "";
                break;
            case RegistryValueKind.MultiString:
                snapshot.StringArrayValue = value as string[] ?? Array.Empty<string>();
                break;
            case RegistryValueKind.DWord:
            case RegistryValueKind.QWord:
                snapshot.NumberValue = Convert.ToInt64(value ?? 0);
                break;
            default:
                snapshot.StringValue = Convert.ToString(value) ?? "";
                break;
        }
        return snapshot;
    }

    public object ToRegistryObject()
    {
        return ToRegistryValueKind() switch
        {
            RegistryValueKind.Binary => string.IsNullOrWhiteSpace(BinaryBase64Value)
                ? Array.Empty<byte>()
                : Convert.FromBase64String(BinaryBase64Value),
            RegistryValueKind.MultiString => StringArrayValue ?? Array.Empty<string>(),
            RegistryValueKind.DWord => Convert.ToInt32(NumberValue ?? 0),
            RegistryValueKind.QWord => NumberValue ?? 0L,
            _ => StringValue ?? ""
        };
    }

    public RegistryValueKind ToRegistryValueKind()
    {
        return Enum.TryParse<RegistryValueKind>(Kind, ignoreCase: true, out var kind)
            ? kind
            : RegistryValueKind.String;
    }
}
