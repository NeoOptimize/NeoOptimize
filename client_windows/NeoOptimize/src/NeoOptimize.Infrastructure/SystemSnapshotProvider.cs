using System.Diagnostics;
using System.Globalization;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using NeoOptimize.Contracts;

namespace NeoOptimize.Infrastructure;

public sealed partial class SystemSnapshotProvider
{
    private long _lastNetworkBytes;
    private DateTimeOffset _lastNetworkSample = DateTimeOffset.MinValue;
    private readonly object _networkLock = new();

    private static readonly Regex GpuEngineKeyPattern = new(@"phys_(?<physical>\d+)_eng_(?<engine>\d+)_engtype_(?<type>[^_]+)", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    public TelemetryPayload CollectTelemetry()
    {
        using var processSnapshot = ProcessSnapshot.Create();
        var processes = processSnapshot.Processes;
        var processList = processes
            .OrderByDescending(process => SafeGetWorkingSet(process))
            .Take(6)
            .Select(process => new Dictionary<string, object?>
            {
                ["name"] = process.ProcessName,
                ["pid"] = process.Id,
                ["working_set_mb"] = Math.Round(SafeGetWorkingSet(process) / 1024d / 1024d, 2),
            })
            .ToList();

        var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)!);
        var memory = GetMemoryStatus();
        var cpuPercent = QueryCpuPercent();
        var gpuPercent = QueryGpuPercent();
        var diskCounters = QueryDiskThroughput(drive.Name.TrimEnd('\\').ToUpperInvariant());
        var temperatureCelsius = QueryTemperatureCelsius();
        var networkMbps = QueryNetworkMbps();
        double? ramPercent = memory.TotalPhysicalMemoryBytes == 0
            ? null
            : Math.Round((1 - (double)memory.AvailablePhysicalMemoryBytes / memory.TotalPhysicalMemoryBytes) * 100, 2);
        double? diskPercent = drive.TotalSize == 0
            ? null
            : Math.Round((1 - (double)drive.AvailableFreeSpace / drive.TotalSize) * 100, 2);

        return new TelemetryPayload
        {
            CpuPercent = cpuPercent,
            RamPercent = ramPercent,
            GpuPercent = gpuPercent,
            DiskUsagePercent = diskPercent,
            DiskReadMbps = diskCounters.ReadMbps,
            DiskWriteMbps = diskCounters.WriteMbps,
            NetworkMbps = networkMbps,
            TemperatureCelsius = temperatureCelsius,
            ProcessCount = processes.Count,
            TopProcesses = processList,
            Snapshot = new Dictionary<string, object?>
            {
                ["machine_name"] = Environment.MachineName,
                ["os"] = RuntimeInformation.OSDescription,
                ["drive_name"] = drive.Name,
                ["drive_total_gb"] = Math.Round(drive.TotalSize / 1024d / 1024d / 1024d, 2),
                ["drive_free_gb"] = Math.Round(drive.AvailableFreeSpace / 1024d / 1024d / 1024d, 2),
                ["timestamp_utc"] = DateTimeOffset.UtcNow,
                ["network_mbps"] = networkMbps,
            },
        };
    }

    public SystemHealthPayload CollectHealth(
        string integrityStatus = "pending",
        string? sfcStatus = null,
        string? dismStatus = null,
        string? thermalStatus = null)
    {
        var telemetry = CollectTelemetry();
        var recommendations = new List<string>();
        var issues = new List<Dictionary<string, object?>>();
        var healthState = "healthy";
        var score = 100;
        var derivedThermalStatus = thermalStatus ?? DeriveThermalStatus(telemetry.TemperatureCelsius);
        var normalizedSfcStatus = string.IsNullOrWhiteSpace(sfcStatus) ? "not_run" : sfcStatus;
        var normalizedDismStatus = string.IsNullOrWhiteSpace(dismStatus) ? "not_run" : dismStatus;

        if (telemetry.CpuPercent is > 85)
        {
            healthState = "warning";
            score -= 12;
            recommendations.Add("CPU tinggi. Audit proses latar belakang dan pertimbangkan Smart Booster.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "cpu", ["value"] = telemetry.CpuPercent });
        }

        if (telemetry.RamPercent is > 90)
        {
            healthState = "warning";
            score -= 15;
            recommendations.Add("Kurangi aplikasi latar belakang dengan konsumsi RAM tinggi.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "ram", ["value"] = telemetry.RamPercent });
        }

        if (telemetry.DiskUsagePercent is > 90)
        {
            healthState = "warning";
            score -= 10;
            recommendations.Add("Bersihkan storage sistem dan temp files.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "disk", ["value"] = telemetry.DiskUsagePercent });
        }

        if (telemetry.TemperatureCelsius is > 82)
        {
            healthState = "warning";
            score -= 12;
            recommendations.Add("Temperatur tinggi. Periksa pendingin dan kurangi beban proses berat.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "thermal", ["value"] = telemetry.TemperatureCelsius });
        }

        if (normalizedSfcStatus is "requires_admin" or "corruption_detected")
        {
            healthState = "warning";
            score -= 8;
            recommendations.Add(normalizedSfcStatus == "requires_admin"
                ? "SFC membutuhkan hak administrator. Jalankan lewat service atau terminal elevated."
                : "SFC mendeteksi masalah integritas file sistem. Jalankan perbaikan lanjutan.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "sfc", ["value"] = normalizedSfcStatus });
        }

        if (normalizedDismStatus is "requires_admin" or "repairable" or "not_repairable")
        {
            healthState = "warning";
            score -= normalizedDismStatus == "requires_admin" ? 4 : 10;
            recommendations.Add(normalizedDismStatus switch
            {
                "requires_admin" => "DISM membutuhkan hak administrator untuk verifikasi komponen OS.",
                "repairable" => "DISM menandai component store dapat diperbaiki. Jadwalkan repair image.",
                "not_repairable" => "DISM menandai component store tidak dapat diperbaiki. Evaluasi restore source atau reinstall.",
                _ => "Evaluasi status DISM terbaru.",
            });
            issues.Add(new Dictionary<string, object?> { ["type"] = "dism", ["value"] = normalizedDismStatus });
        }

        if (string.Equals(integrityStatus, "tampered", StringComparison.OrdinalIgnoreCase))
        {
            healthState = "warning";
            score -= 14;
            recommendations.Add("Integrity scan mendeteksi perubahan file. Bandingkan hash dengan release resmi.");
            issues.Add(new Dictionary<string, object?> { ["type"] = "integrity", ["value"] = integrityStatus });
        }

        if (score < 70)
        {
            healthState = "degraded";
        }

        return new SystemHealthPayload
        {
            OverallScore = Math.Max(score, 0),
            HealthState = healthState,
            SfcStatus = normalizedSfcStatus,
            DismStatus = normalizedDismStatus,
            ThermalStatus = derivedThermalStatus,
            IntegrityStatus = integrityStatus,
            Issues = issues,
            Recommendations = recommendations,
            Report = new Dictionary<string, object?>
            {
                ["generated_at_utc"] = DateTimeOffset.UtcNow,
                ["machine_name"] = Environment.MachineName,
                ["os"] = RuntimeInformation.OSDescription,
                ["cpu_percent"] = telemetry.CpuPercent,
                ["ram_percent"] = telemetry.RamPercent,
                ["gpu_percent"] = telemetry.GpuPercent,
                ["disk_usage_percent"] = telemetry.DiskUsagePercent,
                ["disk_read_mbps"] = telemetry.DiskReadMbps,
                ["disk_write_mbps"] = telemetry.DiskWriteMbps,
                ["temperature_celsius"] = telemetry.TemperatureCelsius,
            },
        };
    }

    private static double? QueryCpuPercent()
    {
        return QuerySingleDouble(
            @"root\cimv2",
            "SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE Name = '_Total'",
            "PercentProcessorTime");
    }

    private static (double? ReadMbps, double? WriteMbps) QueryDiskThroughput(string driveLetter)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\cimv2",
                "SELECT Name, DiskReadBytesPerSec, DiskWriteBytesPerSec FROM Win32_PerfFormattedData_PerfDisk_PhysicalDisk");
            foreach (ManagementObject item in searcher.Get())
            {
                var name = Convert.ToString(item["Name"], CultureInfo.InvariantCulture) ?? string.Empty;
                if (!name.Contains(driveLetter, StringComparison.OrdinalIgnoreCase) && !string.Equals(name, "_Total", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var readBytes = ReadDouble(item, "DiskReadBytesPerSec") ?? 0;
                var writeBytes = ReadDouble(item, "DiskWriteBytesPerSec") ?? 0;
                return (Math.Round(readBytes / 1024d / 1024d, 2), Math.Round(writeBytes / 1024d / 1024d, 2));
            }
        }
        catch
        {
            // WMI disk counters are best effort only.
        }

        return (null, null);
    }

    private static double? QueryGpuPercent()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\cimv2",
                "SELECT Name, UtilizationPercentage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine");
            var enginePeaks = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);

            foreach (ManagementObject item in searcher.Get())
            {
                var name = Convert.ToString(item["Name"], CultureInfo.InvariantCulture) ?? string.Empty;
                var match = GpuEngineKeyPattern.Match(name);
                if (!match.Success)
                {
                    continue;
                }

                var engineKey = $"phys_{match.Groups["physical"].Value}_eng_{match.Groups["engine"].Value}_type_{match.Groups["type"].Value}";
                var value = ReadDouble(item, "UtilizationPercentage") ?? 0;
                if (!enginePeaks.TryGetValue(engineKey, out var current) || value > current)
                {
                    enginePeaks[engineKey] = value;
                }
            }

            if (enginePeaks.Count == 0)
            {
                return null;
            }

            return Math.Round(Math.Min(enginePeaks.Values.Sum(), 100d), 2);
        }
        catch
        {
            return null;
        }
    }

    private static double? QueryTemperatureCelsius()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\wmi",
                "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            foreach (ManagementObject item in searcher.Get())
            {
                var raw = ReadDouble(item, "CurrentTemperature");
                if (raw is null or <= 0)
                {
                    continue;
                }

                return Math.Round((raw.Value / 10d) - 273.15d, 2);
            }
        }
        catch
        {
            // Thermal telemetry is optional and unsupported on many machines.
        }

        return null;
    }

    private double? QueryNetworkMbps()
    {
        try
        {
            var now = DateTimeOffset.UtcNow;
            long totalBytes = 0;
            foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (adapter.OperationalStatus != OperationalStatus.Up)
                {
                    continue;
                }

                if (adapter.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
                {
                    continue;
                }

                var stats = adapter.GetIPv4Statistics();
                totalBytes += stats.BytesReceived + stats.BytesSent;
            }

            lock (_networkLock)
            {
                if (_lastNetworkSample == DateTimeOffset.MinValue)
                {
                    _lastNetworkSample = now;
                    _lastNetworkBytes = totalBytes;
                    return null;
                }

                var seconds = (now - _lastNetworkSample).TotalSeconds;
                if (seconds <= 0.1)
                {
                    return null;
                }

                var deltaBytes = totalBytes - _lastNetworkBytes;
                _lastNetworkSample = now;
                _lastNetworkBytes = totalBytes;

                var mbps = (deltaBytes * 8d) / (seconds * 1024d * 1024d);
                return Math.Round(Math.Max(0, mbps), 2);
            }
        }
        catch
        {
            return null;
        }
    }

    private static string DeriveThermalStatus(double? temperatureCelsius)
    {
        if (temperatureCelsius is null)
        {
            return "unknown";
        }

        if (temperatureCelsius >= 85)
        {
            return "critical";
        }

        if (temperatureCelsius >= 75)
        {
            return "warning";
        }

        return "normal";
    }

    private static double? QuerySingleDouble(string scopePath, string queryText, string propertyName)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(scopePath, queryText);
            foreach (ManagementObject item in searcher.Get())
            {
                return ReadDouble(item, propertyName);
            }
        }
        catch
        {
            return null;
        }

        return null;
    }

    private static double? ReadDouble(ManagementBaseObject source, string propertyName)
    {
        var value = source[propertyName];
        if (value is null)
        {
            return null;
        }

        return value switch
        {
            byte byteValue => byteValue,
            short shortValue => shortValue,
            ushort ushortValue => ushortValue,
            int intValue => intValue,
            uint uintValue => uintValue,
            long longValue => longValue,
            ulong ulongValue => ulongValue,
            float floatValue => floatValue,
            double doubleValue => doubleValue,
            decimal decimalValue => (double)decimalValue,
            string stringValue when double.TryParse(stringValue, NumberStyles.Any, CultureInfo.InvariantCulture, out var parsed) => parsed,
            _ => null,
        };
    }

    private static long SafeGetWorkingSet(Process process)
    {
        try
        {
            return process.WorkingSet64;
        }
        catch
        {
            return 0;
        }
    }

    private static MemoryStatusSnapshot GetMemoryStatus()
    {
        var memoryStatus = new MEMORYSTATUSEX();
        memoryStatus.dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>();

        if (!GlobalMemoryStatusEx(ref memoryStatus))
        {
            return new MemoryStatusSnapshot(0, 0);
        }

        return new MemoryStatusSnapshot(memoryStatus.ullTotalPhys, memoryStatus.ullAvailPhys);
    }

    private sealed record MemoryStatusSnapshot(ulong TotalPhysicalMemoryBytes, ulong AvailablePhysicalMemoryBytes);

    private sealed class ProcessSnapshot : IDisposable
    {
        private ProcessSnapshot(IReadOnlyList<Process> processes)
        {
            Processes = processes;
        }

        public IReadOnlyList<Process> Processes { get; }

        public static ProcessSnapshot Create()
        {
            return new ProcessSnapshot(Process.GetProcesses());
        }

        public void Dispose()
        {
            foreach (var process in Processes)
            {
                process.Dispose();
            }
        }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);
}
