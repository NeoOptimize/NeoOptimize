#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    NeoOptimize Agent v1.0 - audit, scoring, reporting, and safe remediation.
#>

param(
    [ValidateSet("Audit", "Remediate", "Install", "Uninstall", "Status", "Sync", "SyncLoop")]
    [string]$Mode = "Audit",

    [ValidateSet("Safe", "Balanced", "Technician")]
    [string]$Profile = "Safe",

    [switch]$Quiet,
    [switch]$NoOpen,
    [switch]$AssumeYes
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$LibPath = Join-Path $PSScriptRoot "lib\Common.ps1"
if (-not (Test-Path $LibPath)) {
    Write-Host "ERROR: lib\Common.ps1 tidak ditemukan." -ForegroundColor Red
    exit 1
}
. $LibPath

$CapabilityLibPath = Join-Path $PSScriptRoot "lib\NeoCapabilityCatalog.ps1"
if (Test-Path $CapabilityLibPath) {
    . $CapabilityLibPath
}

$Global:NeoOptimizeSkipPause = $true
$Global:NeoOptimizeNonInteractive = [bool]$Quiet
$Global:NeoOptimizeConfirmAll = [bool]$AssumeYes

$PolicyPath = Join-Path $PSScriptRoot "config\NeoOptimize.AgentPolicy.json"
$AgentReportDir = Join-Path $Global:LogDir "agent"
if (-not (Test-Path $AgentReportDir)) {
    New-Item -Path $AgentReportDir -ItemType Directory -Force | Out-Null
}

function Get-AgentPolicy {
    $fallback = [PSCustomObject]@{
        SchemaVersion = "1.0"
        DefaultProfile = "Safe"
        Thresholds = [PSCustomObject]@{
            DiskCriticalFreePercent = 8
            DiskWarnFreePercent = 15
            TempWarnMB = 2048
            StartupWarnCount = 35
            DefinitionWarnDays = 7
            UptimeWarnDays = 14
            RestorePointWarnDays = 7
            RamPressureWarnPercent = 15
        }
        SeverityImpact = [PSCustomObject]@{
            Critical = 20
            High = 14
            Medium = 8
            Low = 4
            Info = 0
        }
        SafeRemediationRuleIds = @("NEO-RP-001", "NEO-FW-001", "NEO-DEF-001", "NEO-DEF-002", "NEO-SMB-001", "NEO-RDP-001", "NEO-SVC-001", "NEO-WU-001")
        ReportRetentionDays = 30
        ScheduledTaskName = "NeoOptimize-Agent-Audit"
    }

    if (-not (Test-Path $PolicyPath)) { return $fallback }
    try {
        return Get-Content -Path $PolicyPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Warn "Policy agent rusak, memakai default: $($_.Exception.Message)"
        return $fallback
    }
}

$Policy = Get-AgentPolicy

function Write-AgentBanner {
    if ($Quiet) { return }
    Write-NeoLogo -Compact
    Write-SectionHeader "" "NEOOPTIMIZE AGENT" "Audit, scoring, reporting, safe remediation"
}

function Get-Impact {
    param([string]$Severity)
    $value = $Policy.SeverityImpact.$Severity
    if ($null -eq $value) { return 0 }
    return [int]$value
}

function New-Finding {
    param(
        [string]$Id,
        [string]$Category,
        [string]$Severity,
        [string]$Title,
        [string]$Evidence,
        [string]$Recommendation,
        [bool]$CanRemediate = $false
    )

    $impact = Get-Impact $Severity
    return [PSCustomObject]@{
        Id = $Id
        Category = $Category
        Severity = $Severity
        Impact = $impact
        CanRemediate = $CanRemediate
        Title = $Title
        Evidence = $Evidence
        Recommendation = $Recommendation
    }
}

function Get-AgentSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $gpu = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
    $sysDrive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction SilentlyContinue

    $snapshot = [PSCustomObject]@{
        Timestamp = Get-Date
        ComputerName = $env:COMPUTERNAME
        User = $env:USERNAME
        OS = $os.Caption
        OSVersion = $os.Version
        Build = $os.BuildNumber
        Architecture = $os.OSArchitecture
        UptimeDays = if ($os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2) } else { $null }
        CPU = $cpu.Name
        Cores = $cpu.NumberOfCores
        Threads = $cpu.NumberOfLogicalProcessors
        RAMTotalGB = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { $null }
        RAMFreeGB = if ($os.FreePhysicalMemory) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { $null }
        SystemDrive = $env:SystemDrive
        SystemDriveFreeGB = if ($sysDrive.FreeSpace) { [math]::Round($sysDrive.FreeSpace / 1GB, 2) } else { $null }
        SystemDriveSizeGB = if ($sysDrive.Size) { [math]::Round($sysDrive.Size / 1GB, 2) } else { $null }
        GPU = $gpu.Name
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        BIOS = $bios.SMBIOSBIOSVersion
        BiosUUID = if ($cs.UUID) { $cs.UUID } else { (Get-CimInstance Win32_ComputerSystemProduct).UUID }
    }
    return $snapshot
}

function Get-EndpointStatePath {
    $dir = Join-Path $env:ProgramData "NeoOptimize"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    return (Join-Path $dir "EndpointSync.json")
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
}

function Read-EndpointSyncConfig {
    $uiConfig = Read-JsonFile (Join-Path $PSScriptRoot "config\NeoOptimize.RMM.json")
    $statePath = Get-EndpointStatePath
    $state = Read-JsonFile $statePath
    $legacy = Read-JsonFile (Join-Path $PSScriptRoot "rmm-agent\appsettings.json")

    $serverUrls = [System.Collections.Generic.List[string]]::new()
    foreach ($value in @(
        $env:NEOOPTIMIZE_RMM_URL,
        (Get-ItemPropertyValue -Path "HKLM:\Software\NeoOptimize" -Name "ServerUrl" -ErrorAction SilentlyContinue),
        $state.ServerUrl,
        $legacy.ServerUrl
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$value)) { $serverUrls.Add(([string]$value).TrimEnd("/")) }
    }
    if ($uiConfig -and $uiConfig.candidate_server_urls) {
        foreach ($url in @($uiConfig.candidate_server_urls)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$url)) { $serverUrls.Add(([string]$url).TrimEnd("/")) }
        }
    }

    if ($serverUrls.Count -eq 0) {
        foreach ($url in @("http://192.168.122.1:3000", "http://127.0.0.1:3000")) { $serverUrls.Add($url) }
    }

    $operatorTerminal = $false
    if ($uiConfig -and $uiConfig.operator_terminal -and $null -ne $uiConfig.operator_terminal.enabled) {
        $operatorTerminal = [bool]$uiConfig.operator_terminal.enabled
    }

    return [PSCustomObject]@{
        ServerUrls = @($serverUrls | Select-Object -Unique)
        ServerUrl = if ($state.ServerUrl) { [string]$state.ServerUrl } else { "" }
        ApiKey = if ($state.ApiKey) { [string]$state.ApiKey } elseif ($legacy.ApiKey) { [string]$legacy.ApiKey } else { "" }
        EnrollmentToken = if ($env:NEO_RMM_ENROLLMENT_TOKEN) { [string]$env:NEO_RMM_ENROLLMENT_TOKEN } elseif ($env:AGENT_ENROLLMENT_TOKEN) { [string]$env:AGENT_ENROLLMENT_TOKEN } elseif ($state.EnrollmentToken) { [string]$state.EnrollmentToken } elseif ($legacy.EnrollmentToken) { [string]$legacy.EnrollmentToken } else { "" }
        CheckInIntervalSeconds = if ($uiConfig.endpoint_sync.checkin_interval_seconds) { [int]$uiConfig.endpoint_sync.checkin_interval_seconds } else { 30 }
        OperatorTerminalEnabled = $operatorTerminal
        TransportSecurity = if ($uiConfig -and $uiConfig.transport_security) { $uiConfig.transport_security } else { [PSCustomObject]@{} }
        Telemetry = if ($uiConfig -and $uiConfig.telemetry) { $uiConfig.telemetry } else { [PSCustomObject]@{} }
        StatePath = $statePath
    }
}

function Save-EndpointSyncState {
    param([string]$ServerUrl, [string]$ApiKey, [string]$EnrollmentToken = "")
    [PSCustomObject]@{
        ServerUrl = $ServerUrl.TrimEnd("/")
        ApiKey = $ApiKey
        EnrollmentToken = $EnrollmentToken
        UpdatedAt = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 4 | Set-Content -Path (Get-EndpointStatePath) -Encoding UTF8
}

function Read-AgentTransportSecurityConfig {
    $cfg = Read-JsonFile (Join-Path $PSScriptRoot "config\NeoOptimize.RMM.json")
    $security = if ($cfg -and $cfg.transport_security) { $cfg.transport_security } else { [PSCustomObject]@{} }
    return [PSCustomObject]@{
        PreferHttps = if ($null -ne $security.prefer_https) { [bool]$security.prefer_https } else { $true }
        RequireHttps = if ($env:NEOOPTIMIZE_REQUIRE_HTTPS) { $env:NEOOPTIMIZE_REQUIRE_HTTPS -match '^(1|true|yes)$' } elseif ($null -ne $security.require_https) { [bool]$security.require_https } else { $true }
        AllowInsecureHttpLab = if ($null -ne $security.allow_insecure_http_lab) { [bool]$security.allow_insecure_http_lab } else { $false }
        ServerCertificateSha256 = if ($env:NEOOPTIMIZE_RMM_CERT_SHA256) { [string]$env:NEOOPTIMIZE_RMM_CERT_SHA256 } elseif ($security.server_certificate_sha256) { [string]$security.server_certificate_sha256 } else { "" }
        SignRequests = if ($null -ne $security.sign_requests) { [bool]$security.sign_requests } else { $true }
        SignatureMaxSkewSeconds = if ($security.signature_max_skew_seconds) { [int]$security.signature_max_skew_seconds } else { 300 }
    }
}

function Test-PrivateOrLoopbackHost {
    param([string]$HostName)
    if ([string]::IsNullOrWhiteSpace($HostName)) { return $false }
    $h = $HostName.ToLowerInvariant()
    if ($h -in @("localhost", "127.0.0.1", "::1")) { return $true }
    if ($h -match '^127\.') { return $true }
    if ($h -match '^10\.') { return $true }
    if ($h -match '^192\.168\.') { return $true }
    if ($h -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.') { return $true }
    if ($h.EndsWith(".local")) { return $true }
    return $false
}

function ConvertTo-NeoStableObject {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $ordered[[string]$key] = ConvertTo-NeoStableObject $Value[$key]
        }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-NeoStableObject $item) }
        return $items
    }
    $obj = [ordered]@{}
    foreach ($prop in @($Value.PSObject.Properties | Where-Object { $_.MemberType -in @("NoteProperty", "Property") } | Sort-Object Name)) {
        $obj[$prop.Name] = ConvertTo-NeoStableObject $prop.Value
    }
    return $obj
}

function ConvertTo-NeoStableJson {
    param($Value)
    $stable = ConvertTo-NeoStableObject $Value
    return ($stable | ConvertTo-Json -Depth 24 -Compress)
}

function Get-NeoSha256Hex {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $sha.Dispose()
    }
}

function Get-NeoHmacSha256Hex {
    param([string]$Secret, [string]$Text)
    $key = [System.Text.Encoding]::UTF8.GetBytes([string]$Secret)
    $hmac = [System.Security.Cryptography.HMACSHA256]::new($key)
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Text)
        return (($hmac.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $hmac.Dispose()
    }
}

function Test-NeoRmmCertificatePin {
    param([Uri]$Uri, [string]$ExpectedSha256)
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256) -or $Uri.Scheme -ne "https") { return $true }
    $expected = ($ExpectedSha256 -replace '[^a-fA-F0-9]', '').ToLowerInvariant()
    if ($expected.Length -ne 64) { throw "Invalid server_certificate_sha256 value in NeoOptimize.RMM.json." }

    $tcp = $null
    $ssl = $null
    try {
        $port = if ($Uri.Port -gt 0) { $Uri.Port } else { 443 }
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $iar = $tcp.BeginConnect($Uri.Host, $port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(5))) { throw "TLS pinning connect timeout." }
        $tcp.EndConnect($iar)
        $ssl = [System.Net.Security.SslStream]::new($tcp.GetStream(), $false, ({ param($sender, $cert, $chain, $errors) return $true }))
        $ssl.AuthenticateAsClient($Uri.Host)
        $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actual = (($sha.ComputeHash($cert2.RawData) | ForEach-Object { $_.ToString("x2") }) -join "")
        } finally {
            $sha.Dispose()
        }
        if ($actual -ne $expected) { throw "RMM certificate pin mismatch." }
        return $true
    } finally {
        if ($ssl) { $ssl.Dispose() }
        if ($tcp) { $tcp.Dispose() }
    }
}

function Assert-RmmTransportPolicy {
    param([string]$Url, [object]$Security)
    $uri = [Uri]$Url
    if ($uri.Scheme -eq "http") {
        if ($Security.RequireHttps) { throw "RMM transport rejected: HTTPS is required." }
        if (-not $Security.AllowInsecureHttpLab -or -not (Test-PrivateOrLoopbackHost $uri.Host)) {
            throw "RMM transport rejected: plain HTTP is allowed only for isolated local/private lab hosts."
        }
    } elseif ($uri.Scheme -ne "https") {
        throw "RMM transport rejected: unsupported scheme '$($uri.Scheme)'."
    }
    Test-NeoRmmCertificatePin -Uri $uri -ExpectedSha256 $Security.ServerCertificateSha256 | Out-Null
}

function Add-NeoRequestSignature {
    param(
        [hashtable]$Headers,
        [string]$Method,
        [string]$Url,
        [object]$Body,
        [object]$Security
    )
    if (-not $Security.SignRequests) { return }

    $secret = ""
    if ($Headers.ContainsKey("x-api-key")) { $secret = [string]$Headers["x-api-key"] }
    elseif ($Headers.ContainsKey("x-enrollment-token")) { $secret = [string]$Headers["x-enrollment-token"] }
    if ([string]::IsNullOrWhiteSpace($secret)) { return }

    $uri = [Uri]$Url
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $nonce = "$([guid]::NewGuid().ToString('N'))$([System.Diagnostics.Process]::GetCurrentProcess().Id)"
    $payload = if ($null -ne $Body) { $Body } else { @{} }
    $bodyHash = Get-NeoSha256Hex (ConvertTo-NeoStableJson $payload)
    $canonical = @(
        ([string]$Method).ToUpperInvariant(),
        $uri.PathAndQuery,
        $timestamp,
        $nonce,
        $bodyHash
    ) -join "`n"

    $Headers["x-neo-timestamp"] = $timestamp
    $Headers["x-neo-nonce"] = $nonce
    $Headers["x-neo-signature"] = Get-NeoHmacSha256Hex -Secret $secret -Text $canonical
}

function Invoke-RmmRequest {
    param(
        [string]$Method,
        [string]$Url,
        [object]$Body = $null,
        [hashtable]$Headers = @{},
        [int]$TimeoutSec = 8
    )
    $security = Read-AgentTransportSecurityConfig
    Assert-RmmTransportPolicy -Url $Url -Security $security
    Add-NeoRequestSignature -Headers $Headers -Method $Method -Url $Url -Body $Body -Security $security

    $params = @{
        Uri = $Url
        Method = $Method
        Headers = $Headers
        TimeoutSec = $TimeoutSec
        ErrorAction = "Stop"
    }
    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 12)
    }
    return Invoke-RestMethod @params
}

function Ensure-RmmRegistration {
    param([object]$Snapshot, [object]$Config)

    $candidateUrls = @()
    if ($Config.ServerUrl) { $candidateUrls += [string]$Config.ServerUrl }
    $candidateUrls += @($Config.ServerUrls)

    foreach ($serverUrl in @($candidateUrls | Where-Object { $_ } | Select-Object -Unique)) {
        $base = ([string]$serverUrl).TrimEnd("/")
        try {
            if (-not [string]::IsNullOrWhiteSpace([string]$Config.ApiKey)) {
                Invoke-RmmRequest -Method "Post" -Url "$base/api/v1/agent/check-in" -Headers @{ "x-api-key" = $Config.ApiKey } -Body @{
                    uuid = $Snapshot.BiosUUID
                    hostname = $Snapshot.ComputerName
                    version = $Global:PRODUCT_VERSION
                    meta = @{ cpu = $Snapshot.CPU; gpu = $Snapshot.GPU; ram_mb = [math]::Round($Snapshot.RAMTotalGB * 1024) }
                } -TimeoutSec 5 | Out-Null
                Save-EndpointSyncState -ServerUrl $base -ApiKey $Config.ApiKey -EnrollmentToken $Config.EnrollmentToken
                return [PSCustomObject]@{ ServerUrl = $base; ApiKey = $Config.ApiKey }
            }

            $headers = @{}
            if (-not [string]::IsNullOrWhiteSpace([string]$Config.EnrollmentToken)) {
                $headers["x-enrollment-token"] = [string]$Config.EnrollmentToken
            }
            $response = Invoke-RmmRequest -Method "Post" -Url "$base/api/v1/agent/register" -Headers $headers -Body @{
                uuid = $Snapshot.BiosUUID
                hostname = $Snapshot.ComputerName
                os = $Snapshot.OS
                cpu = $Snapshot.CPU
                gpu = $Snapshot.GPU
                ram_mb = [math]::Round($Snapshot.RAMTotalGB * 1024)
                version = $Global:PRODUCT_VERSION
            } -TimeoutSec 8
            if ($response.api_key) {
                Save-EndpointSyncState -ServerUrl $base -ApiKey ([string]$response.api_key) -EnrollmentToken $Config.EnrollmentToken
                return [PSCustomObject]@{ ServerUrl = $base; ApiKey = [string]$response.api_key }
            }
        } catch {
            Write-Host "  $($Global:DIM)Endpoint sync unavailable at ${base}: $($_.Exception.Message)$($Global:RESET)"
        }
    }
    return $null
}

function Get-LightTelemetryPayload {
    param([object]$Snapshot, [string]$ActiveCommandId = "")

    $cpuPct = 0
    try { $cpuPct = [math]::Round((Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop).CounterSamples[0].CookedValue, 1) } catch {}
    $memUsedMb = if ($Snapshot.RAMTotalGB -and $Snapshot.RAMFreeGB) { [math]::Round(($Snapshot.RAMTotalGB - $Snapshot.RAMFreeGB) * 1024) } else { $null }
    $proc = Get-Process -ErrorAction SilentlyContinue
    $capabilityCount = 0
    if (Get-Command Get-NeoCapabilityItems -ErrorAction SilentlyContinue) {
        try { $capabilityCount = @(Get-NeoCapabilityItems).Count } catch { $capabilityCount = 0 }
    }

    return @{
        uuid = $Snapshot.BiosUUID
        timestamp = (Get-Date).ToString("o")
        sample_kind = "endpoint_sync"
        active_command_id = $ActiveCommandId
        cpu_pct = $cpuPct
        ram_used_mb = $memUsedMb
        disk_free_gb = $Snapshot.SystemDriveFreeGB
        gpu_pct = 0
        gpu_name = $Snapshot.GPU
        net_rx_kbps = 0
        net_tx_kbps = 0
        handle_count = ($proc | Measure-Object -Property HandleCount -Sum).Sum
        thread_count = ($proc | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
        process_count = @($proc).Count
        cam_active = $false
        mic_active = $false
        host_baseline = @{
            os = @{ name = $Snapshot.OS; version = $Snapshot.OSVersion; build = $Snapshot.Build; architecture = $Snapshot.Architecture }
            hardware = @{ cpu = $Snapshot.CPU; gpu = $Snapshot.GPU; ram_mb = [math]::Round($Snapshot.RAMTotalGB * 1024); manufacturer = $Snapshot.Manufacturer; model = $Snapshot.Model }
        }
        device_info = @{
            hostname = $Snapshot.ComputerName
            bios_uuid = $Snapshot.BiosUUID
            uptime_days = $Snapshot.UptimeDays
            system_drive = $Snapshot.SystemDrive
        }
        neo = @{
            capability_catalog_count = $capabilityCount
            operator_terminal_policy = if ($capabilityCount -gt 0) { "catalog_enforced" } else { "fallback_policy" }
        }
    }
}

function Test-NeoTelemetryFlag {
    param([object]$Config, [string]$Name)
    if ($Config -and $Config.Telemetry -and $null -ne $Config.Telemetry.$Name) {
        try { return [bool]$Config.Telemetry.$Name } catch { return $false }
    }
    return $false
}

function Get-EndpointNetworkInfo {
    $publicIp = ""
    try { $publicIp = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -TimeoutSec 5).ip } catch {}
    $adapters = @()
    try {
        $adapters = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
            [PSCustomObject]@{
                interface = $_.InterfaceAlias
                description = $_.InterfaceDescription
                ipv4 = @($_.IPv4Address | ForEach-Object { $_.IPAddress })
                gateway = @($_.IPv4DefaultGateway | ForEach-Object { $_.NextHop })
                dns = @($_.DNSServer.ServerAddresses)
            }
        })
    } catch {}
    return [PSCustomObject]@{
        public_ip = $publicIp
        adapters = $adapters
        collected_at = (Get-Date).ToString("o")
    }
}

function Invoke-RmmTelemetryDataCommand {
    param([object]$Command, [object]$Config, [object]$Snapshot)
    $cmd = ([string]$Command.cmd).ToUpperInvariant()

    switch ($cmd) {
        "DEVICE_INFO" {
            return @{
                ok = $true
                command = $cmd
                device = @{
                    hostname = $Snapshot.ComputerName
                    os = $Snapshot.OS
                    os_version = $Snapshot.OSVersion
                    build = $Snapshot.Build
                    architecture = $Snapshot.Architecture
                    cpu = $Snapshot.CPU
                    cores = $Snapshot.Cores
                    threads = $Snapshot.Threads
                    ram_total_gb = $Snapshot.RAMTotalGB
                    gpu = $Snapshot.GPU
                    manufacturer = $Snapshot.Manufacturer
                    model = $Snapshot.Model
                    bios = $Snapshot.BIOS
                    bios_uuid = $Snapshot.BiosUUID
                    uptime_days = $Snapshot.UptimeDays
                }
            }
        }
        "IP_ADDRESS" {
            return @{
                ok = $true
                command = $cmd
                network = Get-EndpointNetworkInfo
            }
        }
        "GEOLOCATE" {
            if (-not (Test-NeoTelemetryFlag -Config $Config -Name "collect_approx_location")) {
                return @{
                    ok = $false
                    rejected = $true
                    consent_required = $true
                    command = $cmd
                    reason = "Approximate location telemetry is disabled by endpoint policy."
                }
            }
            return @{
                ok = $true
                command = $cmd
                approximate_only = $true
                network = Get-EndpointNetworkInfo
                note = "Precise GPS/browser geolocation is not collected silently. Public build reports approximate network context only."
            }
        }
        "CAMERA_SNAPSHOT" {
            if (-not (Test-NeoTelemetryFlag -Config $Config -Name "collect_camera_capture")) {
                return @{
                    ok = $false
                    rejected = $true
                    consent_required = $true
                    command = $cmd
                    reason = "Camera capture is disabled by endpoint policy."
                }
            }
            return @{
                ok = $false
                rejected = $true
                add_on_required = $true
                consent_required = $true
                command = $cmd
                reason = "Camera photo requires a local consent UI add-on; silent capture is blocked in the public build."
            }
        }
        "CAMERA_VIDEO" {
            if (-not (Test-NeoTelemetryFlag -Config $Config -Name "collect_camera_capture")) {
                return @{
                    ok = $false
                    rejected = $true
                    consent_required = $true
                    command = $cmd
                    reason = "Camera video is disabled by endpoint policy."
                }
            }
            return @{
                ok = $false
                rejected = $true
                add_on_required = $true
                consent_required = $true
                command = $cmd
                reason = "Camera video requires a local consent UI add-on; silent recording is blocked in the public build."
            }
        }
    }
}

function Get-RmmActionFromCommand {
    param([string]$Command)
    $key = ([string]$Command).ToUpperInvariant()

    if (Get-Command Get-NeoCapabilityByRmmCommand -ErrorAction SilentlyContinue) {
        try {
            $capability = @(Get-NeoCapabilityByRmmCommand -Command $key | Where-Object { $_.local_action } | Select-Object -First 1)[0]
            if ($capability -and -not [string]::IsNullOrWhiteSpace([string]$capability.local_action)) {
                return [string]$capability.local_action
            }
        } catch { Write-Verbose $_.Exception.Message }
    }

    $map = @{
        PING = ""
        OPTIMIZE = "SmartOptimize"
        CLEAN = "CleanAll"
        UPDATES = "Updates"
        PRIVACY = "Privacy"
        POWER = "Power"
        SERVICES = "Services"
        APP_MANAGER = "Apps"
        SYSTEM_REPAIR = "SystemRepair"
        SYSTEM_DIAGNOSTICS = "SystemDiagnostics"
        BACKUP_OPS = "Backup"
        PERFORMANCE = "Performance"
        DEEP_SCAN = "DeepScan"
        SECURITY_SCAN = "Security"
        NETWORK_TEST = "Network"
        THREAT_SCAN = "ThreatMonitor"
        AUTOIMMUNE = "Autoimmune"
        INTEGRITY_SCAN = "IntegrityScan"
        COLLECT = "Collect"
        SYSINFO = "Collect"
        NEOUPDATE = "NeoUpdate"
    }
    if ($map.ContainsKey($key)) { return [string]$map[$key] }
    return ""
}

function Test-OperatorTerminalScript {
    param([string]$ScriptText)
    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return "Script is empty" }
    if ($ScriptText.Length -gt 20000) { return "Script exceeds 20000 characters" }
    $deny = @()
    if (Get-Command Get-NeoOperatorTerminalDenyPatterns -ErrorAction SilentlyContinue) {
        try { $deny = @(Get-NeoOperatorTerminalDenyPatterns) } catch { $deny = @() }
    }
    if ($deny.Count -eq 0) {
        $deny = @(
        '(?i)\bformat\s+[a-z]:',
        '(?i)\bdiskpart\b',
        '(?i)\bcipher\s+/w',
        '(?i)\bbcdedit\b',
        '(?i)\bRemove-Item\b.*\b-Recurse\b.*(C:\\|/)',
        '(?i)\bInvoke-Expression\b',
        '(?i)\bSet-ExecutionPolicy\b'
        )
    }
    foreach ($pattern in $deny) {
        if ($ScriptText -match $pattern) { return "Blocked by operator terminal policy: $pattern" }
    }
    return ""
}

function Invoke-OpenFangTerminalCommand {
    param([object]$Command, [object]$Config)

    if (-not $Config.OperatorTerminalEnabled) {
        throw "OpenFang terminal is disabled on this endpoint"
    }
    $args = $Command.args
    $shell = if ($args.shell) { ([string]$args.shell).ToLowerInvariant() } else { "powershell" }
    $script = [string]$args.script
    $expectedHash = if ($args.script_sha256) { ([string]$args.script_sha256).ToLowerInvariant() } else { "" }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $actualHash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script)) | ForEach-Object { $_.ToString("x2") })
    if ($expectedHash -and $expectedHash -ne $actualHash) { throw "Script SHA-256 mismatch" }

    $policyError = Test-OperatorTerminalScript -ScriptText $script
    if ($policyError) { throw $policyError }

    $workDir = Join-Path $env:ProgramData "NeoOptimize\terminal"
    New-Item -Path $workDir -ItemType Directory -Force | Out-Null
    $ext = if ($shell -eq "cmd") { ".cmd" } else { ".ps1" }
    $scriptPath = Join-Path $workDir ("openfang_{0}{1}" -f ([guid]::NewGuid().ToString("N")), $ext)
    $stdout = "$scriptPath.out"
    $stderr = "$scriptPath.err"
    Set-Content -Path $scriptPath -Value $script -Encoding UTF8

    $exe = if ($shell -eq "cmd") { "$env:SystemRoot\System32\cmd.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
    $arguments = if ($shell -eq "cmd") { "/d /c `"$scriptPath`"" } else { "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" }
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $timeout = if ($args.timeout_seconds) { [int]$args.timeout_seconds } else { 120 }
    if (-not $proc.WaitForExit($timeout * 1000)) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "OpenFang terminal command timed out"
    }

    return @{
        exit_code = $proc.ExitCode
        stdout = if (Test-Path $stdout) { (Get-Content $stdout -Raw -ErrorAction SilentlyContinue) } else { "" }
        stderr = if (Test-Path $stderr) { (Get-Content $stderr -Raw -ErrorAction SilentlyContinue) } else { "" }
        script_sha256 = $actualHash
    }
}

function Invoke-RmmCommand {
    param([object]$Command, [object]$Config)

    $cmd = ([string]$Command.cmd).ToUpperInvariant()
    if ($cmd -eq "PING") { return @{ ok = $true; message = "pong" } }
    if ($cmd -eq "OPENFANG_TERMINAL") { return Invoke-OpenFangTerminalCommand -Command $Command -Config $Config }
    if (@("DEVICE_INFO", "IP_ADDRESS", "GEOLOCATE", "CAMERA_SNAPSHOT", "CAMERA_VIDEO") -contains $cmd) {
        $snapshot = Get-AgentSnapshot
        return Invoke-RmmTelemetryDataCommand -Command $Command -Config $Config -Snapshot $snapshot
    }

    $action = Get-RmmActionFromCommand $cmd
    if ([string]::IsNullOrWhiteSpace($action)) { throw "Unsupported command: $cmd" }

    $engine = Join-Path $PSScriptRoot "NeoOptimize.ps1"
    if (-not (Test-Path $engine)) { throw "NeoOptimize.ps1 not found" }
    $output = & $engine -Action $action -NoPause -AssumeYes 2>&1 | Out-String
    return @{ ok = $true; command = $cmd; action = $action; output = $output.Trim() }
}

function Send-RmmCommandReport {
    param([object]$Connection, [object]$Snapshot, [object]$Command, [string]$Status, [object]$Result)
    try {
        Invoke-RmmRequest -Method "Post" -Url "$($Connection.ServerUrl)/api/v1/agent/report" -Headers @{ "x-api-key" = $Connection.ApiKey } -Body @{
            uuid = $Snapshot.BiosUUID
            cmd_id = $Command.id
            status = $Status
            result = $Result
        } -TimeoutSec 10 | Out-Null
    } catch {
        Write-Host "  $($Global:YELLOW)Command report failed: $($_.Exception.Message)$($Global:RESET)"
    }
}

function Invoke-RmmSyncOnce {
    $config = Read-EndpointSyncConfig
    $snapshot = Get-AgentSnapshot
    $connection = Ensure-RmmRegistration -Snapshot $snapshot -Config $config
    if (-not $connection) { return $false }

    $checkIn = Invoke-RmmRequest -Method "Post" -Url "$($connection.ServerUrl)/api/v1/agent/check-in" -Headers @{ "x-api-key" = $connection.ApiKey } -Body @{
        uuid = $snapshot.BiosUUID
        hostname = $snapshot.ComputerName
        version = $Global:PRODUCT_VERSION
        meta = @{ cpu = $snapshot.CPU; gpu = $snapshot.GPU; ram_mb = [math]::Round($snapshot.RAMTotalGB * 1024) }
    } -TimeoutSec 8

    Invoke-RmmRequest -Method "Post" -Url "$($connection.ServerUrl)/api/v1/agent/telemetry" -Headers @{ "x-api-key" = $connection.ApiKey } -Body (Get-LightTelemetryPayload -Snapshot $snapshot -ActiveCommandId $checkIn.id) -TimeoutSec 8 | Out-Null

    if ($checkIn -and $checkIn.id -and $checkIn.cmd) {
        $status = "success"
        $result = $null
        try {
            $result = Invoke-RmmCommand -Command $checkIn -Config $config
        } catch {
            $status = "failed"
            $result = @{ error = $_.Exception.Message; command = $checkIn.cmd }
        }
        Send-RmmCommandReport -Connection $connection -Snapshot $snapshot -Command $checkIn -Status $status -Result $result
    }

    if (-not $Quiet) { Write-Host "  $($Global:GREEN)Endpoint sync connected: $($connection.ServerUrl)$($Global:RESET)" }
    return $true
}

function Send-RmmTelemetry {
    param([object]$Snapshot)
    try {
        Invoke-RmmSyncOnce | Out-Null
    } catch {
        Write-Host "  $($Global:YELLOW)Failed to sync telemetry to RMM: $($_.Exception.Message)$($Global:RESET)"
    }
}

function Get-StartupEntryCount {
    $paths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )
    $count = 0
    foreach ($path in $paths) {
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            $count += @($props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }).Count
        }
    }
    return $count
}

function Get-PendingRebootReasons {
    $reasons = [System.Collections.Generic.List[string]]::new()
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending") { $reasons.Add("CBS RebootPending") }
    if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired") { $reasons.Add("Windows Update RebootRequired") }
    $sm = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    if ($sm.PendingFileRenameOperations) { $reasons.Add("PendingFileRenameOperations") }
    return $reasons
}

function Get-LastRestorePointDate {
    try {
        $points = Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop |
            Sort-Object CreationTime -Descending
        if ($points) {
            return [System.Management.ManagementDateTimeConverter]::ToDateTime($points[0].CreationTime)
        }
    } catch {}
    return $null
}

function Invoke-AgentAudit {
    $snapshot = Get-AgentSnapshot
    $findings = [System.Collections.Generic.List[object]]::new()
    $t = $Policy.Thresholds

    $freePct = $null
    if ($snapshot.SystemDriveSizeGB -gt 0) {
        $freePct = [math]::Round(($snapshot.SystemDriveFreeGB / $snapshot.SystemDriveSizeGB) * 100, 1)
        if ($freePct -lt [double]$t.DiskCriticalFreePercent) {
            $findings.Add((New-Finding "NEO-DISK-001" "Capacity" "Critical" "System drive hampir penuh" "$($snapshot.SystemDrive) free $freePct% ($($snapshot.SystemDriveFreeGB) GB)" "Jalankan Cleaner, pindahkan data besar, dan cek WinSxS/Windows Update cleanup." $false))
        } elseif ($freePct -lt [double]$t.DiskWarnFreePercent) {
            $findings.Add((New-Finding "NEO-DISK-002" "Capacity" "High" "System drive mulai sempit" "$($snapshot.SystemDrive) free $freePct% ($($snapshot.SystemDriveFreeGB) GB)" "Kosongkan cache, uninstall app besar, atau tambah kapasitas." $false))
        }
    }

    if ($snapshot.RAMTotalGB -gt 0 -and $snapshot.RAMFreeGB -ne $null) {
        $ramFreePct = [math]::Round(($snapshot.RAMFreeGB / $snapshot.RAMTotalGB) * 100, 1)
        if ($ramFreePct -lt [double]$t.RamPressureWarnPercent) {
            $findings.Add((New-Finding "NEO-RAM-001" "Performance" "Medium" "Tekanan RAM tinggi" "RAM free $ramFreePct% ($($snapshot.RAMFreeGB) GB dari $($snapshot.RAMTotalGB) GB)" "Audit startup/process berat sebelum menjalankan optimasi agresif." $false))
        }
    }

    if ($snapshot.UptimeDays -gt [double]$t.UptimeWarnDays) {
        $findings.Add((New-Finding "NEO-UP-001" "Reliability" "Low" "Uptime panjang" "$($snapshot.UptimeDays) hari sejak boot terakhir" "Restart terjadwal dapat menyelesaikan pending update dan memory leak driver." $false))
    }

    $lastRp = Get-LastRestorePointDate
    if (-not $lastRp) {
        $findings.Add((New-Finding "NEO-RP-001" "Recovery" "High" "Restore point tidak ditemukan" "Tidak ada restore point yang bisa dibaca" "Buat restore point sebelum remediation." $true))
    } elseif (((Get-Date) - $lastRp).TotalDays -gt [double]$t.RestorePointWarnDays) {
        $findings.Add((New-Finding "NEO-RP-001" "Recovery" "Medium" "Restore point sudah lama" "Terakhir: $($lastRp.ToString('yyyy-MM-dd HH:mm'))" "Buat restore point baru sebelum perubahan sistem." $true))
    }

    try {
        $fwOff = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
        if ($fwOff.Count -gt 0) {
            $findings.Add((New-Finding "NEO-FW-001" "Security" "High" "Firewall profile nonaktif" ($fwOff.Name -join ", ") "Aktifkan semua Windows Firewall profiles." $true))
        }
    } catch {
        $findings.Add((New-Finding "NEO-FW-002" "Security" "Medium" "Status firewall tidak bisa dibaca" $_.Exception.Message "Jalankan ulang sebagai Administrator di Windows 10/11." $false))
    }

    try {
        $mp = Get-MpComputerStatus -ErrorAction Stop
        if (-not $mp.RealTimeProtectionEnabled) {
            $findings.Add((New-Finding "NEO-DEF-001" "Security" "High" "Defender realtime protection nonaktif" "RealTimeProtectionEnabled=False" "Aktifkan realtime protection." $true))
        }
        if ($mp.AntivirusSignatureLastUpdated) {
            $age = ((Get-Date) - $mp.AntivirusSignatureLastUpdated).TotalDays
            if ($age -gt [double]$t.DefinitionWarnDays) {
                $findings.Add((New-Finding "NEO-DEF-002" "Security" "Medium" "Defender definition lama" "Terakhir update: $($mp.AntivirusSignatureLastUpdated)" "Update Defender signatures." $true))
            }
        }
    } catch {
        $findings.Add((New-Finding "NEO-DEF-003" "Security" "Medium" "Defender status tidak tersedia" $_.Exception.Message "Pastikan Microsoft Defender tersedia atau catat antivirus pihak ketiga." $false))
    }

    try {
        $smb = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smb.EnableSMB1Protocol) {
            $findings.Add((New-Finding "NEO-SMB-001" "Security" "High" "SMBv1 aktif" "EnableSMB1Protocol=True" "Disable SMBv1 untuk mengurangi attack surface." $true))
        }
    } catch {
        $smb1Reg = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" $null
        if ($smb1Reg -eq 1) {
            $findings.Add((New-Finding "NEO-SMB-001" "Security" "High" "SMBv1 aktif via registry" "SMB1=1" "Disable SMBv1 untuk mengurangi attack surface." $true))
        }
    }

    $rdpEnabled = (Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" "fDenyTSConnections" 1) -eq 0
    if ($rdpEnabled) {
        $nla = Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication" 0
        if ($nla -ne 1) {
            $findings.Add((New-Finding "NEO-RDP-001" "Security" "High" "RDP aktif tanpa NLA" "fDenyTSConnections=0, UserAuthentication=$nla" "Aktifkan Network Level Authentication dan enkripsi tinggi." $true))
        } else {
            $findings.Add((New-Finding "NEO-RDP-002" "Exposure" "Info" "RDP aktif dengan NLA" "RDP tersedia" "Pastikan hanya dibuka pada jaringan terpercaya/VPN." $false))
        }
    }

    $criticalServices = @("EventLog", "PlugPlay", "RpcSs", "BFE", "mpssvc", "WinDefend", "Dnscache")
    $badServices = [System.Collections.Generic.List[string]]::new()
    foreach ($svcName in $criticalServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -ne "Running") { $badServices.Add("$svcName=$($svc.Status)") }
    }
    if ($badServices.Count -gt 0) {
        $findings.Add((New-Finding "NEO-SVC-001" "Reliability" "High" "Layanan kritis tidak running" ($badServices -join ", ") "Start dan set Automatic untuk layanan kritis yang aman." $true))
    }

    $wu = Get-CimInstance Win32_Service -Filter "Name='wuauserv'" -ErrorAction SilentlyContinue
    if ($wu -and $wu.StartMode -eq "Disabled") {
        $findings.Add((New-Finding "NEO-WU-001" "Maintenance" "Medium" "Windows Update service disabled" "wuauserv=$($wu.State)/$($wu.StartMode)" "Set Windows Update ke Manual/Notify, bukan Disabled permanen." $true))
    }

    $pagefile = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($pagefile -and -not $pagefile.AutomaticManagedPagefile) {
        $findings.Add((New-Finding "NEO-PF-001" "Performance" "Low" "Pagefile custom/manual" "AutomaticManagedPagefile=False" "Untuk mesin umum, system-managed lebih aman kecuali ada alasan teknis." $false))
    }

    $startupCount = Get-StartupEntryCount
    if ($startupCount -gt [int]$t.StartupWarnCount) {
        $findings.Add((New-Finding "NEO-START-001" "Performance" "Medium" "Startup entries terlalu banyak" "$startupCount entry startup terdeteksi" "Audit startup entry dan nonaktifkan vendor updater yang tidak penting." $false))
    }

    $tempMB = [math]::Round((Get-FolderSizeMB $env:TEMP) + (Get-FolderSizeMB "$env:SystemRoot\Temp"), 2)
    if ($tempMB -gt [double]$t.TempWarnMB) {
        $findings.Add((New-Finding "NEO-TEMP-001" "Capacity" "Low" "Temp files besar" "$tempMB MB di user/system temp" "Jalankan modul Cleaner setelah menutup aplikasi aktif." $false))
    }

    $rebootReasons = Get-PendingRebootReasons
    if ($rebootReasons.Count -gt 0) {
        $findings.Add((New-Finding "NEO-BOOT-001" "Reliability" "Medium" "Pending reboot terdeteksi" ($rebootReasons -join ", ") "Restart pada maintenance window sebelum optimasi lanjutan." $false))
    }

    $impact = ($findings | Measure-Object -Property Impact -Sum).Sum
    if ($null -eq $impact) { $impact = 0 }
    $score = [math]::Max(0, [math]::Min(100, 100 - [int]$impact))
    $grade = if ($score -ge 90) { "A" } elseif ($score -ge 75) { "B" } elseif ($score -ge 60) { "C" } elseif ($score -ge 40) { "D" } else { "E" }

    return [PSCustomObject]@{
        AgentVersion = $Global:PRODUCT_VERSION
        PolicyVersion = $Policy.SchemaVersion
        Profile = $Profile
        Score = $score
        Grade = $grade
        GeneratedAt = Get-Date
        Snapshot = $snapshot
        FindingCount = $findings.Count
        Findings = @($findings | Sort-Object @{Expression="Impact";Descending=$true}, Category, Id)
    }
}

function Export-AgentReport {
    param($Audit)

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $jsonPath = Join-Path $AgentReportDir "AgentAudit_$stamp.json"
    $htmlPath = Join-Path $AgentReportDir "AgentAudit_$stamp.html"

    $Audit | ConvertTo-Json -Depth 8 | Out-File -FilePath $jsonPath -Encoding UTF8 -Force

    $rows = foreach ($f in $Audit.Findings) {
        $sev = ConvertTo-HtmlSafe $f.Severity
        $id = ConvertTo-HtmlSafe $f.Id
        $cat = ConvertTo-HtmlSafe $f.Category
        $title = ConvertTo-HtmlSafe $f.Title
        $evidence = ConvertTo-HtmlSafe $f.Evidence
        $recommendation = ConvertTo-HtmlSafe $f.Recommendation
        "<tr><td><span class='badge $sev'>$sev</span></td><td>$id</td><td>$cat</td><td><strong>$title</strong><br><span class='dim'>$evidence</span></td><td>$recommendation</td></tr>"
    }
    if (-not $rows) {
        $rows = "<tr><td colspan='5'>Tidak ada finding. Sistem terlihat sehat.</td></tr>"
    }

    $safeComputer = ConvertTo-HtmlSafe $Audit.Snapshot.ComputerName
    $sections = @"
<div class='card'>
<h2>Agent Score</h2>
<div class='sysinfo'>
<div class='sysinfo-item'><div class='label'>Score</div><div class='value'>$($Audit.Score)/100 ($($Audit.Grade))</div></div>
<div class='sysinfo-item'><div class='label'>Findings</div><div class='value'>$($Audit.FindingCount)</div></div>
<div class='sysinfo-item'><div class='label'>Computer</div><div class='value'>$safeComputer</div></div>
<div class='sysinfo-item'><div class='label'>Profile</div><div class='value'>$($Audit.Profile)</div></div>
</div>
</div>
<div class='card'>
<h2>Prioritized Findings</h2>
<table style='width:100%;border-collapse:collapse;font-size:.82rem'>
<thead><tr style='background:#21262d'><th style='padding:.5rem;text-align:left'>Severity</th><th style='padding:.5rem;text-align:left'>ID</th><th style='padding:.5rem;text-align:left'>Category</th><th style='padding:.5rem;text-align:left'>Evidence</th><th style='padding:.5rem;text-align:left'>Recommendation</th></tr></thead>
<tbody>$($rows -join '')</tbody>
</table>
</div>
"@
    Export-HtmlReport "Agent Audit Report" $sections $htmlPath | Out-Null

    [PSCustomObject]@{ Json = $jsonPath; Html = $htmlPath }
}

function Invoke-AgentRemediation {
    param($Audit)

    $safeRules = @($Policy.SafeRemediationRuleIds)
    $targets = @($Audit.Findings | Where-Object { $_.CanRemediate -and ($safeRules -contains $_.Id) })
    if ($targets.Count -eq 0) {
        Write-OK "Tidak ada finding yang perlu remediation aman."
        return
    }

    Write-Warn "Remediation aman akan mencoba memperbaiki $($targets.Count) finding."
    if (-not (Confirm-NeoAction "  Lanjutkan remediation aman?" $false)) {
        Write-Skip "Agent remediation"
        return
    }

    New-RestorePoint "NeoOptimize Agent Remediation - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null

    foreach ($finding in $targets) {
        Write-Step "$($finding.Id) - $($finding.Title)"
        switch ($finding.Id) {
            "NEO-RP-001" {
                New-RestorePoint "NeoOptimize Agent Checkpoint - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" | Out-Null
            }
            "NEO-FW-001" {
                Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True -ErrorAction SilentlyContinue
                Write-OK "Firewall profiles enabled"
            }
            "NEO-DEF-001" {
                Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
                Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
                Write-OK "Defender realtime + PUA enabled"
            }
            "NEO-DEF-002" {
                Update-MpSignature -ErrorAction SilentlyContinue
                Write-OK "Defender signature update requested"
            }
            "NEO-SMB-001" {
                Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
                Disable-WindowsOptionalFeature -Online -FeatureName "SMB1Protocol" -NoRestart -ErrorAction SilentlyContinue | Out-Null
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" "SMB1" 0 | Out-Null
                Write-OK "SMBv1 disabled"
            }
            "NEO-RDP-001" {
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "UserAuthentication" 1 | Out-Null
                Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" "MinEncryptionLevel" 3 | Out-Null
                Write-OK "RDP NLA + high encryption enforced"
            }
            "NEO-SVC-001" {
                foreach ($svcName in @("EventLog", "PlugPlay", "RpcSs", "BFE", "mpssvc", "WinDefend", "Dnscache")) {
                    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                    if ($svc) {
                        try {
                            Backup-ServiceState $svcName | Out-Null
                            Set-Service -Name $svcName -StartupType Automatic -ErrorAction SilentlyContinue
                            Start-Service -Name $svcName -ErrorAction SilentlyContinue
                        } catch {}
                    }
                }
                Write-OK "Critical services checked"
            }
            "NEO-WU-001" {
                Backup-ServiceState "wuauserv" | Out-Null
                Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
                Write-OK "Windows Update set to Manual"
            }
        }
    }
}

function Install-AgentTask {
    $taskName = if ($Policy.ScheduledTaskName) { $Policy.ScheduledTaskName } else { "NeoOptimize-Agent-Audit" }
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode SyncLoop -Quiet -NoOpen"
    $action = New-ScheduledTaskAction -Execute $ps -Argument $args
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 3650)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Write-OK "Endpoint sync task terpasang dan berjalan: $taskName"
}

function Uninstall-AgentTask {
    $taskName = if ($Policy.ScheduledTaskName) { $Policy.ScheduledTaskName } else { "NeoOptimize-Agent-Audit" }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-OK "Scheduled task dihapus: $taskName"
}

function Show-AgentStatus {
    $taskName = if ($Policy.ScheduledTaskName) { $Policy.ScheduledTaskName } else { "NeoOptimize-Agent-Audit" }
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
        Write-OK "Agent task: $($task.State), LastRun=$($info.LastRunTime), LastResult=$($info.LastTaskResult)"
    } else {
        Write-Warn "Agent task belum terpasang."
    }
    $latest = Get-ChildItem -Path $AgentReportDir -Filter "AgentAudit_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) {
        Write-Info "Report terakhir: $($latest.FullName)"
    }
}

function Remove-OldAgentReports {
    $days = [int]$Policy.ReportRetentionDays
    if ($days -lt 1) { return }
    Get-ChildItem -Path $AgentReportDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$days) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-AgentBanner
Remove-OldAgentReports

switch ($Mode) {
    "Audit" {
        $audit = Invoke-AgentAudit
        $paths = Export-AgentReport $audit
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "  $($Global:GREEN)$($Global:BOLD)Agent Score: $($audit.Score)/100 ($($audit.Grade))$($Global:RESET)"
            Write-Host "  Findings: $($audit.FindingCount)"
            $audit.Findings | Select-Object -First 8 | ForEach-Object {
                Write-Host "  $($Global:YELLOW)[$($_.Severity)]$($Global:RESET) $($_.Id) - $($_.Title)"
            }
            Write-OK "JSON report: $($paths.Json)"
            Write-OK "HTML report: $($paths.Html)"
        }
        
        # Integrasi Telemetry ke RMM
        if (-not $Quiet) { Write-Host "  Syncing Telemetry to RMM..." }
        Send-RmmTelemetry -Snapshot $audit.Snapshot

        if (-not $NoOpen -and -not $Quiet) {
            Start-Process $paths.Html -ErrorAction SilentlyContinue
        }
    }
    "Remediate" {
        $audit = Invoke-AgentAudit
        Invoke-AgentRemediation $audit
        $post = Invoke-AgentAudit
        $paths = Export-AgentReport $post
        Write-OK "Post-remediation score: $($post.Score)/100 ($($post.Grade))"
        Write-OK "Report: $($paths.Html)"
    }
    "Install" { Install-AgentTask }
    "Uninstall" { Uninstall-AgentTask }
    "Status" { Show-AgentStatus }
    "Sync" { Invoke-RmmSyncOnce | Out-Null }
    "SyncLoop" {
        $config = Read-EndpointSyncConfig
        $interval = [Math]::Max(15, [Math]::Min(300, [int]$config.CheckInIntervalSeconds))
        while ($true) {
            try { Invoke-RmmSyncOnce | Out-Null } catch { Write-Host "Endpoint sync error: $($_.Exception.Message)" }
            Start-Sleep -Seconds $interval
        }
    }
}
