#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Aegis AV / NeoMonitor - L0 Threat & Intrusion Monitor v1.0
.DESCRIPTION
    Scans the system for indicators of compromise (IoC), fileless malware,
    suspicious network connections, and hidden processes.
    Outputs structured JSON telemetry to be analyzed by the NeoMonitor AI.
#>

$ErrorActionPreference = "SilentlyContinue"
$ThreatPayload = @{
    "scan_time" = (Get-Date -Format 'yyyy-MM-dd HH:mm:ssZ')
    "suspicious_processes" = @()
    "suspicious_network" = @()
    "powershell_anomalies" = @()
    "defender_status" = ""
    "overall_risk_score" = 0
}
$riskScore = 0

Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   L0 Threat & Intrusion Monitor Initiated        " -ForegroundColor Cyan
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan

# ─── 1. Defender Health Check ─────────────────────────────────────────────────
Write-Host "  [1/4] Checking Windows Defender Health..." -ForegroundColor Yellow
$defender = Get-MpComputerStatus
if ($defender.RealTimeProtectionEnabled -eq $False) {
    $ThreatPayload["defender_status"] = "CRITICAL: Real-Time Protection Disabled"
    $riskScore += 40
} else {
    $ThreatPayload["defender_status"] = "Healthy"
}

# ─── 2. Suspicious Process Heuristics (Fileless Malware / DeepLoad) ─────────
Write-Host "  [2/4] Scanning for Anomalous Processes..." -ForegroundColor Yellow
$processes = Get-WmiObject Win32_Process | Select-Object Name, ProcessId, CommandLine, ExecutablePath
foreach ($p in $processes) {
    # Check for hidden/encoded PowerShell executions
    if ($p.Name -match "(powershell|pwsh).exe" -and $p.CommandLine -match "(-w hidden|-enc|-e |bypass)") {
        $ThreatPayload["suspicious_processes"] += @{
            "pid" = $p.ProcessId
            "name" = $p.Name
            "cmd" = $p.CommandLine
            "reason" = "Hidden/Encoded PowerShell (Possible DeepLoad Injection)"
        }
        $riskScore += 30
    }

    # Check for legitimate processes spawned from weird locations (e.g., svchost running from AppData)
    if ($p.Name -match "(svchost|explorer|cmd|conhost).exe" -and $p.ExecutablePath -match "(AppData|Temp|ProgramData)") {
        $ThreatPayload["suspicious_processes"] += @{
            "pid" = $p.ProcessId
            "name" = $p.Name
            "path" = $p.ExecutablePath
            "reason" = "Core OS Process executing from User Space (Masquerading)"
        }
        $riskScore += 30
    }
}

# ─── 3. Suspicious Network Connections (Reverse Shells / C2) ────────────────
Write-Host "  [3/4] Analyzing Active TCP/UDP Connections..." -ForegroundColor Yellow
$connections = Get-NetTCPConnection -State Established -EA SilentlyContinue
$knownPorts = @(80, 443, 53, 3389, 22, 5985, 5986)
foreach ($conn in $connections) {
    if ($knownPorts -notcontains $conn.RemotePort -and $conn.RemoteAddress -notmatch "^(127\.|192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)") {
        # Unknown high port connecting to public IP
        $owningProcess = (Get-Process -Id $conn.OwningProcess -EA SilentlyContinue).Name
        $ThreatPayload["suspicious_network"] += @{
            "pid" = $conn.OwningProcess
            "process" = $owningProcess
            "remote_ip" = $conn.RemoteAddress
            "remote_port" = $conn.RemotePort
            "reason" = "Non-standard port connected to public IP"
        }
        $riskScore += 10
    }
}

# ─── 4. ETW / Event Log Analysis (Event 4104 PowerShell ScriptBlock) ────────
Write-Host "  [4/4] Analyzing Security Event Logs (Last 1 Hour)..." -ForegroundColor Yellow
$timeSpan = (Get-Date).AddHours(-1)
$psEvents = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-PowerShell/Operational'; ID=4104; StartTime=$timeSpan} -EA SilentlyContinue
foreach ($evt in $psEvents) {
    if ($evt.Message -match "(IEX|Invoke-Expression|FromBase64String|DownloadString|System.Reflection.Assembly)") {
        $ThreatPayload["powershell_anomalies"] += @{
            "time" = $evt.TimeCreated
            "script_block" = $evt.Message.Substring(0, [math]::Min($evt.Message.Length, 200)) + "..."
            "reason" = "Suspicious code execution pattern detected in ScriptBlock"
        }
        $riskScore += 20
    }
}

$ThreatPayload["overall_risk_score"] = $riskScore

Write-Host "    [+] Threat Scan Complete. Risk Score: $riskScore" -ForegroundColor $(if($riskScore -gt 40){"Red"}elseif($riskScore -gt 10){"Yellow"}else{"Green"})
Write-Host "`n[AEGIS] ===================================================" -ForegroundColor Cyan
Write-Host "[AEGIS]   Telemetry Extracted. Sending to NeoMonitor...  " -ForegroundColor Cyan
Write-Host "[AEGIS] ===================================================`n" -ForegroundColor Cyan

# Output JSON for the C# agent to send to the server
$ThreatPayload | ConvertTo-Json -Depth 5 -Compress | Write-Output
