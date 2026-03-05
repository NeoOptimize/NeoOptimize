using System;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.UI.Services
{
    public class SystemMetricsSnapshot
    {
        public double CpuUsagePercent { get; set; }
        public double RamUsagePercent { get; set; }
        public double DiskUsagePercent { get; set; }
        public double LatencyMs { get; set; }
        public DateTimeOffset CapturedAt { get; set; }
    }

    public class SystemMetricsService : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileTime
        {
            public uint DwLowDateTime;
            public uint DwHighDateTime;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private struct MemoryStatusEx
        {
            public uint DwLength;
            public uint DwMemoryLoad;
            public ulong UllTotalPhys;
            public ulong UllAvailPhys;
            public ulong UllTotalPageFile;
            public ulong UllAvailPageFile;
            public ulong UllTotalVirtual;
            public ulong UllAvailVirtual;
            public ulong UllAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FileTime lpIdleTime, out FileTime lpKernelTime, out FileTime lpUserTime);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);

        private readonly object _cpuLock = new object();
        private bool _cpuInitialized;
        private ulong _prevIdle;
        private ulong _prevKernel;
        private ulong _prevUser;

        public async Task<SystemMetricsSnapshot> CaptureAsync(CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();

            var snapshot = new SystemMetricsSnapshot
            {
                CpuUsagePercent = GetCpuUsagePercent(),
                RamUsagePercent = GetRamUsagePercent(),
                DiskUsagePercent = GetDiskUsagePercent(),
                LatencyMs = await MeasureLatencyAsync().ConfigureAwait(false),
                CapturedAt = DateTimeOffset.Now
            };

            return snapshot;
        }

        private static ulong ToUInt64(FileTime fileTime)
        {
            return ((ulong)fileTime.DwHighDateTime << 32) | fileTime.DwLowDateTime;
        }

        private double GetCpuUsagePercent()
        {
            if (!GetSystemTimes(out var idleTime, out var kernelTime, out var userTime))
            {
                return 0;
            }

            ulong idle = ToUInt64(idleTime);
            ulong kernel = ToUInt64(kernelTime);
            ulong user = ToUInt64(userTime);

            lock (_cpuLock)
            {
                if (!_cpuInitialized)
                {
                    _prevIdle = idle;
                    _prevKernel = kernel;
                    _prevUser = user;
                    _cpuInitialized = true;
                    return 0;
                }

                ulong idleDelta = idle - _prevIdle;
                ulong kernelDelta = kernel - _prevKernel;
                ulong userDelta = user - _prevUser;
                ulong totalDelta = kernelDelta + userDelta;

                _prevIdle = idle;
                _prevKernel = kernel;
                _prevUser = user;

                if (totalDelta == 0)
                {
                    return 0;
                }

                double usage = (double)(totalDelta - idleDelta) * 100.0 / totalDelta;
                if (usage < 0) usage = 0;
                if (usage > 100) usage = 100;
                return usage;
            }
        }

        private static double GetRamUsagePercent()
        {
            var memoryStatus = new MemoryStatusEx
            {
                DwLength = (uint)Marshal.SizeOf<MemoryStatusEx>()
            };

            if (!GlobalMemoryStatusEx(ref memoryStatus))
            {
                return 0;
            }

            return memoryStatus.DwMemoryLoad;
        }

        private static double GetDiskUsagePercent()
        {
            try
            {
                var drives = DriveInfo
                    .GetDrives()
                    .Where(d => d.IsReady && d.DriveType == DriveType.Fixed)
                    .ToList();

                if (drives.Count == 0)
                {
                    return 0;
                }

                var driveC = drives.FirstOrDefault(d => d.Name.StartsWith("C", StringComparison.OrdinalIgnoreCase));
                var target = driveC ?? drives[0];
                if (target.TotalSize <= 0)
                {
                    return 0;
                }

                double used = target.TotalSize - target.TotalFreeSpace;
                return used * 100.0 / target.TotalSize;
            }
            catch
            {
                return 0;
            }
        }

        private static async Task<double> MeasureLatencyAsync()
        {
            try
            {
                using var ping = new Ping();
                var reply = await ping.SendPingAsync("8.8.8.8", 700).ConfigureAwait(false);
                if (reply.Status == IPStatus.Success)
                {
                    return reply.RoundtripTime;
                }
            }
            catch
            {
            }

            return 0;
        }

        public void Dispose()
        {
        }
    }
}
