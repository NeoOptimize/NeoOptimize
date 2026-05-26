#Requires -Version 5.1
<#
.SYNOPSIS
    Lightweight NeoOptimize tray companion.

.DESCRIPTION
    Shows realtime CPU/RAM/DISK monitor, quick NEO chat, voice command entry,
    and shortcuts without depending on Windows Script Host.
#>

[CmdletBinding()]
param(
    [switch]$NoBalloon,
    [switch]$OpenChat
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:LogDir = Join-Path $env:ProgramData "NeoOptimize\logs"
$Script:LogPath = Join-Path $Script:LogDir "NeoOptimizeTray.log"
$Script:ChatBusy = $false
$Script:LastNetProbe = [datetime]::MinValue
$Script:LastNetText = "NET --"
$Script:MiniMonitorForm = $null
$Script:MiniMonitorLabels = @{}
$Script:NeoChatForm = $null
$Script:TrayExiting = $false

function Write-NeoTrayLog {
    param([string]$Message)
    try {
        if (-not (Test-Path $Script:LogDir)) { New-Item -Path $Script:LogDir -ItemType Directory -Force | Out-Null }
        Add-Content -Path $Script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message)
    } catch {}
}

function Get-NeoPowerShell {
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

function Start-NeoScript {
    param(
        [string]$ScriptName,
        [string]$Arguments = "",
        [switch]$Visible
    )
    $script = Join-Path $Script:Root $ScriptName
    if (-not (Test-Path $script)) {
        [System.Windows.Forms.MessageBox]::Show("$ScriptName was not found.", "NeoOptimize", "OK", "Warning") | Out-Null
        return
    }
    $ps = Get-NeoPowerShell
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $args = "$args $Arguments" }
    $style = if ($Visible) { "Normal" } else { "Hidden" }
    Start-Process -FilePath $ps -ArgumentList $args -WorkingDirectory $Script:Root -WindowStyle $style | Out-Null
}

function Get-NeoMetricSnapshot {
    $cpu = $null
    $ramPct = $null
    $diskFreePct = $null
    $netText = $Script:LastNetText

    try {
        $cpu = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 0)
    } catch {
        try {
            $cpuSample = Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 1
            $cpu = [math]::Round([double]$cpuSample.CounterSamples[0].CookedValue, 0)
        } catch { $cpu = $null }
    }

    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize
        $free = [double]$os.FreePhysicalMemory
        if ($total -gt 0) { $ramPct = [math]::Round((($total - $free) / $total) * 100, 0) }
    } catch { $ramPct = $null }

    try {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
        if ($disk.Size -gt 0) { $diskFreePct = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 0) }
    } catch { $diskFreePct = $null }

    if (((Get-Date) - $Script:LastNetProbe).TotalSeconds -ge 15) {
        try {
            $net = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq "Up" } |
                Select-Object -First 1
            if ($net) { $netText = "NET " + $net.Name } else { $netText = "NET offline" }
            $Script:LastNetText = $netText
            $Script:LastNetProbe = Get-Date
        } catch {
            $Script:LastNetText = "NET --"
            $Script:LastNetProbe = Get-Date
        }
    }

    [PSCustomObject]@{
        cpu = if ($null -eq $cpu) { "--" } else { "$cpu%" }
        cpu_value = if ($null -eq $cpu) { 0 } else { [int]$cpu }
        ram = if ($null -eq $ramPct) { "--" } else { "$ramPct%" }
        ram_value = if ($null -eq $ramPct) { 0 } else { [int]$ramPct }
        disk = if ($null -eq $diskFreePct) { "--" } else { "$diskFreePct% free" }
        disk_value = if ($null -eq $diskFreePct) { 0 } else { [int]$diskFreePct }
        net = $netText
        time = Get-Date -Format "HH:mm:ss"
    }
}

function Get-NeoInstantAnswer {
    param([string]$Question)
    if ([string]::IsNullOrWhiteSpace($Question)) { return "" }
    $lower = $Question.ToLowerInvariant()
    $normalized = ($lower -replace '[!?.,]', '').Trim()
    $m = Get-NeoMetricSnapshot
    $runtime = "Runtime: $env:COMPUTERNAME - CPU $($m.cpu) - RAM $($m.ram) - Disk $($m.disk)"

    if (@("hi", "hello", "halo", "hai", "help", "bantuan") -contains $normalized) {
        return @(
            "Provider: NEO instant local chat.",
            "Saya aktif. Anda bisa minta status sistem, scan anomaly, saran code perbaikan, daftar modul, voice command, atau Local AI Setup.",
            $runtime,
            "Best next action: ketik 'scan anomaly', 'saran code fix', atau buka Optimizer."
        ) -join "`r`n"
    }
    if ($normalized -eq "status" -or $lower.Contains("health") -or $lower.Contains("kondisi")) {
        return @(
            "Provider: NEO instant local status.",
            $runtime,
            "RMM: checked through service/runtime telemetry when endpoint sync is installed.",
            "Best next action: run AI Doctor Check for a ranked treatment plan."
        ) -join "`r`n"
    }
    if ($lower.Contains("anomali") -or $lower.Contains("anomaly") -or $lower.Contains("scan") -or $lower.Contains("detect")) {
        return @(
            "Provider: NEO realtime anomaly triage.",
            $runtime,
            "Workflow: Device Snapshot -> Benchmark Report -> AI Doctor Check -> Windows Doctor if repair is needed.",
            "Notifications: NEO Mini status, tray balloon/status, worker logs, reports, and RMM telemetry when enrolled."
        ) -join "`r`n"
    }
    if ($lower.Contains("code") -or $lower.Contains("script") -or $lower.Contains("fix") -or $lower.Contains("perbaikan") -or $lower.Contains("powershell")) {
        return @(
            "Provider: NEO code repair guide.",
            "Saya bisa memberi saran code perbaikan dan draft PowerShell/CMD melalui Script Forge.",
            "Default: read-only, rollback note, timeout, SHA-256/report metadata, dan human approval sebelum apply.",
            "Best next action: buka Script Forge atau tulis detail error."
        ) -join "`r`n"
    }
    if ($lower.Contains("ollama") -or $lower.Contains("model") -or $lower.Contains("local ai") -or $lower.Contains("neo-light") -or $lower.Contains("neo-latest")) {
        return @(
            "Provider: NEO Local AI setup guide.",
            "Installer dan Local AI Setup menjalankan Ollama bootstrap di background tanpa CMD popup.",
            "Required models: neo-light:latest, neo:latest, neo-latest:latest.",
            "Saat model masih download, NEO tetap menjawab melalui NeoCore/rule fallback."
        ) -join "`r`n"
    }
    return ""
}

function New-NeoFallbackAnswer {
    param([string]$Question, [string]$ProviderNote)
    $instant = Get-NeoInstantAnswer -Question $Question
    if (-not [string]::IsNullOrWhiteSpace($instant)) { return $instant }
    return @(
        "Provider: NEO local fallback.",
        "Provider note: $ProviderNote",
        "Best next action: run Local AI Setup, then ask again from NEO Mini.",
        "NEO typed chat remains available through local telemetry, packaged safe rules, anomaly triage, and corpus-aware AI Doctor/Script Forge."
    ) -join "`r`n"
}

function New-NeoMetricLabel {
    param([string]$Text, [int]$Top)
    $label = New-Object System.Windows.Forms.Label
    $label.Left = 16
    $label.Top = $Top
    $label.Width = 260
    $label.Height = 22
    $label.ForeColor = [System.Drawing.Color]::FromArgb(219, 230, 245)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
    $label.Text = $Text
    return $label
}

function Show-NeoMiniMonitor {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if ($Script:MiniMonitorForm -and -not $Script:MiniMonitorForm.IsDisposed) {
        $Script:MiniMonitorForm.Show()
        $Script:MiniMonitorForm.WindowState = "Normal"
        $Script:MiniMonitorForm.Activate()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "NeoOptimize Mini Monitor"
    $form.Width = 390
    $form.Height = 258
    $form.StartPosition = "Manual"
    $form.FormBorderStyle = "FixedSingle"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(7, 12, 22)
    $form.ForeColor = [System.Drawing.Color]::White
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $form.Left = $screen.Right - $form.Width - 18
    $form.Top = [Math]::Max($screen.Top + 24, $screen.Bottom - $form.Height - 34)

    $title = New-NeoMetricLabel "NEO Realtime Monitor" 16
    $title.ForeColor = [System.Drawing.Color]::FromArgb(0, 240, 255)
    $cpuLabel = New-NeoMetricLabel "CPU: --" 52
    $ramLabel = New-NeoMetricLabel "RAM: --" 78
    $diskLabel = New-NeoMetricLabel "DISK: --" 104
    $netLabel = New-NeoMetricLabel "NETWORK: --" 130
    $timeLabel = New-NeoMetricLabel "Last update: --" 154
    $timeLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8)
    $timeLabel.ForeColor = [System.Drawing.Color]::FromArgb(139, 152, 171)

    $chat = New-Object System.Windows.Forms.Button
    $chat.Text = "NEO Chat"
    $chat.Left = 16
    $chat.Top = 184
    $chat.Width = 104
    $chat.Height = 32
    $chat.BackColor = [System.Drawing.Color]::FromArgb(0, 214, 230)
    $chat.ForeColor = [System.Drawing.Color]::Black
    $chat.FlatStyle = "Flat"
    $chat.Add_Click({ Show-NeoChatWindow })

    $voice = New-Object System.Windows.Forms.Button
    $voice.Text = "Voice"
    $voice.Left = 130
    $voice.Top = 184
    $voice.Width = 78
    $voice.Height = 32
    $voice.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 45)
    $voice.ForeColor = [System.Drawing.Color]::FromArgb(0, 240, 255)
    $voice.FlatStyle = "Flat"
    $voice.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.VoiceCommand.ps1" -Visible })

    $hide = New-Object System.Windows.Forms.Button
    $hide.Text = "Hide"
    $hide.Left = 218
    $hide.Top = 184
    $hide.Width = 78
    $hide.Height = 32
    $hide.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 45)
    $hide.ForeColor = [System.Drawing.Color]::FromArgb(219, 230, 245)
    $hide.FlatStyle = "Flat"
    $hide.Add_Click({ $Script:MiniMonitorForm.Hide() })

    $exit = New-Object System.Windows.Forms.Button
    $exit.Text = "Exit"
    $exit.Left = 306
    $exit.Top = 184
    $exit.Width = 58
    $exit.Height = 32
    $exit.BackColor = [System.Drawing.Color]::FromArgb(45, 18, 28)
    $exit.ForeColor = [System.Drawing.Color]::FromArgb(255, 180, 190)
    $exit.FlatStyle = "Flat"
    $exit.Add_Click({
        $Script:TrayExiting = $true
        [System.Windows.Forms.Application]::Exit()
    })

    @($title, $cpuLabel, $ramLabel, $diskLabel, $netLabel, $timeLabel, $chat, $voice, $hide, $exit) | ForEach-Object { $form.Controls.Add($_) }
    $Script:MiniMonitorLabels = @{
        Cpu = $cpuLabel
        Ram = $ramLabel
        Disk = $diskLabel
        Net = $netLabel
        Time = $timeLabel
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $m = Get-NeoMetricSnapshot
        $labels = $Script:MiniMonitorLabels
        if ($labels.Cpu) { $labels.Cpu.Text = "CPU: $($m.cpu)" }
        if ($labels.Ram) { $labels.Ram.Text = "RAM: $($m.ram)" }
        if ($labels.Disk) { $labels.Disk.Text = "DISK: $($m.disk)" }
        if ($labels.Net) { $labels.Net.Text = "NETWORK: $($m.net)" }
        if ($labels.Time) { $labels.Time.Text = "Last update: $($m.time)" }
    })
    $timer.Start()
    $Script:MiniMonitorForm = $form
    $form.Add_Resize({
        if ($Script:MiniMonitorForm -and $Script:MiniMonitorForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $Script:MiniMonitorForm.Hide()
            $Script:MiniMonitorForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
    })
    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if (-not $Script:TrayExiting -and $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $eventArgs.Cancel = $true
            $sender.Hide()
        }
    })
    $form.Add_FormClosed({
        $timer.Stop()
        $timer.Dispose()
        $Script:MiniMonitorForm = $null
        $Script:MiniMonitorLabels = @{}
    })
    [void]$form.Show()
}

function Invoke-NeoAsk {
    param([string]$Question)
    if ([string]::IsNullOrWhiteSpace($Question)) { return "" }
    $instant = Get-NeoInstantAnswer -Question $Question
    if (-not [string]::IsNullOrWhiteSpace($instant)) { return $instant }
    $agent = Join-Path $Script:Root "NeoOptimize.AIAgent.ps1"
    if (-not (Test-Path $agent)) { return (New-NeoFallbackAnswer -Question $Question -ProviderNote "NeoOptimize.AIAgent.ps1 was not found.") }

    $ps = Get-NeoPowerShell
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $ps
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$agent`" -Mode Interactive -Question `"$($Question.Replace('"', '\"'))`" -NoOpen"
    $psi.WorkingDirectory = $Script:Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { return "Failed to start NEO." }
    if (-not $proc.WaitForExit(45000)) {
        try { $proc.Kill() } catch {}
        return (New-NeoFallbackAnswer -Question $Question -ProviderNote "NEO timed out. Local AI may still be installing or loading a model.")
    }
    $stdout = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd().Trim()
    if ($stdout) { return $stdout }
    if ($stderr) { return $stderr }
    return (New-NeoFallbackAnswer -Question $Question -ProviderNote "NEO returned no output.")
}

function Show-NeoChatWindow {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    if ($Script:NeoChatForm -and -not $Script:NeoChatForm.IsDisposed) {
        $Script:NeoChatForm.Show()
        $Script:NeoChatForm.WindowState = "Normal"
        $Script:NeoChatForm.Activate()
        return
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "NEO - Neural Execution Operator"
    $form.Width = 680
    $form.Height = 520
    $form.StartPosition = "CenterScreen"
    $form.BackColor = [System.Drawing.Color]::FromArgb(7, 12, 22)
    $form.ForeColor = [System.Drawing.Color]::White
    $form.MinimumSize = New-Object System.Drawing.Size(560, 420)

    $history = New-Object System.Windows.Forms.TextBox
    $history.Multiline = $true
    $history.ReadOnly = $true
    $history.ScrollBars = "Vertical"
    $history.Left = 14
    $history.Top = 14
    $history.Width = 636
    $history.Height = 380
    $history.Anchor = "Top,Left,Right,Bottom"
    $history.BackColor = [System.Drawing.Color]::FromArgb(12, 19, 32)
    $history.ForeColor = [System.Drawing.Color]::FromArgb(219, 230, 245)
    $history.Font = New-Object System.Drawing.Font("Consolas", 9)
    $history.Text = "NEO: Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.`r`n`r`n"

    $input = New-Object System.Windows.Forms.TextBox
    $input.Left = 14
    $input.Top = 408
    $input.Width = 410
    $input.Height = 26
    $input.Anchor = "Left,Right,Bottom"
    $input.BackColor = [System.Drawing.Color]::FromArgb(19, 30, 48)
    $input.ForeColor = [System.Drawing.Color]::White
    $input.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $send = New-Object System.Windows.Forms.Button
    $send.Text = "Send"
    $send.Left = 438
    $send.Top = 406
    $send.Width = 58
    $send.Height = 30
    $send.Anchor = "Right,Bottom"
    $send.BackColor = [System.Drawing.Color]::FromArgb(0, 214, 230)
    $send.ForeColor = [System.Drawing.Color]::Black
    $send.FlatStyle = "Flat"

    $clear = New-Object System.Windows.Forms.Button
    $clear.Text = "Clear"
    $clear.Left = 526
    $clear.Top = 406
    $clear.Width = 58
    $clear.Height = 30
    $clear.Anchor = "Right,Bottom"
    $clear.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 45)
    $clear.ForeColor = [System.Drawing.Color]::FromArgb(219, 230, 245)
    $clear.FlatStyle = "Flat"

    $voice = New-Object System.Windows.Forms.Button
    $voice.Text = "Voice"
    $voice.Left = 592
    $voice.Top = 406
    $voice.Width = 58
    $voice.Height = 30
    $voice.Anchor = "Right,Bottom"
    $voice.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 45)
    $voice.ForeColor = [System.Drawing.Color]::FromArgb(0, 240, 255)
    $voice.FlatStyle = "Flat"
    $voice.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.VoiceCommand.ps1" -Visible })
    $clear.Add_Click({
        $history.Text = "NEO: Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.`r`n`r`n"
        $status.Text = "Chat cleared."
    }.GetNewClosure())

    $hide = New-Object System.Windows.Forms.Button
    $hide.Text = "Hide"
    $hide.Left = 592
    $hide.Top = 446
    $hide.Width = 58
    $hide.Height = 28
    $hide.Anchor = "Right,Bottom"
    $hide.BackColor = [System.Drawing.Color]::FromArgb(18, 28, 45)
    $hide.ForeColor = [System.Drawing.Color]::FromArgb(219, 230, 245)
    $hide.FlatStyle = "Flat"
    $hide.Add_Click({ $Script:NeoChatForm.Hide() })

    $status = New-Object System.Windows.Forms.Label
    $status.Left = 14
    $status.Top = 446
    $status.Width = 568
    $status.Height = 22
    $status.Anchor = "Left,Right,Bottom"
    $status.ForeColor = [System.Drawing.Color]::FromArgb(139, 152, 171)
    $status.Text = "Ask NEO about diagnostics, maintenance, script forge, skills, MCP, or 'siapa anda'."

    $sendAction = {
        if ($Script:ChatBusy) { return }
        $question = $input.Text.Trim()
        if (-not $question) { return }
        $Script:ChatBusy = $true
        $input.Text = ""
        $send.Enabled = $false
        $status.Text = "NEO is thinking..."
        $history.AppendText("You: $question`r`n")
        [System.Windows.Forms.Application]::DoEvents()
        try {
            $answer = Invoke-NeoAsk -Question $question
            $history.AppendText("NEO: $answer`r`n`r`n")
        } catch {
            $history.AppendText("NEO error: $($_.Exception.Message)`r`n`r`n")
        }
        $history.SelectionStart = $history.Text.Length
        $history.ScrollToCaret()
        $status.Text = "Ready."
        $send.Enabled = $true
        $Script:ChatBusy = $false
    }
    $send.Add_Click($sendAction.GetNewClosure())
    $input.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $_.SuppressKeyPress = $true
            & $sendAction
        }
    }.GetNewClosure())

    $Script:NeoChatForm = $form
    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if (-not $Script:TrayExiting -and $eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
            $eventArgs.Cancel = $true
            $sender.Hide()
        }
    })

    @($history, $input, $send, $clear, $voice, $hide, $status) | ForEach-Object { $form.Controls.Add($_) }
    [void]$form.Show()
    $form.Activate()
}

try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $iconPath = Join-Path $Script:Root "assets\NeoOptimize.ico"
    if (-not (Test-Path $iconPath)) { $iconPath = Join-Path $Script:Root "assets\icon.ico" }

    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Text = "NeoOptimize"
    if (Test-Path $iconPath) {
        $notify.Icon = New-Object System.Drawing.Icon($iconPath)
    } else {
        $notify.Icon = [System.Drawing.SystemIcons]::Shield
    }
    $notify.Visible = $true

    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $openItem = $menu.Items.Add("Open NeoOptimize")
    $monitorItem = $menu.Items.Add("Mini Monitor")
    $hideMonitorItem = $menu.Items.Add("Hide Mini Monitor")
    $chatItem = $menu.Items.Add("NEO Chat")
    $hideChatItem = $menu.Items.Add("Hide NEO Chat")
    $agenticItem = $menu.Items.Add("NEO Agentic Autopilot")
    $voiceItem = $menu.Items.Add("Voice Command")
    $updateItem = $menu.Items.Add("Update Manager")
    $providersItem = $menu.Items.Add("AI Providers")
    $reportsItem = $menu.Items.Add("Open Reports")
    $menu.Items.Add("-") | Out-Null
    $exitItem = $menu.Items.Add("Exit")

    $openItem.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.Launcher.ps1" })
    $monitorItem.Add_Click({ Show-NeoMiniMonitor })
    $hideMonitorItem.Add_Click({
        if ($Script:MiniMonitorForm -and -not $Script:MiniMonitorForm.IsDisposed) { $Script:MiniMonitorForm.Hide() }
    })
    $chatItem.Add_Click({ Show-NeoChatWindow })
    $hideChatItem.Add_Click({
        if ($Script:NeoChatForm -and -not $Script:NeoChatForm.IsDisposed) { $Script:NeoChatForm.Hide() }
    })
    $agenticItem.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.AgenticRunner.ps1" -Arguments "-Mode RunOnce" -Visible })
    $voiceItem.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.VoiceCommand.ps1" -Visible })
    $updateItem.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.Launcher.ps1" -Arguments "-UpdateManager" -Visible })
    $providersItem.Add_Click({ Start-NeoScript -ScriptName "NeoOptimize.AIAgent.ps1" -Arguments "-Mode Providers" -Visible })
    $reportsItem.Add_Click({
        $reports = Join-Path $Script:Root "reports"
        if (-not (Test-Path $reports)) { New-Item -Path $reports -ItemType Directory -Force | Out-Null }
        Start-Process explorer.exe -ArgumentList "`"$reports`""
    })
    $exitItem.Add_Click({
        $Script:TrayExiting = $true
        $notify.Visible = $false
        [System.Windows.Forms.Application]::Exit()
    })
    $notify.ContextMenuStrip = $menu
    $notify.Add_DoubleClick({ Start-NeoScript -ScriptName "NeoOptimize.Launcher.ps1" })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        try {
            $m = Get-NeoMetricSnapshot
            $notify.Text = "NeoOptimize | CPU $($m.cpu) RAM $($m.ram) DISK $($m.disk)"
        } catch {}
    })
    $timer.Start()

    if (-not $NoBalloon) {
        $notify.BalloonTipTitle = "NeoOptimize"
        $notify.BalloonTipText = "NEO tray is active. Realtime monitor, AI chat, voice command, and updates are ready."
        $notify.ShowBalloonTip(3000)
    }

    if ($OpenChat) {
        Show-NeoChatWindow
    } else {
        Show-NeoMiniMonitor
    }

    Write-NeoTrayLog "Tray started."
    [System.Windows.Forms.Application]::Run()
} catch {
    Write-NeoTrayLog ("Tray error: {0}" -f $_.Exception.Message)
}
