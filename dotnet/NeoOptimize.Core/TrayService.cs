using System;
using System.Threading;
using System.Threading.Tasks;

namespace NeoOptimize.Core
{
    public enum SensitivityLevel { Low, Medium, High }

    public class TraySettings
    {
        public bool AutoHide { get; set; } = true;
        public SensitivityLevel Sensitivity { get; set; } = SensitivityLevel.Medium;
        public int CheckIntervalSeconds { get; set; } = 10;
    }

    public class TrayService : IDisposable
    {
        private readonly TraySettings _settings;
        private Timer _timer;

        public event Action<string> OnActionExecuted; // log-friendly

        public TrayService(TraySettings settings = null)
        {
            _settings = settings ?? new TraySettings();
        }

        public void Start()
        {
            _timer = new Timer(async _ => await CheckAsync(), null, 5000, _settings.CheckIntervalSeconds * 1000);
            OnActionExecuted?.Invoke("Mini Tray started, initial scan scheduled");
        }

        private async Task CheckAsync()
        {
            try
            {
                // sample checks - replace with WMI/PerformanceCounter integration
                var cpu = GetCpuUsageSample();
                var ram = GetRamUsageSample();

                if (cpu > 80 && _settings.Sensitivity != SensitivityLevel.Low)
                {
                    // trigger RAM release
                    OnActionExecuted?.Invoke($"Mini Tray: CPU overload detected ({cpu}%), triggering RAM release");
                    // call optimizer engine here
                }

                if (ram > 85 && _settings.Sensitivity == SensitivityLevel.High)
                {
                    OnActionExecuted?.Invoke($"Mini Tray: RAM overload detected ({ram}%), triggering cache flush");
                }
            }
            catch { }
            await Task.CompletedTask;
        }

        private int GetCpuUsageSample()
        {
            // placeholder: integrate proper perf counters
            return new Random().Next(10, 90);
        }

        private int GetRamUsageSample()
        {
            return new Random().Next(20, 95);
        }

        public void Stop()
        {
            _timer?.Dispose();
            _timer = null;
            OnActionExecuted?.Invoke("Mini Tray stopped");
        }

        public void Dispose()
        {
            Stop();
        }
    }
}
using System.Collections.Generic;
using NeoOptimize.Core.Models;

namespace NeoOptimize.Core;

public sealed class TrayService
{
    public IReadOnlyList<string> EvaluateThresholds(SystemSnapshot snapshot)
    {
        var actions = new List<string>();

        if (snapshot.CpuUsagePercent > 80) actions.Add("CPU > 80%, advise RAM release.");
        if (snapshot.MemoryUsagePercent > 85) actions.Add("RAM > 85%, advise cache flush.");
        if (snapshot.DiskUsagePercent > 90) actions.Add("Disk pressure high, advise cleanup.");
        if (snapshot.NetworkUsageMbps > 150) actions.Add("Network pressure high, advise DNS refresh.");

        return actions;
    }
}
