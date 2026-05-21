param(
    [ValidateSet("Scan", "Check", "Update", "Repair")]
    [string]$Mode = "Update",
    [string]$ServerUrl = "",
    [string]$Email = "",
    [switch]$ForceRepair,
    [switch]$AssumeYes
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:SecureRoot = Join-Path $env:ProgramData "NeoOptimize\SecureUpdate"
$Script:BaselinePath = Join-Path $Script:SecureRoot "installed_integrity.json"
$Script:ManifestPath = Join-Path $Script:SecureRoot "last_update_manifest.json"

function Write-NeoLine {
    param([string]$Message, [string]$Color = "Gray")
    Write-Host "[NeoUpdate] $Message" -ForegroundColor $Color
}

function ConvertFrom-NeoSecureString {
    param([Security.SecureString]$Secure)
    if (-not $Secure) { return "" }
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

function Read-NeoRmmConfig {
    $path = Join-Path $Script:Root "config\NeoOptimize.RMM.json"
    if (-not (Test-Path $path)) {
        return [PSCustomObject]@{
            candidate_server_urls = @("http://192.168.122.1:3000", "http://127.0.0.1:3000")
            auth = [PSCustomObject]@{ email = ""; password = "" }
        }
    }
    try { return Get-Content -Path $path -Raw | ConvertFrom-Json } catch { return $null }
}

function Invoke-NeoJson {
    param(
        [string]$Url,
        [string]$Method = "Get",
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSec = 15
    )
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) { $headers["Authorization"] = "Bearer $Token" }
    $params = @{ Uri = $Url; Method = $Method; Headers = $headers; TimeoutSec = $TimeoutSec; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 8)
    }
    Invoke-RestMethod @params
}

function Get-NeoServerUrl {
    param($Config, [string]$Preferred)
    if (-not [string]::IsNullOrWhiteSpace($Preferred)) { return $Preferred.TrimEnd("/") }
    foreach ($url in @($Config.candidate_server_urls)) {
        if ([string]::IsNullOrWhiteSpace([string]$url)) { continue }
        $base = ([string]$url).TrimEnd("/")
        try {
            $health = Invoke-NeoJson -Url ($base + "/health") -TimeoutSec 3
            if ($health.status -eq "ok") { return $base }
        } catch { Write-Verbose $_.Exception.Message }
    }
    throw "NeoOptimize RMM server is not reachable."
}

function Get-NeoUpdateCredential {
    param($Config, [string]$DefaultEmail)
    $mail = $DefaultEmail
    if ([string]::IsNullOrWhiteSpace($mail) -and $Config.auth -and $Config.auth.email) {
        $mail = [string]$Config.auth.email
    }
    if ([string]::IsNullOrWhiteSpace($mail)) {
        $mail = Read-Host "NeoOptimize update email"
    }

    $plain = ""
    if ($Config.auth -and -not [string]::IsNullOrWhiteSpace([string]$Config.auth.password)) {
        $plain = [string]$Config.auth.password
    }
    if ([string]::IsNullOrWhiteSpace($plain)) {
        $secure = Read-Host "NeoOptimize update password" -AsSecureString
        $plain = ConvertFrom-NeoSecureString $secure
    }
    if ([string]::IsNullOrWhiteSpace($mail) -or [string]::IsNullOrWhiteSpace($plain)) {
        throw "Update credentials are required."
    }
    return @{ email = $mail; password = $plain }
}

function New-NeoUpdateSession {
    param([string]$BaseUrl, [hashtable]$Credential)
    $session = Invoke-NeoJson -Url ($BaseUrl + "/api/v1/update/session") -Method "Post" -Body $Credential -TimeoutSec 15
    if ([string]::IsNullOrWhiteSpace([string]$session.token)) { throw "RMM did not return an update token." }
    return $session
}

function Get-NeoUpdateManifest {
    param([string]$BaseUrl, [string]$Token, [string]$ManifestPath = "/downloads/neooptimize/manifest")
    $url = if ($ManifestPath -match "^https?://") { $ManifestPath } else { $BaseUrl.TrimEnd("/") + "/" + $ManifestPath.TrimStart("/") }
    $manifest = Invoke-NeoJson -Url $url -Token $Token -TimeoutSec 15
    if ([string]::IsNullOrWhiteSpace([string]$manifest.sha256)) { throw "Update manifest is missing SHA-256." }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.installer_url) -and [string]::IsNullOrWhiteSpace([string]$manifest.url)) {
        throw "Update manifest is missing installer URL."
    }
    return $manifest
}

function Get-NeoCriticalFiles {
    $rels = @(
        "program\NeoOptimize.exe",
        "program\NeoOptimize.UI.ps1",
        "program\NeoOptimize.ps1",
        "program\NeoOptimize.UpdateManager.ps1",
        "program\NeoOptimize.AIAgent.ps1",
        "program\NeoOptimize.Cloud.ps1",
        "program\NeoOptimize.VoiceCommand.ps1",
        "program\signing.pub.pem",
        "program\modules\14_IntegrityScan.ps1",
        "program\modules\17_NeoOptimizeUpdate.ps1",
        "agent\NeoOptimize.Agent.exe",
        "agent\signing.pub.pem"
    )
    $installRoot = if ((Split-Path -Leaf $Script:Root) -ieq "program") { Split-Path -Parent $Script:Root } else { $Script:Root }
    foreach ($rel in $rels) {
        $short = $rel -replace "^program\\", ""
        $candidates = @(
            (Join-Path $installRoot $rel),
            (Join-Path $Script:Root $short),
            (Join-Path $Script:Root $rel)
        )
        $path = @($candidates | Select-Object -Unique | Where-Object { Test-Path $_ } | Select-Object -First 1)
        if ($path.Count -eq 0) { $path = @($candidates[0]) }
        [PSCustomObject]@{ relative_path = $rel; path = [string]$path[0] }
    }
}

function Invoke-NeoIntegrityScan {
    if (-not (Test-Path $Script:SecureRoot)) { New-Item -Path $Script:SecureRoot -ItemType Directory -Force | Out-Null }
    $baseline = $null
    if (Test-Path $Script:BaselinePath) {
        try { $baseline = Get-Content -Path $Script:BaselinePath -Raw | ConvertFrom-Json } catch { $baseline = $null }
    }

    $baselineMap = @{}
    if ($baseline -and $baseline.files) {
        foreach ($item in @($baseline.files)) { $baselineMap[[string]$item.relative_path] = [string]$item.sha256 }
    }

    $results = foreach ($item in Get-NeoCriticalFiles) {
        $exists = Test-Path $item.path
        $hash = if ($exists) { (Get-FileHash -Path $item.path -Algorithm SHA256).Hash.ToUpperInvariant() } else { "" }
        $expected = if ($baselineMap.ContainsKey([string]$item.relative_path)) { $baselineMap[[string]$item.relative_path].ToUpperInvariant() } else { "" }
        $status = if (-not $exists) { "missing" } elseif ($expected -and $hash -ne $expected) { "tampered" } else { "ok" }
        [PSCustomObject]@{
            relative_path = $item.relative_path
            path = $item.path
            exists = $exists
            sha256 = $hash
            expected_sha256 = $expected
            status = $status
        }
    }

    $issues = @($results | Where-Object { $_.status -ne "ok" })
    if (-not $baseline) {
        $baselineData = [PSCustomObject]@{
            created_at = (Get-Date).ToUniversalTime().ToString("o")
            files = @($results | Where-Object { $_.exists } | Select-Object relative_path, sha256)
        }
        $baselineData | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:BaselinePath -Encoding UTF8
    }

    return [PSCustomObject]@{
        scanned_at = (Get-Date).ToUniversalTime().ToString("o")
        baseline_path = $Script:BaselinePath
        baseline_created = (-not [bool]$baseline)
        issues = $issues
        files = @($results)
        healthy = ($issues.Count -eq 0)
    }
}

function Save-NeoIntegrityBaseline {
    $scan = Invoke-NeoIntegrityScan
    $baselineData = [PSCustomObject]@{
        created_at = (Get-Date).ToUniversalTime().ToString("o")
        files = @($scan.files | Where-Object { $_.exists } | Select-Object relative_path, sha256)
    }
    $baselineData | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:BaselinePath -Encoding UTF8
}

function Save-NeoManifest {
    param($Manifest)
    if (-not (Test-Path $Script:SecureRoot)) { New-Item -Path $Script:SecureRoot -ItemType Directory -Force | Out-Null }
    $safe = $Manifest | Select-Object * -ExcludeProperty update_token
    $safe | ConvertTo-Json -Depth 10 | Set-Content -Path $Script:ManifestPath -Encoding UTF8
}

function Download-NeoInstaller {
    param([string]$BaseUrl, $Manifest, [string]$Token)
    $installerUrl = if ($Manifest.installer_url) { [string]$Manifest.installer_url } else { [string]$Manifest.url }
    if ($installerUrl -notmatch "^https?://") { $installerUrl = $BaseUrl.TrimEnd("/") + "/" + $installerUrl.TrimStart("/") }
    if ($installerUrl -notmatch "^https?://") { throw "Installer URL must be http or https." }
    $uri = [Uri]$installerUrl
    if ($uri.Scheme -eq "http" -and $uri.Host -notin @("127.0.0.1", "localhost", "192.168.122.1")) {
        throw "Secure update requires HTTPS for non-lab installer URLs."
    }

    $expected = ([string]$Manifest.installer_sha256)
    if ([string]::IsNullOrWhiteSpace($expected)) { $expected = [string]$Manifest.sha256 }
    if ([string]::IsNullOrWhiteSpace($expected)) { throw "Installer SHA-256 is required." }
    $expected = $expected.ToUpperInvariant()

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $work = Join-Path $Script:SecureRoot $stamp
    New-Item -Path $work -ItemType Directory -Force | Out-Null
    $downloadPath = Join-Path $work "NeoOptimize.exe"
    $headers = @{ Authorization = "Bearer $Token" }
    Invoke-WebRequest -Uri $installerUrl -Headers $headers -OutFile $downloadPath -UseBasicParsing -TimeoutSec 120
    $actual = (Get-FileHash -Path $downloadPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actual -ne $expected) {
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
        throw "Installer SHA-256 mismatch. Expected $expected, got $actual."
    }
    return $downloadPath
}

function Start-NeoRepairInstaller {
    param([string]$InstallerPath, $Manifest)
    $installerArgs = if ($Manifest.repair -and $Manifest.repair.repair_args) { [string]$Manifest.repair.repair_args } elseif ($Manifest.silent_args) { [string]$Manifest.silent_args } else { "/S" }
    if ($installerArgs -notmatch '^[A-Za-z0-9\s/:\-_.=]+$') { throw "Installer arguments contain unsupported characters." }
    $runnerPath = Join-Path $Script:SecureRoot "NeoOptimize_UpdateRepair.ps1"
    $logPath = Join-Path $Script:SecureRoot ("NeoOptimize_UpdateRepair_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    $runner = @"
`$ErrorActionPreference = "Stop"
Start-Transcript -Path '$($logPath -replace "'", "''")' -Append -Force | Out-Null
try {
    Start-Process -FilePath '$($InstallerPath -replace "'", "''")' -ArgumentList '$($installerArgs -replace "'", "''")' -Wait -WindowStyle Minimized
} finally {
    try { Stop-Transcript | Out-Null } catch { Write-Verbose $_.Exception.Message }
}
"@
    Set-Content -Path $runnerPath -Value $runner -Encoding UTF8
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$runnerPath`"" -WindowStyle Minimized
    return [PSCustomObject]@{ queued = $true; runner = $runnerPath; log = $logPath; installer = $InstallerPath; args = $installerArgs }
}

function Invoke-NeoSecureUpdate {
    param([switch]$RepairOnly)
    $config = Read-NeoRmmConfig
    $base = Get-NeoServerUrl -Config $config -Preferred $ServerUrl
    $credential = Get-NeoUpdateCredential -Config $config -DefaultEmail $Email
    Write-NeoLine "Authenticating secure update session..." "Cyan"
    $session = New-NeoUpdateSession -BaseUrl $base -Credential $credential
    Write-NeoLine "Fetching signed update manifest..." "Cyan"
    $manifest = Get-NeoUpdateManifest -BaseUrl $base -Token ([string]$session.token) -ManifestPath ([string]$session.manifest_url)
    Save-NeoManifest $manifest

    Write-NeoLine "Scanning NeoOptimize program integrity..." "Cyan"
    $scan = Invoke-NeoIntegrityScan
    if ($scan.healthy -and -not $ForceRepair -and -not $RepairOnly) {
        Write-NeoLine "Integrity scan clean. Update package will still be verified before install." "Green"
    } elseif (-not $scan.healthy) {
        Write-NeoLine ("Integrity issues detected: {0}" -f $scan.issues.Count) "Yellow"
    }

    if (-not $AssumeYes) {
        $answer = Read-Host "Download verified installer and run NeoOptimize repair/update now? [y/N]"
        if ($answer -notmatch '^(y|yes)$') { throw "Update cancelled by user." }
    }

    Write-NeoLine "Downloading installer through credential-protected channel..." "Cyan"
    $installer = Download-NeoInstaller -BaseUrl $base -Manifest $manifest -Token ([string]$session.token)
    Write-NeoLine "SHA-256 verified. Queueing repair/update runner..." "Green"
    $result = Start-NeoRepairInstaller -InstallerPath $installer -Manifest $manifest
    Write-NeoLine "Repair/update queued. Log: $($result.log)" "Green"
    return $result
}

try {
    switch ($Mode) {
        "Scan" {
            $scan = Invoke-NeoIntegrityScan
            $scan | ConvertTo-Json -Depth 8
            if (-not $scan.healthy) { exit 2 }
        }
        "Check" {
            $config = Read-NeoRmmConfig
            $base = Get-NeoServerUrl -Config $config -Preferred $ServerUrl
            $credential = Get-NeoUpdateCredential -Config $config -DefaultEmail $Email
            $session = New-NeoUpdateSession -BaseUrl $base -Credential $credential
            $manifest = Get-NeoUpdateManifest -BaseUrl $base -Token ([string]$session.token) -ManifestPath ([string]$session.manifest_url)
            Save-NeoManifest $manifest
            $manifest | Select-Object schema_version, update_id, version, release_channel, bytes, sha256, requires_credentials, expires_at | ConvertTo-Json -Depth 4
        }
        "Repair" {
            Invoke-NeoSecureUpdate -RepairOnly | ConvertTo-Json -Depth 6
        }
        "Update" {
            $scan = Invoke-NeoIntegrityScan
            if (-not $scan.healthy -or $ForceRepair) {
                Write-NeoLine "Auto repair will run because integrity is not clean or ForceRepair was requested." "Yellow"
            }
            Invoke-NeoSecureUpdate | ConvertTo-Json -Depth 6
        }
    }
} catch {
    Write-NeoLine $_.Exception.Message "Red"
    exit 1
}
