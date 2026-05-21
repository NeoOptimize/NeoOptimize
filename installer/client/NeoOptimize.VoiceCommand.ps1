#Requires -Version 5.1
<#
.SYNOPSIS
    Voice command bridge for NeoOptimize.

.DESCRIPTION
    Uses the Windows System.Speech recognizer when available, then maps a
    short authorized spoken command to a safe NeoOptimize action.
#>

param(
    [int]$ListenSeconds = 8,
    [switch]$NoExecute
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $Root "config\NeoOptimize.ModelAgent.json"
$EnginePath = Join-Path $Root "NeoOptimize.ps1"

function Read-VoiceConfig {
    $fallback = [PSCustomObject]@{
        enabled = $true
        language = "id-ID"
        wake_phrase = "neo optimize"
        mode = "push_to_talk"
    }
    if (-not (Test-Path $ConfigPath)) { return $fallback }
    try {
        $cfg = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        if ($cfg.voice) { return $cfg.voice }
    } catch {}
    return $fallback
}

function Get-PowerShellExe {
    $ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $ps) { return $ps }
    return "powershell.exe"
}

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Resolve-VoiceCulture {
    param([string]$Language)
    try {
        return [System.Globalization.CultureInfo]::new($Language)
    } catch {
        return [System.Globalization.CultureInfo]::CurrentCulture
    }
}

function Get-NeoVoiceAction {
    param([string]$Text)
    $text = ($Text -replace "[^\p{L}\p{Nd}\s-]", " ").ToLowerInvariant()
    $rules = @(
        @{ Pattern = "doctor|dokter|health|sehat|analisa|analyze|diagnostic"; Action = "AIPlan"; Label = "AI Doctor" },
        @{ Pattern = "model|provider|api"; Action = "AIProviders"; Label = "AI Providers" },
        @{ Pattern = "clean|bersih|junk|cache"; Action = "Cleaner"; Label = "Cleaner" },
        @{ Pattern = "optimize|optimasi|boost|cepat"; Action = "SmartOptimize"; Label = "Smart Optimize" },
        @{ Pattern = "disk|storage|drive|penyimpanan"; Action = "DiskStatus"; Label = "Disk Status" },
        @{ Pattern = "network|jaringan|internet|wifi"; Action = "Network"; Label = "Network" },
        @{ Pattern = "security|aman|defender|firewall"; Action = "Security"; Label = "Security" },
        @{ Pattern = "update aplikasi|neo update|update neo"; Action = "NeoUpdate"; Label = "NeoOptimize Update" },
        @{ Pattern = "profile|profil|mode"; Action = "Profile"; Label = "Profile" }
    )

    foreach ($rule in $rules) {
        if ($text -match $rule.Pattern) {
            return [PSCustomObject]@{
                action = [string]$rule.Action
                label = [string]$rule.Label
                text = $Text
            }
        }
    }
    return $null
}

function Start-NeoVoiceAction {
    param([string]$Action)
    if ([string]::IsNullOrWhiteSpace($Action)) { return }
    if (-not (Test-Path $EnginePath)) {
        Write-Host "NeoOptimize engine not found: $EnginePath" -ForegroundColor Red
        return
    }
    $args = "-NoProfile -ExecutionPolicy RemoteSigned -File $(Quote-Arg $EnginePath) -Action $Action -AssumeYes"
    Start-Process -FilePath (Get-PowerShellExe) -ArgumentList $args -WorkingDirectory $Root -WindowStyle Normal | Out-Null
}

$voice = Read-VoiceConfig
$language = if ($voice.language) { [string]$voice.language } else { "id-ID" }
$wake = if ($voice.wake_phrase) { [string]$voice.wake_phrase } else { "neo optimize" }

Write-Host ""
Write-Host "NeoOptimize Voice Command"
Write-Host "========================="
Write-Host "Language    : $language"
Write-Host "Wake phrase : $wake"
Write-Host "Listening   : $ListenSeconds seconds"
Write-Host ""
Write-Host "Try: '$wake doctor', '$wake clean', '$wake optimize', '$wake network', '$wake model'"
Write-Host ""

try {
    Add-Type -AssemblyName System.Speech -ErrorAction Stop
    $culture = Resolve-VoiceCulture $language
    $recognizer = [System.Speech.Recognition.SpeechRecognitionEngine]::new($culture)
    $choices = [System.Speech.Recognition.Choices]::new()
    foreach ($phrase in @(
        "$wake doctor", "$wake health", "$wake analisa", "$wake diagnostic",
        "$wake model", "$wake provider", "$wake api",
        "$wake clean", "$wake bersih", "$wake optimize", "$wake network",
        "$wake security", "$wake disk", "$wake update aplikasi", "$wake profile",
        "doctor", "health", "clean", "optimize", "network", "security", "disk", "model"
    )) {
        [void]$choices.Add($phrase)
    }
    $builder = [System.Speech.Recognition.GrammarBuilder]::new()
    $builder.Culture = $culture
    $builder.Append($choices)
    $grammar = [System.Speech.Recognition.Grammar]::new($builder)
    $recognizer.LoadGrammar($grammar)
    $recognizer.SetInputToDefaultAudioDevice()

    $done = [System.Threading.ManualResetEvent]::new($false)
    $recognized = $null
    $recognizer.add_SpeechRecognized({
        param($sender, $eventArgs)
        if ($eventArgs.Result -and $eventArgs.Result.Confidence -ge 0.35) {
            $script:recognized = $eventArgs.Result
            [void]$script:done.Set()
        }
    })
    $recognizer.RecognizeAsync([System.Speech.Recognition.RecognizeMode]::Multiple)
    [void]$done.WaitOne([math]::Max(3, $ListenSeconds) * 1000)
    $recognizer.RecognizeAsyncStop()

    if (-not $recognized) {
        Write-Host "No clear voice command recognized." -ForegroundColor Yellow
        exit 2
    }

    $match = Get-NeoVoiceAction -Text $recognized.Text
    Write-Host "Recognized   : $($recognized.Text) ($([math]::Round($recognized.Confidence * 100))%)"
    if (-not $match) {
        Write-Host "No NeoOptimize action matched this phrase." -ForegroundColor Yellow
        exit 3
    }

    Write-Host "Action       : $($match.label) [$($match.action)]" -ForegroundColor Cyan
    if (-not $NoExecute) {
        Start-NeoVoiceAction -Action $match.action
    }
} catch {
    Write-Host "Voice command is unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "Install a Windows speech language pack and make sure a microphone is available." -ForegroundColor DarkGray
    exit 1
}
