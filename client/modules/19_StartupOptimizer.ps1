#Requires -RunAsAdministrator
<# MODULE 19 - STARTUP OPTIMIZER #>
Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
. "$PSScriptRoot\..\lib\Common.ps1"

Write-ModuleHeader "19" "BOOT" "STARTUP OPTIMIZER"

function Get-RunEntries {
    $rows = New-Object System.Collections.Generic.List[object]
    $paths = @(
        @{ Hive="HKCU"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Hive="HKLM"; Path="HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" },
        @{ Hive="HKLM32"; Path="HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run" }
    )
    $id = 1
    foreach ($p in $paths) {
        $item = Get-ItemProperty -Path $p.Path -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($prop in $item.PSObject.Properties) {
            if ($prop.Name -in @("PSPath","PSParentPath","PSChildName","PSDrive","PSProvider")) { continue }
            $rows.Add([PSCustomObject]@{
                Id = $id
                Type = "Run"
                Hive = $p.Hive
                Path = $p.Path
                Name = $prop.Name
                Command = [string]$prop.Value
            }) | Out-Null
            $id++
        }
    }
    return @($rows)
}

function Get-ThirdPartyStartupTasks {
    $rows = New-Object System.Collections.Generic.List[object]
    $id = 1
    Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskPath -notlike "\Microsoft\Windows\*" -and $_.State -in @("Ready","Running") } |
        Sort-Object TaskPath, TaskName |
        ForEach-Object {
            $rows.Add([PSCustomObject]@{
                Id = $id
                Type = "Task"
                TaskPath = $_.TaskPath
                TaskName = $_.TaskName
                State = $_.State
            }) | Out-Null
            $id++
        }
    return @($rows)
}

$runEntries = @(Get-RunEntries)
$tasks = @(Get-ThirdPartyStartupTasks)

Write-Step "RUN KEY STARTUP ENTRIES"
Write-Host ""
foreach ($entry in $runEntries) {
    Write-Host ("  [R{0,2}] {1,-6} {2,-32} {3}" -f $entry.Id, $entry.Hive, $entry.Name, $entry.Command)
}
if ($runEntries.Count -eq 0) { Write-Info "Tidak ada Run key startup entry." }

Write-Host ""
Write-Step "THIRD-PARTY SCHEDULED STARTUP TASKS"
Write-Host ""
foreach ($task in $tasks | Select-Object -First 30) {
    Write-Host ("  [T{0,2}] {1}{2} ({3})" -f $task.Id, $task.TaskPath, $task.TaskName, $task.State)
}
if ($tasks.Count -gt 30) { Write-Info "Menampilkan 30 dari $($tasks.Count) task. Report menyimpan semua." }
if ($tasks.Count -eq 0) { Write-Info "Tidak ada third-party scheduled task aktif." }

$dir = Join-Path $Global:LogDir "startup"
if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
$reportPath = Join-Path $dir ("startup-inventory_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
[PSCustomObject]@{ run = $runEntries; tasks = $tasks } | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8
Write-OK "Startup report: $reportPath"

if ($Global:NeoOptimizeNonInteractive -or [System.Console]::IsInputRedirected) {
    Write-Warn "Non-interactive mode: audit only."
    Wait-AnyKey
    return
}

Write-Host ""
Write-Host "  [1] Audit only"
Write-Host "  [2] Disable selected Run entries"
Write-Host "  [3] Disable selected scheduled tasks"
Write-Host ""
$choice = Read-NeoChoice "  Pilihan [1-3]" @("1","2","3") "1"

if ($choice -eq "2" -and $runEntries.Count -gt 0) {
    $raw = Read-Host "  Masukkan nomor R dipisah koma, contoh: 1,3"
    $ids = @($raw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $selected = @($runEntries | Where-Object { $ids -contains $_.Id })
    if ($selected.Count -gt 0 -and (Confirm-NeoAction "Disable selected Run entries?" $false)) {
        $backup = Join-Path $dir ("disabled-run_{0}.json" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        $selected | ConvertTo-Json -Depth 5 | Set-Content -Path $backup -Encoding UTF8
        foreach ($entry in $selected) {
            Backup-RegKey $entry.Path | Out-Null
            Remove-ItemProperty -Path $entry.Path -Name $entry.Name -ErrorAction SilentlyContinue
            Write-OK "Disabled Run entry: $($entry.Name)"
        }
        Write-OK "Disabled Run backup: $backup"
    }
}

if ($choice -eq "3" -and $tasks.Count -gt 0) {
    $raw = Read-Host "  Masukkan nomor T dipisah koma, contoh: 1,3"
    $ids = @($raw -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
    $selected = @($tasks | Where-Object { $ids -contains $_.Id })
    if ($selected.Count -gt 0 -and (Confirm-NeoAction "Disable selected scheduled tasks?" $false)) {
        foreach ($task in $selected) {
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
            Write-OK "Disabled task: $($task.TaskPath)$($task.TaskName)"
        }
    }
}

Write-Host ""
Write-Separator "=" $Global:GREEN
Write-Host "  $($Global:GREEN)$($Global:BOLD)STARTUP OPTIMIZER SELESAI$($Global:RESET)"
Write-Footer
Wait-AnyKey
