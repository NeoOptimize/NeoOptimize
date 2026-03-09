using System.Diagnostics;
using System.Runtime.InteropServices;
using NeoOptimize.Contracts;

namespace NeoOptimize.Infrastructure;

public sealed class SystemSnapshotProvider
{
    public TelemetryPayload CollectTelemetry()
    {
        var processes = Process.GetProcesses();
        var processList = processes
            .OrderByDescending(process => SafeGetWorkingSet(process))
            .Take(5)
            .Select(process => new Dictionary<string, object?>
            {
                ["name"] = process.ProcessName,
                ["pid"] = process.Id,
                ["working_set_mb"] = Math.Round(SafeGetWorkingSet(process) / 1024d / 1024d, 2),
            })
            .ToList();

        var drive = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory)!);
        var memory = GetMemoryStatus();
        double? ramPercent = memory.TotalPhysicalMemoryBytes == 0
            ? null
            : Math.Round((1 - (double)memory.AvailablePhysicalMemoryBytes / memory.TotalPhysicalMemoryBytes) * 100, 2);
        double? diskPercent = drive.TotalSize == 0
            ? null
            : Math.Round((1 - (double)drive.AvailableFreeSpace / drive.TotalSize) * 100, 2);

        return new TelemetryPayload
        {
            CpuPercent = null,
            RamPercent = ramPercent,
            GpuPercent = null,
            DiskUsagePercent = diskPercent,
            DiskReadMbps = null,
            DiskWriteMbps = null,
            TemperatureCelsius = null,
            ProcessCount = processes.Length,
            TopProcesses = processList,
            Snapshot = new Dictionary<string, object?>
            {
                ["machine_name"] = Environment.MachineName,
                ["os"] = RuntimeInformation.OSDescription,
                ["drive_name"] = drive.Name,
                ["timestamp_utc"] = DateTimeOffset.UtcNow,
            },
        };
    }

    public SystemHealthPayload CollectHealth(string integrityStatus = "pending")
    {
        var telemetry = CollectTelemetry();
        var recommendations = new List<string>();
        var issues = new List<Dictionary<string, object?>>();
        var healthState = "healthy";
        var score = 100;

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

        return new SystemHealthPayload
        {
            OverallScore = Math.Max(score, 0),
            HealthState = healthState,
            SfcStatus = "not_run",
            DismStatus = "not_run",
            ThermalStatus = "unknown",
            IntegrityStatus = integrityStatus,
            Issues = issues,
            Recommendations = recommendations,
            Report = new Dictionary<string, object?>
            {
                ["generated_at_utc"] = DateTimeOffset.UtcNow,
                ["machine_name"] = Environment.MachineName,
                ["os"] = RuntimeInformation.OSDescription,
            },
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
