using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace NeoOptimize.Agent.Safety;

public sealed class AgentSecureStore
{
    private const string StateFile = "state.json";
    private const string CrashCounterFile = "crash_counter.dat";
    private readonly ILogger<AgentSecureStore> _logger;

    public string RootPath { get; }
    public string SnapshotsPath => Path.Combine(RootPath, "snapshots");

    public AgentSecureStore(IConfiguration configuration, ILogger<AgentSecureStore> logger)
    {
        _logger = logger;
        RootPath = ResolveRootPath(configuration);
        EnsureReady();
    }

    public void EnsureReady()
    {
        Directory.CreateDirectory(RootPath);
        Directory.CreateDirectory(SnapshotsPath);
        ApplyAcl(RootPath);
        ApplyAcl(SnapshotsPath);
    }

    public SafetyExecutionState? ReadState()
    {
        return ReadProtectedJson<SafetyExecutionState>(StateFile);
    }

    public void WriteState(SafetyExecutionState state)
    {
        state.UpdatedAtUtc = DateTime.UtcNow;
        WriteProtectedJson(StateFile, state);
    }

    public int IncrementCrashCounter()
    {
        var counter = ReadProtectedJson<CrashCounter>(CrashCounterFile) ?? new CrashCounter();
        counter.Count++;
        counter.UpdatedAtUtc = DateTime.UtcNow;
        WriteProtectedJson(CrashCounterFile, counter);
        return counter.Count;
    }

    public void ResetCrashCounter()
    {
        WriteProtectedJson(CrashCounterFile, new CrashCounter());
    }

    public void WriteSnapshot<T>(string fileName, T value)
    {
        WriteProtectedJson(Path.Combine("snapshots", fileName), value);
    }

    public T? ReadSnapshot<T>(string fileName)
    {
        return ReadProtectedJson<T>(Path.Combine("snapshots", fileName));
    }

    public string GetSnapshotFileName(string commandId, string registryPath)
    {
        var safeCommandId = Sanitize(commandId);
        var pathHash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(registryPath))).ToLowerInvariant()[..16];
        return $"snap_{safeCommandId}_{pathHash}.bak";
    }

    private T? ReadProtectedJson<T>(string relativePath)
    {
        var path = Path.Combine(RootPath, relativePath);
        if (!File.Exists(path)) return default;

        try
        {
            var protectedBytes = File.ReadAllBytes(path);
            var bytes = Unprotect(protectedBytes);
            return JsonSerializer.Deserialize<T>(bytes, JsonOptions.Default);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[SAFETY] Failed to read protected store file {File}", relativePath);
            return default;
        }
    }

    private void WriteProtectedJson<T>(string relativePath, T value)
    {
        EnsureReady();
        var path = Path.Combine(RootPath, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path) ?? RootPath);

        var bytes = JsonSerializer.SerializeToUtf8Bytes(value, JsonOptions.Default);
        var protectedBytes = Protect(bytes);
        File.WriteAllBytes(path, protectedBytes);
    }

    private static byte[] Protect(byte[] bytes)
    {
        if (!OperatingSystem.IsWindows()) return bytes;
        return ProtectedData.Protect(bytes, optionalEntropy: null, DataProtectionScope.LocalMachine);
    }

    private static byte[] Unprotect(byte[] bytes)
    {
        if (!OperatingSystem.IsWindows()) return bytes;
        return ProtectedData.Unprotect(bytes, optionalEntropy: null, DataProtectionScope.LocalMachine);
    }

    private void ApplyAcl(string path)
    {
        if (!OperatingSystem.IsWindows()) return;

        try
        {
            var info = new DirectoryInfo(path);
            var security = new DirectorySecurity();
            security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);

            var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            var adminsSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);

            security.AddAccessRule(new FileSystemAccessRule(
                systemSid,
                FileSystemRights.FullControl,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow));

            security.AddAccessRule(new FileSystemAccessRule(
                adminsSid,
                FileSystemRights.ReadAndExecute | FileSystemRights.ListDirectory,
                InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
                PropagationFlags.None,
                AccessControlType.Allow));

            info.SetAccessControl(security);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[SAFETY] Failed to apply SecureStore ACL for {Path}", path);
        }
    }

    private static string ResolveRootPath(IConfiguration configuration)
    {
        var configured = configuration["Safety:SecureStorePath"] ?? configuration["Agent:Safety:SecureStorePath"];
        if (!string.IsNullOrWhiteSpace(configured)) return Environment.ExpandEnvironmentVariables(configured);

        var programData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        if (string.IsNullOrWhiteSpace(programData)) programData = AppContext.BaseDirectory;
        return Path.Combine(programData, "NeoOptimize", "SecureStore");
    }

    private static string Sanitize(string value)
    {
        var safe = new string(value.Select(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' ? ch : '_').ToArray());
        return string.IsNullOrWhiteSpace(safe) ? Guid.NewGuid().ToString("N") : safe;
    }

    private sealed class CrashCounter
    {
        public int Count { get; set; }
        public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    }
}

public sealed class SafetyExecutionState
{
    public string CommandId { get; set; } = "";
    public string CommandType { get; set; } = "";
    public string ManifestSha256 { get; set; } = "";
    public string Status { get; set; } = "IDLE";
    public string RiskLevel { get; set; } = "UNKNOWN";
    public DateTime StartedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime UpdatedAtUtc { get; set; } = DateTime.UtcNow;
    public List<string> SnapshotFiles { get; set; } = new();
    public HealthSnapshot? Baseline { get; set; }
    public Dictionary<string, object> Metadata { get; set; } = new();
}
