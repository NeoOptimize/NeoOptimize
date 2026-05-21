using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using NeoOptimize.Agent.Models;
using NeoOptimize.Agent.Security;
using NeoOptimize.Agent.Commands;
using System.Reflection;

namespace NeoOptimize.Agent.Services;

// ═══════════════════════════════════════════════════════════════════
// AgentWorker v5.0 — Production Hardened
// FIXES:
//   [BUG#3]  Per-command timeout from CheckInResponse.TimeoutSecs
//   [BUG#3]  Exponential backoff with jitter on network errors
//   [NEW]    Verbose structured logging (Debug mode toggle)
//   [NEW]    Graceful shutdown with cleanup
// ═══════════════════════════════════════════════════════════════════

public class AgentWorker : BackgroundService
{
    private readonly ILogger<AgentWorker> _logger;
    private readonly ApiClient _api;
    private readonly ISystemCollector _sys;
    private readonly RsaVerifier _verifier;
    private readonly CommandDispatcher _dispatcher;

    private readonly string _version;
    private readonly int _telemetryIntervalSec;
    private DateTime _lastTelemetry = DateTime.MinValue;
    private int _consecutiveErrors  = 0;
    private const int PollingIntervalSec   = 5;
    private const int MaxBackoffSec        = 120;

    public AgentWorker(
        ILogger<AgentWorker> logger,
        ApiClient api,
        ISystemCollector sys,
        RsaVerifier verifier,
        CommandDispatcher dispatcher,
        IConfiguration configuration)
    {
        _logger     = logger;
        _api        = api;
        _sys        = sys;
        _verifier   = verifier;
        _dispatcher = dispatcher;
        _version    = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "5.0.0";
        _telemetryIntervalSec = Math.Clamp(ReadInt(configuration, "Telemetry:IntervalSeconds", 1), 1, 60);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("═══════════════════════════════════════════");
        _logger.LogInformation("  NeoOptimize Aegis Agent v{Version} STARTED", _version);
        _logger.LogInformation("═══════════════════════════════════════════");

        string uuid = _sys.GetBiosUuid();
        _logger.LogInformation("[BOOT] Agent UUID      : {Uuid}", uuid);
        _logger.LogInformation("[BOOT] Machine Hostname: {Host}", Environment.MachineName);
        _logger.LogInformation("[BOOT] OS Platform     : {OS}", Environment.OSVersion);
        _logger.LogInformation("[BOOT] .NET Runtime    : {RT}", Environment.Version);

        var startupRecovery = await _dispatcher.RecoverPendingExecutionAsync(stoppingToken);
        if (startupRecovery != null && TryGetString(startupRecovery, "command_id", out var recoveredCommandId))
        {
            _logger.LogCritical("[SAFETY] Emergency rollback completed for interrupted command {CommandId}", recoveredCommandId);
            await _api.SendReportAsync(new ReportRequest
            {
                Uuid = uuid,
                CmdId = recoveredCommandId,
                Status = ResolveReportStatus(startupRecovery),
                Result = startupRecovery
            }, stoppingToken);
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                // ── 1. Telemetry (every TelemetryIntervalSec) ──────────────────
                if (DateTime.UtcNow - _lastTelemetry > TimeSpan.FromSeconds(_telemetryIntervalSec))
                {
                    _logger.LogDebug("[TELE] Collecting system telemetry...");
                    var tel = _sys.GetTelemetry();

                    _logger.LogDebug("[TELE] CPU={Cpu:F1}% RAM={Ram}MB Disk={Disk}GB GPU={Gpu:F1}% GpuTemp={GpuT:F0}°C",
                        tel.CpuPct, tel.RamUsedMb, tel.DiskFreeGb, tel.GpuPct, tel.GpuTempC);

                    await _api.SendTelemetryAsync(tel, stoppingToken);
                    _lastTelemetry = DateTime.UtcNow;
                }

                // ── 2. Check-In (poll for commands) ────────────────────────────
                _logger.LogDebug("[POLL] Checking in to server...");
                var req = new CheckInRequest
                {
                    Uuid     = uuid,
                    Hostname = Environment.MachineName,
                    Version  = _version,
                    Meta     = _sys.GetSystemMeta()
                };

                var res = await _api.CheckInAsync(req, stoppingToken);

                // Reset error counter on successful comms
                _consecutiveErrors = 0;

                // ── 3. Execute Command (if any) ─────────────────────────────────
                if (res != null && !string.IsNullOrEmpty(res.Cmd) && !string.IsNullOrEmpty(res.Id))
                {
                    _logger.LogInformation("[CMD] Received command: {Type} [ID={Id}]", res.Cmd, res.Id);

                    // ── ZERO TRUST: Verify RSA Signature ──────────────────────────
                    if (string.IsNullOrEmpty(res.Sig) || !_verifier.VerifyCommand(res.Id, res.Cmd, res.Args, res.Sig))
                    {
                        _logger.LogCritical("[SECURITY] ⚠ Signature REJECTED for cmd {Id} — POSSIBLE MITM ATTACK!", res.Id);

                        await _api.SendReportAsync(new ReportRequest
                        {
                            Uuid   = uuid,
                            CmdId  = res.Id,
                            Status = "rejected",
                            Result = new Dictionary<string, object> { { "error", "RSA signature invalid — command dropped" } }
                        }, stoppingToken);

                        await Task.Delay(PollingIntervalSec * 1000, stoppingToken);
                        continue;
                    }

                    _logger.LogInformation("[CMD] Signature VERIFIED ✓ — executing {Type}...", res.Cmd);

                    // ── [BUG#3 FIX] Per-command timeout ───────────────────────────
                    int timeoutSecs = res.TimeoutSecs > 0 ? res.TimeoutSecs : 300;
                    using var cmdCts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                    cmdCts.CancelAfter(TimeSpan.FromSeconds(timeoutSecs));

                    try
                    {
                        var resultDict = await _dispatcher.ExecuteAsync(res.Cmd, res.Args, cmdCts.Token);
                        var reportStatus = ResolveReportStatus(resultDict);

                        if (reportStatus == "success")
                            _logger.LogInformation("[CMD] ✓ {Type} completed successfully.", res.Cmd);
                        else
                            _logger.LogWarning("[CMD] {Type} completed with report status {Status}.", res.Cmd, reportStatus);
                        _logger.LogDebug("[CMD] Result keys: {Keys}", string.Join(", ", resultDict.Keys));

                        await _api.SendReportAsync(new ReportRequest
                        {
                            Uuid   = uuid,
                            CmdId  = res.Id,
                            Status = reportStatus,
                            Result = resultDict
                        }, stoppingToken);
                    }
                    catch (OperationCanceledException) when (cmdCts.IsCancellationRequested && !stoppingToken.IsCancellationRequested)
                    {
                        _logger.LogWarning("[CMD] ⏱ {Type} timed out after {Sec}s", res.Cmd, timeoutSecs);
                        await _api.SendReportAsync(new ReportRequest
                        {
                            Uuid   = uuid,
                            CmdId  = res.Id,
                            Status = "timeout",
                            Result = new Dictionary<string, object> { { "error", $"Timed out after {timeoutSecs}s" } }
                        }, stoppingToken);
                    }
                    catch (Exception cmdEx)
                    {
                        _logger.LogError(cmdEx, "[CMD] ✗ {Type} FAILED: {Msg}", res.Cmd, cmdEx.Message);
                        await _api.SendReportAsync(new ReportRequest
                        {
                            Uuid   = uuid,
                            CmdId  = res.Id,
                            Status = "failed",
                            Result = new Dictionary<string, object> { { "error", cmdEx.Message }, { "stack", cmdEx.StackTrace ?? "" } }
                        }, stoppingToken);
                    }
                }
                else
                {
                    _logger.LogDebug("[POLL] No pending commands. Idle.");
                }

                await Task.Delay(PollingIntervalSec * 1000, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break; // graceful shutdown
            }
            catch (Exception ex)
            {
                _consecutiveErrors++;
                // Exponential backoff with jitter: min 30s, max 120s
                int backoffSec = Math.Min(MaxBackoffSec, 30 * (int)Math.Pow(2, Math.Min(_consecutiveErrors - 1, 3)));
                int jitter     = Random.Shared.Next(0, 5);

                _logger.LogError("[LOOP] Agent loop error #{N}: {Msg} — retrying in {Sec}s",
                    _consecutiveErrors, ex.Message, backoffSec + jitter);

                await Task.Delay((backoffSec + jitter) * 1000, stoppingToken);
            }
        }

        _logger.LogInformation("[SHUTDOWN] NeoOptimize Agent stopped gracefully.");
    }

    private static string ResolveReportStatus(Dictionary<string, object> result)
    {
        if (TryGetString(result, "report_status", out var explicitStatus) &&
            (explicitStatus == "success" || explicitStatus == "failed" || explicitStatus == "timeout"))
        {
            return explicitStatus;
        }

        if (TryGetBool(result, "rejected") || TryGetBool(result, "rollback") || TryGetBool(result, "rolled_back"))
            return "failed";

        if (TryGetInt(result, "exitCode", out var exitCode) && exitCode != 0)
            return "failed";

        if (result.TryGetValue("error", out var error) &&
            error != null &&
            !string.IsNullOrWhiteSpace(Convert.ToString(error)))
        {
            return "failed";
        }

        return "success";
    }

    private static bool TryGetString(Dictionary<string, object> result, string key, out string value)
    {
        value = "";
        if (!result.TryGetValue(key, out var raw) || raw == null) return false;
        value = Convert.ToString(raw)?.Trim().ToLowerInvariant() ?? "";
        return !string.IsNullOrWhiteSpace(value);
    }

    private static bool TryGetBool(Dictionary<string, object> result, string key)
    {
        return result.TryGetValue(key, out var value) && value switch
        {
            bool boolValue => boolValue,
            string text => bool.TryParse(text, out var parsed) && parsed,
            _ => false
        };
    }

    private static bool TryGetInt(Dictionary<string, object> result, string key, out int number)
    {
        number = 0;
        if (!result.TryGetValue(key, out var value) || value == null) return false;
        try
        {
            number = Convert.ToInt32(value);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static int ReadInt(IConfiguration configuration, string key, int fallback)
    {
        var value = configuration[key] ?? configuration[$"Agent:{key}"];
        return int.TryParse(value, out var parsed) ? parsed : fallback;
    }
}
