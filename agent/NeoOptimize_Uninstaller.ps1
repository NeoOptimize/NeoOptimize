#Requires -RunAsAdministrator
param(
    [string]$InstallDir = "$env:ProgramFiles\NeoOptimize\Agent"
)

$ErrorActionPreference = "Continue"
$ServiceName = "NeoOptimize RMM Agent"

function Get-NeoBiosUuid {
    try {
        $uuid = (Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop).UUID
        if ($uuid) { return [string]$uuid }
    } catch {}

    try {
        $uuid = (Get-WmiObject -Class Win32_ComputerSystemProduct -ErrorAction Stop).UUID
        if ($uuid) { return [string]$uuid }
    } catch {}

    return $env:COMPUTERNAME
}

function Get-NeoConfigValue {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Name
    )

    if ($Config.PSObject.Properties.Name -contains $Name -and $Config.$Name) {
        return [string]$Config.$Name
    }

    if ($Config.Agent -and $Config.Agent.PSObject.Properties.Name -contains $Name -and $Config.Agent.$Name) {
        return [string]$Config.Agent.$Name
    }

    return ""
}

function Send-NeoUninstallEvent {
    param([string]$InstallDir)

    $configPath = Join-Path $InstallDir "appsettings.json"
    if (-not (Test-Path $configPath)) {
        Write-Host "[!] RMM config not found; uninstall event skipped."
        return
    }

    try {
        $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
        $serverUrl = (Get-NeoConfigValue -Config $config -Name "ServerUrl").TrimEnd("/")
        $apiKey = Get-NeoConfigValue -Config $config -Name "ApiKey"

        if ([string]::IsNullOrWhiteSpace($serverUrl) -or
            [string]::IsNullOrWhiteSpace($apiKey) -or
            $apiKey -notmatch "^[0-9a-fA-F-]{36}$") {
            Write-Host "[!] RMM credentials incomplete; uninstall event skipped."
            return
        }

        $body = @{
            u = Get-NeoBiosUuid
            h = $env:COMPUTERNAME
            v = "1.0"
            reason = "user_uninstall"
            uninstall_id = [guid]::NewGuid().ToString()
        } | ConvertTo-Json -Depth 4

        $headers = @{ "x-api-key" = $apiKey }
        $uri = "$serverUrl/api/v1/agent/uninstall"
        Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $body -ContentType "application/json" -TimeoutSec 8 | Out-Null
        Write-Host "[+] RMM uninstall event sent."
    } catch {
        Write-Host "[!] RMM uninstall event failed: $($_.Exception.Message)"
    }
}

Write-Host "[+] Uninstalling NeoOptimize RMM Agent"
Send-NeoUninstallEvent -InstallDir $InstallDir

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

if (Test-Path $InstallDir) {
    icacls $InstallDir /reset /T /C | Out-Null
    Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "[+] NeoOptimize RMM Agent removed."
