using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace NeoOptimize.Infrastructure;

public sealed class HardwareFingerprintService
{
    public string BuildFingerprint()
    {
        var macAddresses = NetworkInterface.GetAllNetworkInterfaces()
            .Where(nic => nic.OperationalStatus == OperationalStatus.Up)
            .Select(nic => nic.GetPhysicalAddress().ToString())
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .OrderBy(value => value)
            .ToArray();

        var raw = string.Join("|", new[]
        {
            Environment.MachineName,
            RuntimeInformation.OSDescription,
            RuntimeInformation.OSArchitecture.ToString(),
            RuntimeInformation.ProcessArchitecture.ToString(),
            Environment.ProcessorCount.ToString(),
            string.Join(",", macAddresses),
        });

        using var sha = SHA256.Create();
        var bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
