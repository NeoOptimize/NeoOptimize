#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize local AI bootstrap for Ollama.

.DESCRIPTION
    Installs or starts Ollama when available, imports bundled model files, and
    verifies the required NEO models. The installer path and model store are
    deterministic so NEO can work without manual provider configuration.
#>

[CmdletBinding()]
param(
    [switch]$Ensure,
    [switch]$Download,
    [switch]$Install,
    [switch]$PullModel,
    [switch]$PullRequiredModels,
    [switch]$ImportBundledModels,
    [switch]$SkipInstallerDownload,
    [string]$Model = "",
    [string[]]$Models = @("neo-light:latest", "neo:latest", "neo-latest:latest"),
    [string]$DownloadUrl = "https://ollama.com/download/OllamaSetup.exe",
    [string]$InstallerPath = "",
    [string]$BundledModelStore = "",
    [string]$ModelStore = "",
    [switch]$Background,
    [switch]$Silent,
    [switch]$Force
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Script:OllamaSetupSelfPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
    $InstallerPath = Join-Path $Root "tools\OllamaSetup.exe"
}
if ([string]::IsNullOrWhiteSpace($BundledModelStore)) {
    $BundledModelStore = Join-Path $Root "tools\ollama-models\models"
}
if ([string]::IsNullOrWhiteSpace($ModelStore)) {
    $ModelStore = Join-Path $env:ProgramData "NeoOptimize\ollama\models"
}
if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = "neo-light:latest"
}
$LogDir = Join-Path $env:ProgramData "NeoOptimize\logs"
$LogPath = Join-Path $LogDir "NeoOptimize-OllamaSetup.log"

function Write-Step {
    param([string]$Message)
    try {
        if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message) -Encoding UTF8
    } catch {}
    Write-Host "[NeoOptimize Local AI] $Message"
}

function Quote-NativeArgument {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    $escaped = $Value -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Resolve-PowerShellExe {
    foreach ($candidate in @(
        (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"),
        "powershell.exe",
        "powershell"
    )) {
        try {
            $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            if (Test-Path $candidate) { return $candidate }
        } catch {}
    }
    return "powershell.exe"
}

function Start-NeoOllamaSetupBackground {
    $self = $Script:OllamaSetupSelfPath
    if ([string]::IsNullOrWhiteSpace($self) -or -not (Test-Path $self)) {
        throw "Cannot resolve Ollama setup helper path for background launch."
    }

    $argumentItems = New-Object System.Collections.Generic.List[string]
    foreach ($item in @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", $self)) {
        $argumentItems.Add($item) | Out-Null
    }

    foreach ($key in @($PSBoundParameters.Keys | Sort-Object)) {
        if ($key -eq "Background") { continue }
        $value = $PSBoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $argumentItems.Add("-$key") | Out-Null }
            continue
        }
        if ($null -eq $value) { continue }
        if ($value -is [Array]) {
            foreach ($entry in @($value)) {
                $argumentItems.Add("-$key") | Out-Null
                $argumentItems.Add([string]$entry) | Out-Null
            }
            continue
        }
        $argumentItems.Add("-$key") | Out-Null
        $argumentItems.Add([string]$value) | Out-Null
    }

    if (-not $PSBoundParameters.ContainsKey("Silent")) { $argumentItems.Add("-Silent") | Out-Null }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Resolve-PowerShellExe
    $psi.Arguments = (@($argumentItems | ForEach-Object { Quote-NativeArgument ([string]$_) }) -join " ")
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to launch Ollama setup background worker." }
    Write-Step "Background Ollama setup worker started. PID=$($proc.Id). Log=$LogPath"
    return $proc.Id
}

if ($Background) {
    Write-Step "Queuing NeoOptimize Local AI setup in the background."
    Start-NeoOllamaSetupBackground | Out-Null
    Write-Step "NeoOptimize Local AI setup is running in the background. Installer/UI can continue."
    return
}

function Start-HiddenProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$Arguments = "",
        [string]$WorkingDirectory = $Root,
        [int]$TimeoutSeconds = 0,
        [switch]$NoWait
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    Write-Step "Starting hidden process: $FilePath $Arguments"
    if (-not $proc.Start()) { throw "Failed to start $FilePath" }
    if ($NoWait) { return $proc }

    if ($TimeoutSeconds -gt 0) {
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch {}
            throw "$FilePath timed out after $TimeoutSeconds seconds"
        }
    } else {
        $proc.WaitForExit()
    }
    Write-Step "Process exit code: $($proc.ExitCode)"
    return [int]$proc.ExitCode
}

function Normalize-ModelName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    $trimmed = $Name.Trim()
    if ($trimmed -eq "neo-latest") { return "neo-latest:latest" }
    if ($trimmed -eq "neo-light") { return "neo-light:latest" }
    if ($trimmed -eq "neo") { return "neo:latest" }
    return $trimmed
}

function Get-RequiredModels {
    $normalized = @()
    foreach ($item in $Models) {
        $name = Normalize-ModelName $item
        if (-not [string]::IsNullOrWhiteSpace($name) -and $normalized -notcontains $name) {
            $normalized += $name
        }
    }
    return $normalized
}

function Test-OllamaReady {
    try {
        $tags = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 4
        return [PSCustomObject]@{
            ready = $true
            models = @($tags.models | ForEach-Object { $_.name })
        }
    } catch {
        return [PSCustomObject]@{
            ready = $false
            models = @()
            error = $_.Exception.Message
        }
    }
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Resolve-OllamaExe {
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        (Join-Path $env:ProgramFiles "Ollama\ollama.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "Ollama\ollama.exe")
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) { return $candidate }
    }
    return ""
}

function Test-InstallerSignature {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $signature = Get-AuthenticodeSignature -FilePath $Path
        if ($signature.Status -ne "Valid") { return $false }
        $subject = [string]$signature.SignerCertificate.Subject
        return ($subject -match "Ollama|Code Signing|Developer ID")
    } catch {
        return $false
    }
}

function Set-OllamaModelStore {
    New-Item -Path $ModelStore -ItemType Directory -Force | Out-Null
    [Environment]::SetEnvironmentVariable("OLLAMA_MODELS", $ModelStore, "Machine")
    $env:OLLAMA_MODELS = $ModelStore
    Write-Step "OLLAMA_MODELS=$ModelStore"
}

function Download-OllamaInstaller {
    if ($SkipInstallerDownload) {
        Write-Step "Installer download skipped by policy."
        return
    }
    New-Item -Path (Split-Path -Parent $InstallerPath) -ItemType Directory -Force | Out-Null
    $tmp = "$InstallerPath.download"
    if ((Test-Path $InstallerPath) -and -not $Force) {
        Write-Step "Installer already exists: $InstallerPath"
        Write-Step "SHA-256: $(Get-FileSha256 $InstallerPath)"
        return
    }

    Write-Step "Downloading official Ollama installer..."
    Write-Step $DownloadUrl
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $tmp -UseBasicParsing
    Move-Item -Path $tmp -Destination $InstallerPath -Force
    $hash = Get-FileSha256 $InstallerPath
    Set-Content -Path "$InstallerPath.sha256" -Value "$hash  OllamaSetup.exe" -Encoding ASCII
    Write-Step "Downloaded: $InstallerPath"
    Write-Step "SHA-256: $hash"
}

function Install-Ollama {
    if (-not (Test-Path $InstallerPath)) {
        if ($SkipInstallerDownload) {
            Write-Step "Ollama installer is not bundled and download is disabled. Skipping runtime install."
            return
        }
        Download-OllamaInstaller
    }

    if (-not (Test-Path $InstallerPath)) {
        throw "Ollama installer not found: $InstallerPath"
    }

    $hash = Get-FileSha256 $InstallerPath
    Write-Step "Installer: $InstallerPath"
    Write-Step "SHA-256: $hash"
    if (-not (Test-InstallerSignature $InstallerPath)) {
        Write-Step "Authenticode signature could not be validated in this environment."
        if (-not $Force) {
            throw "Installer signature not valid/verified. Use -Force to install anyway."
        }
    }

    $installerArgs = if ($Silent) { "/S" } else { "" }
    Write-Step "Launching Ollama installer with no console window."
    $exitCode = Start-HiddenProcess -FilePath $InstallerPath -ArgumentList $installerArgs -TimeoutSeconds 1800
    Write-Step "Ollama installer exited with code $exitCode."
}

function Start-OllamaServer {
    $status = Test-OllamaReady
    if ($status.ready) { return $true }

    $ollamaExe = Resolve-OllamaExe
    if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
        Write-Step "ollama.exe not found."
        return $false
    }

    Write-Step "Starting Ollama API."
    $existing = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^ollama(\.exe)?$" -or $_.CommandLine -match "ollama.*serve" }
    if (-not $existing) {
        Start-HiddenProcess -FilePath $ollamaExe -ArgumentList "serve" -NoWait | Out-Null
    }

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $status = Test-OllamaReady
        if ($status.ready) { return $true }
    }
    return $false
}

function Import-BundledOllamaModels {
    if (-not (Test-Path $BundledModelStore)) {
        Write-Step "No bundled model store found: $BundledModelStore"
        return $false
    }

    Set-OllamaModelStore
    Write-Step "Importing bundled Ollama models."
    $manifests = Join-Path $BundledModelStore "manifests"
    $blobs = Join-Path $BundledModelStore "blobs"
    if (Test-Path $manifests) {
        Copy-Item -Path $manifests -Destination $ModelStore -Recurse -Force
    }
    if (Test-Path $blobs) {
        Copy-Item -Path $blobs -Destination $ModelStore -Recurse -Force
    }
    return $true
}

function Pull-OllamaModel {
    param([string]$Name)

    $ollamaExe = Resolve-OllamaExe
    if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
        throw "ollama.exe not found after install."
    }

    Set-OllamaModelStore
    Write-Step "Pulling model: $Name"
    $exitCode = Start-HiddenProcess -FilePath $ollamaExe -ArgumentList ("pull {0}" -f (Quote-NativeArgument $Name)) -TimeoutSeconds 7200
    if ($exitCode -ne 0) { throw "ollama pull failed for $Name with exit code $exitCode" }
}

function Get-NeoModelRecipe {
    param([string]$Name)
    switch ($Name.ToLowerInvariant()) {
        "neo-light:latest" {
            return [PSCustomObject]@{
                Base = "qwen2.5:0.5b"
                Role = "fast maintenance triage"
                Temperature = "0.2"
            }
        }
        "neo:latest" {
            return [PSCustomObject]@{
                Base = "qwen2.5:1.5b"
                Role = "deeper Windows optimization reasoning"
                Temperature = "0.2"
            }
        }
        "neo-latest:latest" {
            return [PSCustomObject]@{
                Base = "neo:latest"
                Role = "compatibility alias for neo latest"
                Temperature = "0.2"
            }
        }
        default { return $null }
    }
}

function New-NeoModelAlias {
    param([string]$Name)

    $ollamaExe = Resolve-OllamaExe
    if ([string]::IsNullOrWhiteSpace($ollamaExe)) {
        throw "ollama.exe not found after install."
    }

    $recipe = Get-NeoModelRecipe -Name $Name
    if ($null -eq $recipe) { throw "No local NeoOptimize model recipe for $Name" }

    Set-OllamaModelStore
    $status = Test-OllamaReady
    $available = @($status.models)
    if ($available -notcontains $recipe.Base) {
        if ($recipe.Base -eq "neo:latest") {
            New-NeoModelAlias -Name "neo:latest"
        } else {
            Write-Step "Pulling base model for ${Name}: $($recipe.Base)"
            $baseExit = Start-HiddenProcess -FilePath $ollamaExe -ArgumentList ("pull {0}" -f (Quote-NativeArgument $recipe.Base)) -TimeoutSeconds 7200
            if ($baseExit -ne 0) { throw "ollama pull failed for base model $($recipe.Base) with exit code $baseExit" }
        }
    }

    $modelfileDir = Join-Path $env:ProgramData "NeoOptimize\ollama\modelfiles"
    New-Item -Path $modelfileDir -ItemType Directory -Force | Out-Null
    $safeName = ($Name -replace '[^A-Za-z0-9_.-]', '_')
    $modelfile = Join-Path $modelfileDir "$safeName.Modelfile"
    $content = @"
FROM $($recipe.Base)
PARAMETER temperature $($recipe.Temperature)
PARAMETER num_ctx 4096
SYSTEM """
You are NEO, the local NeoOptimize assistant. You help with Windows maintenance, optimization, diagnostics, privacy review, update repair, local AI setup, RMM readiness checks, and rollback-first safety planning. Keep answers concise, evidence-driven, and operator-approved. Never lock camera, microphone, or location permissions behind organization policy.
"""
"@
    Set-Content -Path $modelfile -Value $content -Encoding UTF8
    Write-Step "Creating local Ollama model $Name from $($recipe.Base) for $($recipe.Role)."
    $createArgs = "create {0} -f {1}" -f (Quote-NativeArgument $Name), (Quote-NativeArgument $modelfile)
    $createExit = Start-HiddenProcess -FilePath $ollamaExe -ArgumentList $createArgs -TimeoutSeconds 1800
    if ($createExit -ne 0) { throw "ollama create failed for $Name with exit code $createExit" }
}

function Ensure-RequiredModels {
    $required = @(Get-RequiredModels)
    if ($required.Count -eq 0) { return }

    Set-OllamaModelStore
    if ($ImportBundledModels -or $Ensure) {
        Import-BundledOllamaModels | Out-Null
    }
    $serverStarted = Start-OllamaServer

    $status = Test-OllamaReady
    $available = @($status.models)
    foreach ($name in $required) {
        if ($available -contains $name) {
            Write-Step "Model ready: $name"
            continue
        }
        if (-not $serverStarted -and -not (Resolve-OllamaExe)) {
            Write-Step "Model pending until Ollama runtime is installed: $name"
            continue
        }
        if ($PullRequiredModels -or $PullModel) {
            try {
                Pull-OllamaModel -Name $name
            } catch {
                Write-Step "Direct pull failed for ${name}: $($_.Exception.Message)"
                try {
                    New-NeoModelAlias -Name $name
                } catch {
                    Write-Step "Model setup deferred for ${name}: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Step "Model missing: $name"
        }
    }
}

Write-Step "Status before setup:"
$status = Test-OllamaReady
Write-Step "Ollama ready: $($status.ready)"
if ($status.models.Count -gt 0) {
    Write-Step "Models: $((@($status.models) | Select-Object -First 8) -join ', ')"
}

if ($Ensure) {
    Set-OllamaModelStore
    if (-not (Resolve-OllamaExe)) {
        if ((Test-Path $InstallerPath) -or -not $SkipInstallerDownload) {
            Install-Ollama
        } else {
            Write-Step "Ollama runtime not available. Installer will continue; Local AI is deferred."
        }
    }
    Ensure-RequiredModels
} else {
    if ($Download) { Download-OllamaInstaller }
    if ($Install) { Install-Ollama }
    if ($ImportBundledModels) { Import-BundledOllamaModels | Out-Null }
    if ($PullModel) { Pull-OllamaModel -Name (Normalize-ModelName $Model) }
    if ($PullRequiredModels) { Ensure-RequiredModels }
}

$status = Test-OllamaReady
Write-Step "Final status: $($status.ready)"
if ($status.models.Count -gt 0) {
    Write-Step "Available models: $((@($status.models) | Select-Object -First 12) -join ', ')"
} else {
    Write-Step "No local model detected. NEO will use NeoCore fallback until Ollama is available."
}
