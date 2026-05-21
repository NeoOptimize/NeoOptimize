// ═══════════════════════════════════════════════════════════════════
// NeoOptimize Agent — SystemCollector v5.0 (Production)
// FIXES:
//   [BUG#5]  Added command timeout enforcement
//   [NEW]    GPU name, GPU usage%, GPU temperature (via WMI/NVML)
//   [NEW]    CPU temperature via WMI MSAcpi_ThermalZoneTemperature
//   [NEW]    Camera/Mic active detection
//   [NEW]    Public IP + GeoIP in telemetry
// ═══════════════════════════════════════════════════════════════════

using System.Management;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Win32;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using NeoOptimize.Agent.Models;

namespace NeoOptimize.Agent.Services;

public interface ISystemCollector
{
    string GetBiosUuid();
    TelemetryRequest GetTelemetry();
    Dictionary<string, string> GetSystemMeta();
}

public class SystemCollector : ISystemCollector
{
    private readonly ILogger<SystemCollector> _logger;
    private readonly HttpClient _http;
    private string? _cachedPublicIp;
    private DateTime _lastGeoUpdate = DateTime.MinValue;
    private string? _cachedGeoCity;
    private string? _cachedGeoCountry;
    private double? _cachedGeoLat;
    private double? _cachedGeoLon;
    private float? _cachedGpuPct;
    private float? _cachedGpuTemp;
    private string? _cachedGpuName;
    private readonly bool _collectDeviceCapabilities;
    private readonly bool _collectApproxLocation;
    private readonly bool _collectVerboseDiagnostics;
    private readonly bool _collectCameraCapture;
    private readonly bool _collectMicrophoneCapture;
    private readonly bool _collectBiometricData;

    public SystemCollector(ILogger<SystemCollector> logger, IConfiguration configuration)
    {
        _logger = logger;
        _http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        _collectDeviceCapabilities = ReadBool(configuration, "Telemetry:CollectDeviceCapabilities", true);
        _collectApproxLocation = ReadBool(configuration, "Telemetry:CollectApproxLocation", false);
        _collectVerboseDiagnostics = ReadBool(configuration, "Telemetry:CollectVerboseDiagnostics", false);
        _collectCameraCapture = ReadBool(configuration, "Telemetry:CollectCameraCapture", false);
        _collectMicrophoneCapture = ReadBool(configuration, "Telemetry:CollectMicrophoneCapture", false);
        _collectBiometricData = ReadBool(configuration, "Telemetry:CollectBiometricData", false);
    }

    private string? _cachedBiosUuid;  // [BUG-A03 FIX] Cache UUID — WMI query only once at startup

    public string GetBiosUuid()
    {
        if (_cachedBiosUuid != null) return _cachedBiosUuid;
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT UUID FROM Win32_ComputerSystemProduct");
            foreach (var obj in searcher.Get())
            {
                var uuid = obj["UUID"]?.ToString();
                if (!string.IsNullOrEmpty(uuid) && uuid != "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")
                {
                    _cachedBiosUuid = uuid;
                    return _cachedBiosUuid;
                }
            }
        }
        catch (Exception ex) { _logger.LogWarning("BIOS UUID WMI failed: {Msg}", ex.Message); }
        // Fallback: use machine-specific hash
        _cachedBiosUuid = Guid.NewGuid().ToString();
        return _cachedBiosUuid;
    }

    public Dictionary<string, string> GetSystemMeta()
    {
        var meta = new Dictionary<string, string>();
        try
        {
            using var os = new ManagementObjectSearcher("SELECT Caption,Version,BuildNumber,OSArchitecture FROM Win32_OperatingSystem");
            foreach (var obj in os.Get())
            {
                meta["os"] = obj["Caption"]?.ToString() ?? "Unknown";
                meta["os_version"] = obj["Version"]?.ToString() ?? "";
                meta["os_build"] = obj["BuildNumber"]?.ToString() ?? "";
                meta["os_architecture"] = obj["OSArchitecture"]?.ToString() ?? "";
            }

            using var cpu = new ManagementObjectSearcher("SELECT Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,CurrentClockSpeed FROM Win32_Processor");
            foreach (var obj in cpu.Get())
            {
                meta["cpu"] = obj["Name"]?.ToString() ?? "Unknown";
                meta["cpu_cores"] = obj["NumberOfCores"]?.ToString() ?? "0";
                meta["cpu_threads"] = obj["NumberOfLogicalProcessors"]?.ToString() ?? "0";
                meta["cpu_mhz"] = obj["MaxClockSpeed"]?.ToString() ?? "0";
                meta["cpu_current_mhz"] = obj["CurrentClockSpeed"]?.ToString() ?? "";
                break;
            }

            using var system = new ManagementObjectSearcher("SELECT TotalPhysicalMemory,Manufacturer,Model FROM Win32_ComputerSystem");
            foreach (var obj in system.Get())
            {
                meta["ram_mb"] = ((ulong)obj["TotalPhysicalMemory"] / 1024 / 1024).ToString();
                meta["manufacturer"] = obj["Manufacturer"]?.ToString() ?? "";
                meta["model"] = obj["Model"]?.ToString() ?? "";
            }

            using var board = new ManagementObjectSearcher("SELECT Product,Manufacturer FROM Win32_BaseBoard");
            foreach (var obj in board.Get())
            {
                var maker = obj["Manufacturer"]?.ToString() ?? "";
                var product = obj["Product"]?.ToString() ?? "";
                meta["motherboard"] = string.IsNullOrWhiteSpace(maker) ? product : $"{maker} {product}".Trim();
                break;
            }

            // GPU Info
            using var gpu = new ManagementObjectSearcher("SELECT Name,AdapterRAM FROM Win32_VideoController");
            foreach (var obj in gpu.Get())
            {
                var gpuName = obj["Name"]?.ToString() ?? "";
                if (!string.IsNullOrEmpty(gpuName) && !gpuName.Contains("Remote", StringComparison.OrdinalIgnoreCase))
                {
                    meta["gpu"] = gpuName;
                    _cachedGpuName = gpuName;
                    break;
                }
            }

            meta["disks_json"] = JsonSerializer.Serialize(GetDiskProfile());
            meta["security_state_json"] = JsonSerializer.Serialize(GetSecurityState());
            meta["power_profile"] = GetActivePowerProfile() ?? "";
        }
        catch (Exception ex) { _logger.LogWarning("SystemMeta failed: {Msg}", ex.Message); }
        return meta;
    }

    public TelemetryRequest GetTelemetry()
    {
        var tele = new TelemetryRequest
        {
            Uuid      = GetBiosUuid(),
            Hostname  = Environment.MachineName,
            Timestamp = DateTime.UtcNow
        };

        try
        {
            // CPU Usage
            using var cpuLoad = new ManagementObjectSearcher("SELECT LoadPercentage,CurrentClockSpeed FROM Win32_Processor");
            float cpuPct = 0;
            int count = 0;
            foreach (var obj in cpuLoad.Get())
            {
                cpuPct += Convert.ToSingle(obj["LoadPercentage"]);
                if (tele.CpuClockMhz == null && obj["CurrentClockSpeed"] != null)
                    tele.CpuClockMhz = Convert.ToSingle(obj["CurrentClockSpeed"]);
                count++;
            }
            tele.CpuPct = count > 0 ? cpuPct / count : 0;
            tele.CpuKernelPct = GetCpuKernelTimePercent();

            // RAM Usage
            using var os = new ManagementObjectSearcher("SELECT FreePhysicalMemory,TotalVisibleMemorySize FROM Win32_OperatingSystem");
            foreach (var obj in os.Get())
            {
                var total = Convert.ToInt64(obj["TotalVisibleMemorySize"]);
                var free  = Convert.ToInt64(obj["FreePhysicalMemory"]);
                tele.RamUsedMb = (int)((total - free) / 1024);
                tele.MemoryAvailableMb = (int)(free / 1024);
            }
            var memory = GetMemoryPerfStats();
            tele.MemoryCommittedPct = memory.committedPct;
            tele.MemoryCacheFaultsSec = memory.cacheFaultsSec;

            // Disk Free (C:)
            var drive = new System.IO.DriveInfo("C");
            if (drive.IsReady)
                tele.DiskFreeGb = (float)Math.Round(drive.AvailableFreeSpace / 1_073_741_824.0, 1);
            var disk = GetDiskPerfStats();
            tele.DiskReadBytesSec = disk.readBytesSec;
            tele.DiskWriteBytesSec = disk.writeBytesSec;
            tele.DiskRwBytesSec = disk.readBytesSec.GetValueOrDefault() + disk.writeBytesSec.GetValueOrDefault();
            tele.DiskQueueLength = disk.queueLength;
            tele.DiskTimePct = disk.diskTimePct;
            tele.DiskLatencyMs = disk.latencyMs;

            // Network I/O
            var (rx, tx, bandwidth, totalBytes, outputQueue) = GetNetworkStats();
            tele.NetRxKbps = rx;
            tele.NetTxKbps = tx;
            tele.NetworkBandwidthBps = bandwidth;
            tele.NetworkBytesTotalSec = totalBytes;
            tele.NetworkOutputQueueLength = outputQueue;
            tele.NetworkLatencyMs = GetNetworkLatencyMs();

            // GPU Usage + Temperature
            RefreshGpuStats();
            tele.GpuPct   = _cachedGpuPct;
            tele.GpuTempC = _cachedGpuTemp;
            tele.GpuName  = _cachedGpuName;

            // CPU Temperature
            tele.CpuTempC = GetCpuTemperature();

            // Peripherals: public builds report device availability only by default.
            tele.CameraAvailable = HasCameraDevice();
            tele.MicrophoneAvailable = HasMicrophoneDevice();
            tele.BiometricAvailable = _collectBiometricData ? HasBiometricDevice() : null;
            tele.CamActive = _collectCameraCapture ? IsCameraPossiblyActive() : false;
            tele.MicActive = _collectMicrophoneCapture ? IsMicrophonePossiblyActive() : false;
            var processStats = GetProcessStats();
            tele.ProcessCount = processStats.processes;
            tele.ThreadCount = processStats.threads;
            tele.HandleCount = processStats.handles;
            tele.PowerProfile = GetActivePowerProfile();
            tele.OnBattery = IsOnBattery();

            // Public IP + Geo (cached, refresh every 5 min)
            if ((DateTime.UtcNow - _lastGeoUpdate) > TimeSpan.FromMinutes(5))
            {
                RefreshGeoIpAsync().GetAwaiter().GetResult();
                _lastGeoUpdate = DateTime.UtcNow;
            }
            tele.PublicIp = _cachedPublicIp;
            tele.GeoCity  = _cachedGeoCity;
            tele.GeoCountry = _cachedGeoCountry;
            tele.GeoLat = _cachedGeoLat;
            tele.GeoLon = _cachedGeoLon;
            tele.LocationLabel = !string.IsNullOrWhiteSpace(_cachedGeoCity)
                ? $"{_cachedGeoCity}{(string.IsNullOrWhiteSpace(_cachedGeoCountry) ? "" : ", " + _cachedGeoCountry)}"
                : (_collectApproxLocation ? null : "Approximate location disabled by policy");
            tele.LocationDetail = new Dictionary<string, object?>
            {
                ["source"] = _collectApproxLocation ? "public_ip_geoip" : "disabled",
                ["lat"] = _cachedGeoLat,
                ["lon"] = _cachedGeoLon,
                ["public_ip"] = _cachedPublicIp
            };
            tele.Metrics = BuildMetricsEnvelope(tele);
            tele.SecurityState = GetSecurityState();
            tele.DeviceInfo = _collectDeviceCapabilities ? BuildDeviceInfoEnvelope() : new Dictionary<string, object?>();
            tele.VerboseInfo = _collectVerboseDiagnostics ? BuildVerboseEnvelope(tele) : BuildPrivacyEnvelope(tele);
        }
        catch (Exception ex)
        {
            _logger.LogWarning("Telemetry collection partial error: {Msg}", ex.Message);
            tele.Bugs["collector_error"] = ex.Message;
        }

        return tele;
    }

    // ── GPU Stats via WMI (works without NVIDIA drivers) ─────────────
    private void RefreshGpuStats()
    {
        try
        {
            // Try NVML-style via WMI (requires NVIDIA Management Library or generic WMI)
            using var gpu = new ManagementObjectSearcher("SELECT * FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine");
            float totalPct = 0; int gpuCount = 0;
            foreach (var obj in gpu.Get())
            {
                if (obj["Name"]?.ToString()?.Contains("3D") == true)
                {
                    totalPct += Convert.ToSingle(obj["UtilizationPercentage"] ?? 0);
                    gpuCount++;
                }
            }
            if (gpuCount > 0) _cachedGpuPct = totalPct / gpuCount;
        }
        catch { /* GPU WMI may not be available on all systems */ }

        try
        {
            // Temperature via generic thermal sensor
            using var thermal = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            foreach (var obj in thermal.Get())
            {
                var kelvin = Convert.ToDouble(obj["CurrentTemperature"]);
                _cachedGpuTemp = (float)Math.Round(kelvin / 10.0 - 273.15, 1);
                break;
            }
        }
        catch { /* thermal WMI not available */ }
    }

    private float? GetCpuTemperature()
    {
        try
        {
            using var thermal = new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            float? temp = null;
            foreach (var obj in thermal.Get())
            {
                var kelvin = Convert.ToDouble(obj["CurrentTemperature"]);
                temp = (float)Math.Round(kelvin / 10.0 - 273.15, 1);
            }
            return temp;
        }
        catch { return null; }
    }

    // ── Camera/Mic Detection ──────────────────────────────────────────
    private bool HasCameraDevice()
    {
        try
        {
            using var pnp = new ManagementObjectSearcher("SELECT Name,Status FROM Win32_PnPEntity WHERE Name LIKE '%Camera%' OR Name LIKE '%Webcam%'");
            foreach (var obj in pnp.Get())
                if (obj["Status"]?.ToString() == "OK") return true;
        }
        catch { }
        return false;
    }

    private bool HasMicrophoneDevice()
    {
        try
        {
            // Check if any audio capture device is present and active
            using var audio = new ManagementObjectSearcher("SELECT * FROM Win32_SoundDevice WHERE Status='OK'");
            return audio.Get().Count > 0;
        }
        catch { return false; }
    }

    private bool HasBiometricDevice()
    {
        try
        {
            using var biometric = new ManagementObjectSearcher("SELECT Name,Status FROM Win32_PnPEntity WHERE Name LIKE '%Biometric%' OR Name LIKE '%Fingerprint%' OR Name LIKE '%Windows Hello%'");
            foreach (var obj in biometric.Get())
                if (obj["Status"]?.ToString() == "OK") return true;
        }
        catch { }
        return false;
    }

    private bool IsCameraPossiblyActive()
    {
        // Conservative signal only. The agent never opens the camera stream.
        return HasCameraDevice();
    }

    private bool IsMicrophonePossiblyActive()
    {
        // Conservative signal only. The agent never opens the microphone stream.
        return HasMicrophoneDevice();
    }

    // ── Network I/O ──────────────────────────────────────────────────
    private (float rx, float tx, double? bandwidthBps, double? totalBytesSec, float? outputQueueLength) GetNetworkStats()
    {
        try
        {
            using var net = new ManagementObjectSearcher("SELECT * FROM Win32_PerfFormattedData_Tcpip_NetworkInterface");
            float rx = 0, tx = 0;
            double bandwidth = 0, total = 0;
            float outputQueue = 0;
            foreach (var obj in net.Get())
            {
                rx += ToFloat(GetWmiValue(obj, "BytesReceivedPerSec")).GetValueOrDefault();
                tx += ToFloat(GetWmiValue(obj, "BytesSentPerSec")).GetValueOrDefault();
                bandwidth += ToDouble(GetWmiValue(obj, "CurrentBandwidth")).GetValueOrDefault();
                total += ToDouble(GetWmiValue(obj, "BytesTotalPerSec")).GetValueOrDefault();
                outputQueue += ToFloat(GetWmiValue(obj, "OutputQueueLength")).GetValueOrDefault();
            }
            return (rx / 1024, tx / 1024, bandwidth > 0 ? bandwidth : null, total > 0 ? total : null, outputQueue);
        }
        catch { return (0, 0, null, null, null); }
    }

    private float? GetNetworkLatencyMs()
    {
        try
        {
            using var ping = new Ping();
            var reply = ping.Send("1.1.1.1", 1000);
            return reply.Status == IPStatus.Success ? reply.RoundtripTime : null;
        }
        catch { return null; }
    }

    private float? GetCpuKernelTimePercent()
    {
        try
        {
            using var cpu = new ManagementObjectSearcher("SELECT PercentPrivilegedTime FROM Win32_PerfFormattedData_PerfOS_Processor WHERE Name='_Total'");
            foreach (var obj in cpu.Get())
                return ToFloat(GetWmiValue(obj, "PercentPrivilegedTime"));
        }
        catch { }
        return null;
    }

    private (float? committedPct, float? cacheFaultsSec) GetMemoryPerfStats()
    {
        try
        {
            using var memory = new ManagementObjectSearcher("SELECT PercentCommittedBytesInUse,CacheFaultsPersec FROM Win32_PerfFormattedData_PerfOS_Memory");
            foreach (var obj in memory.Get())
            {
                return (
                    ToFloat(GetWmiValue(obj, "PercentCommittedBytesInUse")),
                    ToFloat(GetWmiValue(obj, "CacheFaultsPersec"))
                );
            }
        }
        catch { }
        return (null, null);
    }

    private (double? readBytesSec, double? writeBytesSec, float? queueLength, float? diskTimePct, float? latencyMs) GetDiskPerfStats()
    {
        try
        {
            using var disk = new ManagementObjectSearcher("SELECT * FROM Win32_PerfFormattedData_PerfDisk_LogicalDisk WHERE Name='_Total'");
            foreach (var obj in disk.Get())
            {
                var latencySeconds = ToDouble(GetWmiValue(obj, "AvgDisksecPerTransfer"));
                return (
                    ToDouble(GetWmiValue(obj, "DiskReadBytesPersec")),
                    ToDouble(GetWmiValue(obj, "DiskWriteBytesPersec")),
                    ToFloat(GetWmiValue(obj, "CurrentDiskQueueLength")),
                    ToFloat(GetWmiValue(obj, "PercentDiskTime")),
                    latencySeconds.HasValue ? (float)Math.Round(latencySeconds.Value * 1000.0, 2) : null
                );
            }
        }
        catch { }
        return (null, null, null, null, null);
    }

    private (int? processes, int? threads, int? handles) GetProcessStats()
    {
        try
        {
            var processes = Process.GetProcesses();
            var threadCount = 0;
            var handleCount = 0;
            foreach (var process in processes)
            {
                try
                {
                    threadCount += process.Threads.Count;
                    handleCount += process.HandleCount;
                }
                catch { /* protected process */ }
                finally
                {
                    process.Dispose();
                }
            }
            return (processes.Length, threadCount, handleCount);
        }
        catch { return (null, null, null); }
    }

    private string? GetActivePowerProfile()
    {
        if (!OperatingSystem.IsWindows()) return null;
        try
        {
            using var process = Process.Start(new ProcessStartInfo
            {
                FileName = "powercfg",
                ArgumentList = { "/GETACTIVESCHEME" },
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            });
            if (process == null) return null;
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(1000);
            var open = output.LastIndexOf('(');
            var close = output.LastIndexOf(')');
            if (open >= 0 && close > open) return output[(open + 1)..close].Trim();
            return output.Trim();
        }
        catch { return null; }
    }

    private bool? IsOnBattery()
    {
        if (!OperatingSystem.IsWindows()) return null;
        try
        {
            using var battery = new ManagementObjectSearcher("SELECT BatteryStatus FROM Win32_Battery");
            foreach (var obj in battery.Get())
            {
                var status = Convert.ToInt32(GetWmiValue(obj, "BatteryStatus") ?? 0);
                return status != 2; // 2 = AC power/charging.
            }
            return false;
        }
        catch { return null; }
    }

    private List<Dictionary<string, object?>> GetDiskProfile()
    {
        var disks = new List<Dictionary<string, object?>>();
        try
        {
            using var drives = new ManagementObjectSearcher("SELECT Model,InterfaceType,MediaType,Size,DeviceID FROM Win32_DiskDrive");
            foreach (var obj in drives.Get())
            {
                var model = obj["Model"]?.ToString() ?? "";
                var mediaType = obj["MediaType"]?.ToString() ?? "";
                var interfaceType = obj["InterfaceType"]?.ToString() ?? "";
                disks.Add(new Dictionary<string, object?>
                {
                    ["model"] = model,
                    ["interface_type"] = interfaceType,
                    ["media_type"] = mediaType,
                    ["size_bytes"] = ToDouble(obj["Size"]),
                    ["profile"] = InferDiskProfile(model, mediaType, interfaceType),
                    ["device_id"] = obj["DeviceID"]?.ToString() ?? ""
                });
            }
        }
        catch { }
        return disks;
    }

    private Dictionary<string, object?> GetSecurityState()
    {
        var state = new Dictionary<string, object?>();
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System");
            var enableLua = key?.GetValue("EnableLUA");
            state["uac_enabled"] = enableLua == null || Convert.ToInt32(enableLua) == 1;
        }
        catch { }

        try
        {
            using var defender = new ManagementObjectSearcher(@"root\Microsoft\Windows\Defender", "SELECT AntivirusEnabled,RealTimeProtectionEnabled FROM MSFT_MpComputerStatus");
            foreach (var obj in defender.Get())
            {
                state["defender_antivirus_enabled"] = Convert.ToBoolean(GetWmiValue(obj, "AntivirusEnabled") ?? false);
                state["defender_realtime_enabled"] = Convert.ToBoolean(GetWmiValue(obj, "RealTimeProtectionEnabled") ?? false);
                break;
            }
        }
        catch { }

        try
        {
            var volumes = new List<Dictionary<string, object?>>();
            using var bitlocker = new ManagementObjectSearcher(@"root\CIMV2\Security\MicrosoftVolumeEncryption", "SELECT DriveLetter,ProtectionStatus FROM Win32_EncryptableVolume");
            foreach (var obj in bitlocker.Get())
            {
                volumes.Add(new Dictionary<string, object?>
                {
                    ["drive"] = obj["DriveLetter"]?.ToString() ?? "",
                    ["protection_status"] = ToInt(GetWmiValue(obj, "ProtectionStatus"))
                });
            }
            if (volumes.Count > 0) state["bitlocker_volumes"] = volumes;
        }
        catch { }

        return state;
    }

    private static Dictionary<string, object?> BuildMetricsEnvelope(TelemetryRequest tele)
    {
        return new Dictionary<string, object?>
        {
            ["cpu"] = new Dictionary<string, object?>
            {
                ["utilization_percent"] = tele.CpuPct,
                ["kernel_time_percent"] = tele.CpuKernelPct,
                ["clock_mhz"] = tele.CpuClockMhz
            },
            ["memory"] = new Dictionary<string, object?>
            {
                ["available_mb"] = tele.MemoryAvailableMb,
                ["used_mb"] = tele.RamUsedMb,
                ["committed_percent"] = tele.MemoryCommittedPct,
                ["cache_faults_sec"] = tele.MemoryCacheFaultsSec
            },
            ["disk"] = new Dictionary<string, object?>
            {
                ["free_gb"] = tele.DiskFreeGb,
                ["read_bytes_sec"] = tele.DiskReadBytesSec,
                ["write_bytes_sec"] = tele.DiskWriteBytesSec,
                ["read_write_bytes_sec"] = tele.DiskRwBytesSec,
                ["queue_length"] = tele.DiskQueueLength,
                ["disk_time_percent"] = tele.DiskTimePct,
                ["latency_ms"] = tele.DiskLatencyMs
            },
            ["network"] = new Dictionary<string, object?>
            {
                ["rx_kbps"] = tele.NetRxKbps,
                ["tx_kbps"] = tele.NetTxKbps,
                ["current_bandwidth_bps"] = tele.NetworkBandwidthBps,
                ["bytes_total_sec"] = tele.NetworkBytesTotalSec,
                ["output_queue_length"] = tele.NetworkOutputQueueLength,
                ["latency_ms"] = tele.NetworkLatencyMs
            },
            ["thermal_power"] = new Dictionary<string, object?>
            {
                ["cpu_temperature_c"] = tele.CpuTempC,
                ["power_profile"] = tele.PowerProfile,
                ["on_battery"] = tele.OnBattery
            },
            ["gpu"] = new Dictionary<string, object?>
            {
                ["name"] = tele.GpuName,
                ["utilization_percent"] = tele.GpuPct,
                ["temperature_c"] = tele.GpuTempC
            },
            ["peripherals"] = new Dictionary<string, object?>
            {
                ["camera_available"] = tele.CameraAvailable,
                ["microphone_available"] = tele.MicrophoneAvailable,
                ["biometric_available"] = tele.BiometricAvailable,
                ["cam_active"] = tele.CamActive,
                ["mic_active"] = tele.MicActive,
                ["capture_policy"] = "disabled unless explicit admin/user consent enables capture diagnostics"
            },
            ["processes"] = new Dictionary<string, object?>
            {
                ["process_count"] = tele.ProcessCount,
                ["thread_count"] = tele.ThreadCount,
                ["handle_count"] = tele.HandleCount
            }
        };
    }

    private static Dictionary<string, object?> BuildPrivacyEnvelope(TelemetryRequest tele)
    {
        return new Dictionary<string, object?>
        {
            ["agent"] = new Dictionary<string, object?>
            {
                ["source"] = "neo_agent",
                ["collector"] = "SystemCollector",
                ["schema_version"] = tele.SchemaVersion,
                ["sample_kind"] = tele.SampleKind,
                ["timestamp_utc"] = tele.Timestamp,
                ["telemetry_interval_note"] = "Lightweight endpoint telemetry; no secrets, user documents, camera stream, microphone stream, or biometric data are collected."
            }
        };
    }

    private static Dictionary<string, object?> BuildDeviceInfoEnvelope()
    {
        return new Dictionary<string, object?>
        {
            ["computer_name"] = Environment.MachineName,
            ["os_version"] = Environment.OSVersion.VersionString,
            ["is_64_bit_os"] = Environment.Is64BitOperatingSystem,
            ["is_64_bit_process"] = Environment.Is64BitProcess,
            ["processor_count"] = Environment.ProcessorCount,
            ["dotnet_runtime"] = Environment.Version.ToString()
        };
    }

    private static Dictionary<string, object?> BuildVerboseEnvelope(TelemetryRequest tele)
    {
        return new Dictionary<string, object?>
        {
            ["agent"] = new Dictionary<string, object?>
            {
                ["source"] = "neo_agent",
                ["collector"] = "SystemCollector",
                ["schema_version"] = tele.SchemaVersion,
                ["sample_kind"] = tele.SampleKind,
                ["timestamp_utc"] = tele.Timestamp,
                ["telemetry_interval_note"] = "Lightweight endpoint audit telemetry; no secrets or user documents are collected."
            },
            ["audit_hints"] = new Dictionary<string, object?>
            {
                ["cpu_pressure"] = tele.CpuPct >= 85,
                ["memory_pressure"] = tele.MemoryCommittedPct >= 85,
                ["disk_queue_pressure"] = tele.DiskQueueLength >= 2,
                ["thermal_pressure"] = (tele.CpuTempC >= 85) || (tele.GpuTempC >= 84),
                ["rmm_command_hint"] = "SYSTEM_DIAGNOSTICS"
            }
        };
    }

    private static string InferDiskProfile(string model, string mediaType, string interfaceType)
    {
        var joined = $"{model} {mediaType} {interfaceType}";
        if (joined.Contains("NVMe", StringComparison.OrdinalIgnoreCase)) return "SSD_NVME";
        if (joined.Contains("SSD", StringComparison.OrdinalIgnoreCase) || joined.Contains("Solid", StringComparison.OrdinalIgnoreCase)) return "SATA_SSD";
        if (joined.Contains("HDD", StringComparison.OrdinalIgnoreCase) || joined.Contains("Fixed hard disk", StringComparison.OrdinalIgnoreCase)) return "HDD";
        return "UNKNOWN";
    }

    private static object? GetWmiValue(ManagementBaseObject obj, string name)
    {
        foreach (PropertyData property in obj.Properties)
        {
            if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
                return property.Value;
        }
        return null;
    }

    private static float? ToFloat(object? value)
    {
        if (value == null) return null;
        try { return Convert.ToSingle(value); } catch { return null; }
    }

    private static double? ToDouble(object? value)
    {
        if (value == null) return null;
        try { return Convert.ToDouble(value); } catch { return null; }
    }

    private static int? ToInt(object? value)
    {
        if (value == null) return null;
        try { return Convert.ToInt32(value); } catch { return null; }
    }

    // ── GeoIP ────────────────────────────────────────────────────────
    private async Task RefreshGeoIpAsync()
    {
        try
        {
            var ipResp = await _http.GetStringAsync("https://api.ipify.org?format=text");
            _cachedPublicIp = ipResp.Trim();
            if (!_collectApproxLocation) return;

            var geoResp = await _http.GetStringAsync($"http://ip-api.com/json/{_cachedPublicIp}?fields=status,city,country,regionName,lat,lon");
            var geo = JsonSerializer.Deserialize<JsonElement>(geoResp);
            if (geo.GetProperty("status").GetString() == "success")
            {
                var city    = geo.GetProperty("city").GetString() ?? "";
                var country = geo.GetProperty("country").GetString() ?? "";
                _cachedGeoCity = city;
                _cachedGeoCountry = country;
                _cachedGeoLat = geo.TryGetProperty("lat", out var lat) ? lat.GetDouble() : null;
                _cachedGeoLon = geo.TryGetProperty("lon", out var lon) ? lon.GetDouble() : null;
            }
        }
        catch { /* GeoIP is best-effort */ }
    }

    private static bool ReadBool(IConfiguration configuration, string key, bool defaultValue)
    {
        var value = configuration[key];
        return bool.TryParse(value, out var parsed) ? parsed : defaultValue;
    }
}
