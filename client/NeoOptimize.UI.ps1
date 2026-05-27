#Requires -Version 5.1
<#
.SYNOPSIS
    NeoOptimize production control center.
#>

Set-StrictMode -Off
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:EnginePath = Join-Path $Script:Root "NeoOptimize.ps1"
$Script:ReportsPath = Join-Path $Script:Root "reports"
$Script:ConfigPath = Join-Path $Script:Root "config\NeoOptimize.UI.json"
$Script:UiLogPath = Join-Path $Script:Root "reports\NeoOptimize_UI.log"
$Script:WorkerReportsPath = Join-Path $Script:Root "reports\workers"
$Script:WorkerStdoutPath = ""
$Script:WorkerStderrPath = ""
$Script:WorkerTranscriptPath = ""
$Script:WorkerLastLabel = ""
$Script:IconPath = Join-Path $Script:Root "assets\NeoOptimize.ico"
$Script:LogoPath = Join-Path $Script:Root "assets\NeoOptimize.png"
$Script:ModelConfigPath = Join-Path $Script:Root "config\NeoOptimize.ModelAgent.json"
$Script:RmmConfigPath = Join-Path $Script:Root "config\NeoOptimize.RMM.json"
$Script:LightRefreshSeconds = 3.0
$Script:HeavyRefreshSeconds = 15.0
$Script:SystemSnapshot = $null
$Script:LastSystemSnapshotRefresh = [DateTime]::MinValue
$Script:LastGpuRefresh = [DateTime]::MinValue
$Script:LastGpuUsage = 0.0
try {
    $refreshOverride = $env:NEOOPTIMIZE_REFRESH_SECONDS -as [double]
    if ($refreshOverride -and $refreshOverride -ge 1) {
        $Script:LightRefreshSeconds = [math]::Min(10.0, [math]::Max(1.0, $refreshOverride))
    }
} catch {}

function Test-AdminSession {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-AdminSession)) {
    $ps = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    Start-Process -FilePath $ps -ArgumentList "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WindowStyle Hidden
    exit
}

foreach ($dir in @($Script:ReportsPath, $Script:WorkerReportsPath, (Split-Path -Parent $Script:ConfigPath))) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

function Write-UiLog {
    param([string]$Message)
    try {
        Add-Content -Path $Script:UiLogPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    } catch {}
}

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Xaml

function Quote-Arg {
    param([string]$Value)
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Quote-PsLiteral {
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-PowerShellExe {
    return (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe")
}

function Read-UiConfig {
    $default = [PSCustomObject]@{
        language = "en"
        theme = "dark"
        profile_name = ""
        profile_phone = ""
        profile_created_at = ""
    }
    if (-not (Test-Path $Script:ConfigPath)) { return $default }
    try {
        $cfg = Get-Content -Path $Script:ConfigPath -Raw | ConvertFrom-Json
        if ($cfg.language -notin @("en", "id")) { $cfg.language = "en" }
        if ($cfg.theme -notin @("system", "dark", "light")) { $cfg.theme = "dark" }
        foreach ($property in @("profile_name", "profile_phone", "profile_created_at")) {
            if (-not ($cfg.PSObject.Properties.Name -contains $property)) {
                $cfg | Add-Member -NotePropertyName $property -NotePropertyValue ""
            }
        }
        return $cfg
    } catch {
        return $default
    }
}

function Save-UiConfig {
    [PSCustomObject]@{
        language = $Script:UiLanguage
        theme = $Script:UiTheme
        profile_name = $Script:UserName
        profile_phone = $Script:UserPhone
        profile_created_at = $Script:ProfileCreatedAt
        updated_at = (Get-Date).ToString("s")
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $Script:ConfigPath -Encoding UTF8
}

function Get-SystemTheme {
    try {
        $value = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop
        if ([int]$value -eq 1) { return "light" }
    } catch {}
    return "dark"
}

function Resolve-Theme {
    if ($Script:UiTheme -eq "system") { return Get-SystemTheme }
    return $Script:UiTheme
}

$Script:UiConfig = Read-UiConfig
$Script:UiLanguage = $Script:UiConfig.language
$Script:UiTheme = $Script:UiConfig.theme
$Script:UserName = [string]$Script:UiConfig.profile_name
$Script:UserPhone = [string]$Script:UiConfig.profile_phone
$Script:ProfileCreatedAt = [string]$Script:UiConfig.profile_created_at
$Script:BrushConverter = [System.Windows.Media.BrushConverter]::new()

$Script:L = @{
    en = @{
        AppTagline = "SYSTEM OPTIMIZER PRO"
        MainTitle = "System Overview"
        Subtitle = "Real-time performance & optimization monitoring"
        Health = "Health"
        Rmm = "RMM"
        RmmServer = "server"
        RmmReachable = "reachable"
        RmmUnreachable = "unreachable"
        Ready = "Ready."
        Refresh = "Refresh"
        FullAuto = "Safe Care Plan"
        Overview = "Overview"
        Advisor = "Diagnostics"
        Providers = "Security"
        NullClawDocs = "NullClaw Docs"
        Audit = "AI Analysis"
        Restore = "Smart Optimize"
        Reports = "Reports"
        Console = "Disk Status"
        Users = "Profile"
        Settings = "Settings"
        About = "About"
        ManagedSystems = "Endpoint Sync"
        OnlineNow = "Online Now"
        OfflineCount = "Offline"
        TasksToday = "Tasks Today"
        TotalRegistered = "Total registered"
        ActiveConnected = "Active & connected"
        NeedAttentionCard = "Need attention"
        OptimizationTasks = "Optimization tasks"
        Available = "Available"
        TaskQueueTitle = "Task Queue"
        TaskQueueEmpty = "No tasks yet. Run a module to start."
        Workflow = "Repair Workflow"
        WorkflowNote = "Technician sequence"
        StepPrecheck = "Pre-check"
        StepProtect = "Protect"
        StepOptimize = "Optimize"
        StepReport = "Report"
        StepPrecheckDesc = "Audit endpoint state."
        StepProtectDesc = "Create restore point."
        StepOptimizeDesc = "Run modules safely."
        StepReportDesc = "Review logs."
        Run = "Run"
        Modules = "Optimizer Modules"
        ModulesNote = "Run AI-assisted optimization and maintenance modules on this computer or approved endpoint agents."
        Cloud = "Cloud Connectors"
        CloudNote = "GitHub, HF Space, Supabase, E2B"
        CloudStatus = "Check Connectors"
        CloudOpen = "Open Cloud Pages"
        AiPanel = "NeoCore AI"
        AiNote = "Built-in trainable local model. Ollama and NullClaw are optional assistants."
        AiChecking = "NeoCore: checking..."
        NeoCoreReady = "NeoCore local model ready"
        NeoCoreMissing = "NeoCore policy model missing"
        AiRuleReady = "safety rule engine ready"
        OllamaReady = "Ollama ready"
        OllamaMissing = "Ollama not running"
        NullClawReady = "NullClaw connected"
        NullClawMissing = "NullClaw not connected"
        NullClawInstall = "Install NullClaw CLI, run onboard, then refresh providers."
        Device = "Device"
        Cpu = "CPU"
        Memory = "Memory"
        Disk = "Disk"
        Windows = "Windows"
        Free = "free"
        Used = "used"
        Uptime = "uptime"
        Days = "days"
        Running = "Running"
        Missing = "Not installed"
        Unknown = "Unknown"
        NoTelemetry = "No telemetry"
        InstallAgent = "Install agent package"
        RmmAuthMissing = "Fleet monitor ready"
        RmmConnected = "Endpoint sync connected"
        RmmDegraded = "Endpoint sync degraded"
        RmmOffline = "Local mode"
        RmmDispatch = "Dispatch to endpoint agents?"
        RmmDispatchQuestion = "Online endpoint agents are available. Yes sends this action to approved agents. No runs it on this computer only."
        RmmDispatchQueued = "Task queued"
        RmmDispatchFailed = "Remote queue failed"
        NeoUpdate = "Update NeoOptimize"
        Healthy = "Healthy"
        NeedsAttention = "Needs attention"
        HighRisk = "High risk"
        Id = "ID"
        Operation = "Operation"
        Risk = "Risk"
        Action = "Action"
        Configured = "configured"
        Publishable = "publishable"
        Dashboard = "dashboard"
        MissingConnector = "missing"
        ReadyState = "ready"
        Started = "started."
        Refreshed = "Dashboard refreshed"
        Saved = "Preference saved."
        ConfirmFullAuto = "Safe Care Plan runs audit, deep scan, light cleanup, and reports only. High-risk tuning stays locked unless explicitly enforced."
        ConfirmTitle = "Confirm Safe Care"
        MissingEngine = "NeoOptimize.ps1 was not found."
        Operations = @(
            @{ Badge="SYS"; Name="System Dashboard"; Risk="Read-only"; Action="Dashboard"; Detail="Hardware, disk, OS, uptime, process overview." },
            @{ Badge="AID"; Name="AI Doctor Health"; Risk="Read-only"; Action="AIPlan"; Detail="Clickable AI health inspection with NeoCore, local models, NullClaw, or API models." },
            @{ Badge="NEO"; Name="NEO - Neural Execution Operator"; Risk="Confirm"; Action="AIInteractive"; Detail="Conversational AI operator with skills, MCP connector awareness, and confirmed local actions." },
            @{ Badge="AGT"; Name="NEO Agentic Autopilot"; Risk="Confirm"; Action="NEOAgentic"; Detail="Observe, diagnose, plan, ask approval, act through allowlisted modules, verify, and learn from local outcomes." },
            @{ Badge="SCR"; Name="NEO Script Forge"; Risk="Read-only"; Action="AIScriptForge"; Detail="Generate PowerShell/CMD audit and maintenance scripts with SHA-256 metadata and safe defaults." },
            @{ Badge="CAT"; Name="Capability Catalog"; Risk="Read-only"; Action="AICatalog"; Detail="View NEO capability map with risk, preflight, rollback, verification, and references." },
            @{ Badge="MOD"; Name="AI Model Agent"; Risk="Config"; Action="AIModelSettings"; Detail="Choose model provider, local endpoint, API keys, and voice command profile." },
            @{ Badge="VOC"; Name="Voice Command"; Risk="Read-only"; Action="VoiceCommand"; Detail="Use Windows speech recognition to launch safe NeoOptimize actions." },
            @{ Badge="PERM"; Name="Permission Audit"; Risk="Medium"; Action="Permissions"; Detail="Audit elevation, UAC, WMI, services, and remote-access posture without opening remote access." },
            @{ Badge="HW"; Name="Device Collector"; Risk="Read-only"; Action="Collect"; Detail="Hardware inventory, OS profile, process snapshot, and structured telemetry export." },
            @{ Badge="CLN"; Name="System Cleaner"; Risk="Low"; Action="Cleaner"; Detail="Temp, cache, recycle bin, WER, browser cache cleanup." },
            @{ Badge="DSN"; Name="Deep Scan"; Risk="Read-only"; Action="DeepScan"; Detail="Deep scan drives and folders for junk, obsolete packages, cache, and residual files." },
            @{ Badge="DIA"; Name="System Diagnostics"; Risk="Read-only"; Action="SystemDiagnostics"; Detail="Detect boot, driver, event log, and Windows health anomalies." },
            @{ Badge="DOC"; Name="NEO Windows Doctor"; Risk="Read-only"; Action="WindowsDoctor"; Detail="Correlate diagnostics, anomaly scoring, AI plan, MCP context, and NullClaw bridge." },
            @{ Badge="FIX"; Name="Windows Error Fix"; Risk="High"; Action="WindowsErrorFix"; Detail="Human-confirmed repair lane for DISM, SFC, WinRE, update reset, and service recovery." },
            @{ Badge="RPR"; Name="System Repair"; Risk="High"; Action="SystemRepair"; Detail="Enable WinRE, run DISM RestoreHealth, SFC, update reset, and recovery service checks." },
            @{ Badge="SMA"; Name="Smart Optimize"; Risk="Medium"; Action="SmartOptimize"; Detail="Clean junk, boost memory, scan disk, and run defrag/TRIM." },
            @{ Badge="JNK"; Name="Clean All Junk"; Risk="Low"; Action="CleanAll"; Detail="Temp, prefetch, browser cache, shader cache, update cache, and recycle bin." },
            @{ Badge="SCH"; Name="Schedule Cleanup"; Risk="Low"; Action="ScheduleClean"; Detail="Install daily hidden cleanup task at 03:30 as SYSTEM." },
            @{ Badge="DSK"; Name="Disk Status"; Risk="Read-only"; Action="DiskStatus"; Detail="Volume capacity, health, physical disk status, and report export." },
            @{ Badge="CHK"; Name="Scan Disk"; Risk="Read-only"; Action="DiskScan"; Detail="Online scan with Repair-Volume or chkdsk /scan fallback." },
            @{ Badge="FIX"; Name="Repair Disk"; Risk="High"; Action="DiskRepair"; Detail="Offline scan/fix or chkdsk /F scheduling when required." },
            @{ Badge="TRM"; Name="Defrag / TRIM"; Risk="Medium"; Action="DiskOptimize"; Detail="Analyze and optimize fixed volumes with SSD TRIM support." },
            @{ Badge="HLT"; Name="Health Repair"; Risk="Medium"; Action="HealthRepair"; Detail="DISM component cleanup, RestoreHealth, and SFC scan." },
            @{ Badge="PER"; Name="Performance"; Risk="Medium"; Action="Performance"; Detail="Memory, NTFS, visual effects, boot and responsiveness tuning." },
            @{ Badge="PRV"; Name="Privacy"; Risk="Medium"; Action="Privacy"; Detail="Reduce diagnostics, tracking, suggestions, and bloat patterns." },
            @{ Badge="NET"; Name="Network"; Risk="Medium"; Action="Network"; Detail="TCP stack, DNS, QoS, and low-latency settings." },
            @{ Badge="SEC"; Name="Security Audit / Hardening"; Risk="Confirm"; Action="Security"; Detail="Audit-first security module. Hardening needs explicit ENFORCE in the console." },
            @{ Badge="DFR"; Name="Defender Lab Recovery"; Risk="Confirm"; Action="DefenderAuditMode"; Detail="Recover lab machines after old aggressive CFA, ASR, or Network Protection hardening." },
            @{ Badge="SVC"; Name="Services"; Risk="High"; Action="Services"; Detail="Service profiles for home, gaming, workstation, minimal, restore." },
            @{ Badge="UPD"; Name="Updates"; Risk="Medium"; Action="Updates"; Detail="Windows Update control, driver audit, winget upgrade." },
            @{ Badge="PWR"; Name="Power"; Risk="Low"; Action="Power"; Detail="Power plans, gaming mode, latency and power audit." },
            @{ Badge="APP"; Name="Selectable Debloater"; Risk="Medium"; Action="Apps"; Detail="Choose bundled Windows apps to uninstall; Camera, Photos, Store, Calculator stay protected." },
            @{ Badge="STR"; Name="Startup Optimizer"; Risk="Medium"; Action="StartupOptimizer"; Detail="Audit startup Run keys and third-party scheduled tasks, then disable selected entries." },
            @{ Badge="CMP"; Name="Component Cleanup"; Risk="Medium"; Action="ComponentCleanup"; Detail="Analyze WinSxS and run DISM StartComponentCleanup when approved." },
            @{ Badge="EVT"; Name="Event Log Maintenance"; Risk="Medium"; Action="EventLogMaintenance"; Detail="Export key EVTX logs and optionally clear after backup." },
            @{ Badge="FEA"; Name="Feature Optimizer"; Risk="Medium"; Action="FeatureOptimizer"; Detail="Audit optional Windows features and disable selected legacy components." },
            @{ Badge="NRT"; Name="Network Repair Toolkit"; Risk="Medium"; Action="NetworkRepair"; Detail="Flush DNS, renew DHCP, reset proxy, or perform confirmed Winsock/TCP repair." },
            @{ Badge="DEV"; Name="Device Snapshot"; Risk="Read-only"; Action="DeviceSnapshot"; Detail="Inventory OS, hardware, drivers, disks, BitLocker, TPM, and Secure Boot." },
            @{ Badge="BEN"; Name="Before/After Benchmark"; Risk="Read-only"; Action="BenchmarkReport"; Detail="Capture performance baseline and compare after maintenance." },
            @{ Badge="PVR"; Name="Privacy Review"; Risk="Read-only"; Action="PrivacyReview"; Detail="Audit privacy settings while keeping Camera, Microphone, and Location user-controlled." },
            @{ Badge="NDG"; Name="Network Diagnostics"; Risk="Read-only"; Action="NetworkDiagnostics"; Detail="Run adapter, DNS, route, TCP, and connectivity diagnostics." },
            @{ Badge="HV"; Name="Container/Hyper-V Tuning"; Risk="Medium"; Action="ContainerHyperVTuning"; Detail="Audit WSL2 and Hyper-V; write safe .wslconfig only with approval." },
            @{ Badge="ZT"; Name="Zero-Trust Security"; Risk="Medium"; Action="ZeroTrustSecurity"; Detail="Audit Defender, firewall, SMB, LSA, VBS, HVCI, and optional ASR policy." },
            @{ Badge="GM"; Name="Game Mode Ultra"; Risk="Medium"; Action="GameModeUltra"; Detail="Audit and apply safe Game Mode, GameDVR, and HAGS settings without BCDEdit changes." },
            @{ Badge="NPU"; Name="AI & NPU Caching"; Risk="Read-only"; Action="AINPUCaching"; Detail="Inventory AI accelerators and model cache sizes; optional local cache limit policy." },
            @{ Badge="NVMe"; Name="NVMe DirectStorage"; Risk="Medium"; Action="StorageTiering"; Detail="Audit BypassIO, SSD health, ReTrim, and Storage Spaces tiering." },
            @{ Badge="RAC"; Name="Remote Readiness"; Risk="Read-only"; Action="RemoteReadiness"; Detail="Check WinRM, OpenSSH, RDP, QEMU Guest Agent, firewall, and RMM without enabling access." },
            @{ Badge="WUR"; Name="Update Repair"; Risk="Medium"; Action="UpdateRepair"; Detail="Audit Windows Update and run DISM/SFC or component reset only after confirmation." },
            @{ Badge="PWR"; Name="Power Plan Tuning"; Risk="Medium"; Action="PowerPlanTuning"; Detail="Audit powercfg and switch power plans after approval." },
            @{ Badge="SA"; Name="Security Audit"; Risk="Read-only"; Action="SecurityAudit"; Detail="Read-only posture for Defender, firewall, UAC, SMB, TPM, Secure Boot, and BitLocker." },
            @{ Badge="PRO"; Name="Optimization Profile"; Risk="Medium"; Action="Profile"; Detail="Choose office, gaming, balanced, or recovery-oriented optimization profiles." },
            @{ Badge="BKP"; Name="Backup"; Risk="Low"; Action="Backup"; Detail="Create local registry, Wi-Fi profile, and driver backup before deeper changes." },
            @{ Badge="THR"; Name="Threat Monitor"; Risk="Read-only"; Action="ThreatMonitor"; Detail="Inspect Defender health, suspicious processes, network activity, and script anomalies." },
            @{ Badge="AIM"; Name="Autoimmune Shield"; Risk="High"; Action="Autoimmune"; Detail="Audit-first ransomware and ASR protection profile; enforce only after confirmation." },
            @{ Badge="INT"; Name="Integrity Scan"; Risk="Read-only"; Action="IntegrityScan"; Detail="Verify critical files, process signatures, SHA-256 hashes, and tamper indicators." },
            @{ Badge="APP"; Name="Secure Update Manager"; Risk="Signed"; Action="NeoUpdate"; Detail="Credential-gated update, SHA-256 integrity verification, and automatic NeoOptimize repair." },
            @{ Badge="AGT"; Name="Agent Audit"; Risk="Read-only"; Action="AgentAudit"; Detail="Endpoint score, findings, reports, safe remediation plan." }
        )
    }
    id = @{
        AppTagline = "SYSTEM OPTIMIZER PRO"
        MainTitle = "System Overview"
        Subtitle = "Real-time performance & optimization monitoring"
        Health = "Health"
        Rmm = "RMM"
        RmmServer = "server"
        RmmReachable = "terjangkau"
        RmmUnreachable = "tidak terjangkau"
        Ready = "Siap."
        Refresh = "Refresh"
        FullAuto = "Safe Care Plan"
        Overview = "Overview"
        Advisor = "Diagnostics"
        Providers = "Security"
        NullClawDocs = "Docs NullClaw"
        Audit = "AI Analysis"
        Restore = "Smart Optimize"
        Reports = "Reports"
        Console = "Disk Status"
        Users = "Profile"
        Settings = "Settings"
        About = "About"
        ManagedSystems = "Sinkron Endpoint"
        OnlineNow = "Sedang Online"
        OfflineCount = "Offline"
        TasksToday = "Tugas Hari Ini"
        TotalRegistered = "Total terdaftar"
        ActiveConnected = "Aktif & terhubung"
        NeedAttentionCard = "Perlu perhatian"
        OptimizationTasks = "Tugas optimasi"
        Available = "tersedia"
        TaskQueueTitle = "Task Queue"
        TaskQueueEmpty = "No tasks yet. Run a module to start."
        Workflow = "Alur Repair"
        WorkflowNote = "Urutan teknisi"
        StepPrecheck = "Pre-check"
        StepProtect = "Proteksi"
        StepOptimize = "Optimasi"
        StepReport = "Report"
        StepPrecheckDesc = "Audit status endpoint."
        StepProtectDesc = "Buat restore point."
        StepOptimizeDesc = "Jalankan modul aman."
        StepReportDesc = "Review log."
        Run = "Jalankan"
        Modules = "Optimizer Modules"
        ModulesNote = "Jalankan modul optimasi dan maintenance berbasis AI di komputer ini atau agent endpoint yang disetujui."
        Cloud = "Cloud Connectors"
        CloudNote = "GitHub, HF Space, Supabase, E2B"
        CloudStatus = "Cek Connectors"
        CloudOpen = "Buka Cloud"
        AiPanel = "NeoCore AI"
        AiNote = "Model lokal bawaan yang bisa dilatih ulang. Ollama dan NullClaw hanya assistant opsional."
        AiChecking = "NeoCore: mengecek..."
        NeoCoreReady = "Model lokal NeoCore siap"
        NeoCoreMissing = "Policy model NeoCore belum ada"
        AiRuleReady = "safety rule engine siap"
        OllamaReady = "Ollama siap"
        OllamaMissing = "Ollama belum running"
        NullClawReady = "NullClaw terhubung"
        NullClawMissing = "NullClaw belum terhubung"
        NullClawInstall = "Install NullClaw CLI, jalankan onboard, lalu refresh provider."
        Device = "Device"
        Cpu = "CPU"
        Memory = "Memori"
        Disk = "Disk"
        Windows = "Windows"
        Free = "kosong"
        Used = "terpakai"
        Uptime = "uptime"
        Days = "hari"
        Running = "Running"
        Missing = "Belum terinstall"
        Unknown = "Tidak diketahui"
        NoTelemetry = "Telemetry belum ada"
        InstallAgent = "Install paket agent"
        RmmAuthMissing = "Fleet monitor siap"
        RmmConnected = "Sinkron endpoint terhubung"
        RmmDegraded = "Sinkron endpoint perlu perhatian"
        RmmOffline = "Mode lokal"
        RmmDispatch = "Kirim ke agent endpoint?"
        RmmDispatchQuestion = "Agent endpoint online tersedia. Yes mengirim aksi ini ke agent yang disetujui. No menjalankan di komputer ini saja."
        RmmDispatchQueued = "Task masuk antrean"
        RmmDispatchFailed = "Antrean remote gagal"
        NeoUpdate = "Update NeoOptimize"
        Healthy = "Sehat"
        NeedsAttention = "Perlu perhatian"
        HighRisk = "Risiko tinggi"
        Id = "ID"
        Operation = "Operasi"
        Risk = "Risiko"
        Action = "Aksi"
        Configured = "terkonfigurasi"
        Publishable = "publishable"
        Dashboard = "dashboard"
        MissingConnector = "belum ada"
        ReadyState = "siap"
        Started = "dijalankan."
        Refreshed = "Dashboard direfresh"
        Saved = "Preferensi disimpan."
        ConfirmFullAuto = "Safe Care Plan menjalankan audit, deep scan, cleanup ringan, dan report saja. Tuning high-risk tetap terkunci kecuali di-enforce eksplisit."
        ConfirmTitle = "Konfirmasi Safe Care"
        MissingEngine = "NeoOptimize.ps1 tidak ditemukan."
        Operations = @(
            @{ Badge="SYS"; Name="System Dashboard"; Risk="Read-only"; Action="Dashboard"; Detail="Hardware, disk, OS, uptime, dan proses." },
            @{ Badge="AID"; Name="AI Doctor Health"; Risk="Read-only"; Action="AIPlan"; Detail="Pemeriksaan kesehatan via NeoCore, model lokal, NullClaw, atau API model." },
            @{ Badge="NEO"; Name="NEO - Neural Execution Operator"; Risk="Confirm"; Action="AIInteractive"; Detail="Operator AI percakapan dengan skill, status MCP connector, dan aksi lokal terkonfirmasi." },
            @{ Badge="AGT"; Name="NEO Agentic Autopilot"; Risk="Confirm"; Action="NEOAgentic"; Detail="Observe, diagnosa, plan, minta approval, act via modul allowlist, verify, lalu belajar dari hasil lokal." },
            @{ Badge="SCR"; Name="NEO Script Forge"; Risk="Read-only"; Action="AIScriptForge"; Detail="Buat script PowerShell/CMD audit dan maintenance dengan SHA-256 dan default aman." },
            @{ Badge="CAT"; Name="Capability Catalog"; Risk="Read-only"; Action="AICatalog"; Detail="Lihat peta capability NEO berisi risiko, preflight, rollback, verifikasi, dan referensi." },
            @{ Badge="MOD"; Name="AI Model Agent"; Risk="Config"; Action="AIModelSettings"; Detail="Pilih provider model, endpoint lokal, API key, dan profil voice command." },
            @{ Badge="VOC"; Name="Voice Command"; Risk="Read-only"; Action="VoiceCommand"; Detail="Gunakan speech recognition Windows untuk menjalankan aksi NeoOptimize yang aman." },
            @{ Badge="PERM"; Name="Permission Audit"; Risk="Medium"; Action="Permissions"; Detail="Audit elevation, UAC, WMI, service, dan remote-access posture tanpa membuka remote access." },
            @{ Badge="HW"; Name="Device Collector"; Risk="Read-only"; Action="Collect"; Detail="Inventory hardware, profil OS, snapshot proses, dan export telemetry terstruktur." },
            @{ Badge="CLN"; Name="System Cleaner"; Risk="Low"; Action="Cleaner"; Detail="Bersihkan temp, cache, recycle bin, WER, dan cache browser." },
            @{ Badge="DSN"; Name="Deep Scan"; Risk="Read-only"; Action="DeepScan"; Detail="Deep scan drive dan folder untuk junk, paket lama, cache, dan residual." },
            @{ Badge="DIA"; Name="System Diagnostics"; Risk="Read-only"; Action="SystemDiagnostics"; Detail="Deteksi anomali boot, driver, event log, dan health Windows." },
            @{ Badge="DOC"; Name="NEO Windows Doctor"; Risk="Read-only"; Action="WindowsDoctor"; Detail="Korelasikan diagnostics, skor anomali, AI plan, MCP context, dan NullClaw bridge." },
            @{ Badge="FIX"; Name="Windows Error Fix"; Risk="High"; Action="WindowsErrorFix"; Detail="Repair terkonfirmasi untuk DISM, SFC, WinRE, reset update, dan recovery service." },
            @{ Badge="RPR"; Name="System Repair"; Risk="High"; Action="SystemRepair"; Detail="Enable WinRE, jalankan DISM RestoreHealth, SFC, reset update, dan cek service recovery." },
            @{ Badge="SMA"; Name="Smart Optimize"; Risk="Medium"; Action="SmartOptimize"; Detail="Clean junk, boost memori, scan disk, dan defrag/TRIM." },
            @{ Badge="JNK"; Name="Clean All Junk"; Risk="Low"; Action="CleanAll"; Detail="Temp, prefetch, cache browser, shader cache, cache update, recycle bin." },
            @{ Badge="SCH"; Name="Schedule Cleanup"; Risk="Low"; Action="ScheduleClean"; Detail="Install task cleanup harian jam 03:30 sebagai SYSTEM." },
            @{ Badge="DSK"; Name="Disk Status"; Risk="Read-only"; Action="DiskStatus"; Detail="Kapasitas volume, health, physical disk, dan export report." },
            @{ Badge="CHK"; Name="Scan Disk"; Risk="Read-only"; Action="DiskScan"; Detail="Online scan via Repair-Volume atau fallback chkdsk /scan." },
            @{ Badge="FIX"; Name="Repair Disk"; Risk="High"; Action="DiskRepair"; Detail="Offline scan/fix atau jadwal chkdsk /F bila diperlukan." },
            @{ Badge="TRM"; Name="Defrag / TRIM"; Risk="Medium"; Action="DiskOptimize"; Detail="Analyze dan optimize fixed volume dengan dukungan SSD TRIM." },
            @{ Badge="HLT"; Name="Health Repair"; Risk="Medium"; Action="HealthRepair"; Detail="DISM component cleanup, RestoreHealth, dan SFC scan." },
            @{ Badge="PER"; Name="Performance"; Risk="Medium"; Action="Performance"; Detail="Tuning memory, NTFS, visual effects, boot, dan respons." },
            @{ Badge="PRV"; Name="Privacy"; Risk="Medium"; Action="Privacy"; Detail="Kurangi diagnostic, tracking, suggestion, dan bloat." },
            @{ Badge="NET"; Name="Network"; Risk="Medium"; Action="Network"; Detail="TCP stack, DNS, QoS, dan setting low-latency." },
            @{ Badge="SEC"; Name="Security Audit / Hardening"; Risk="Confirm"; Action="Security"; Detail="Modul security audit-first. Hardening butuh ENFORCE eksplisit di console." },
            @{ Badge="DFR"; Name="Defender Lab Recovery"; Risk="Confirm"; Action="DefenderAuditMode"; Detail="Pulihkan VM lab setelah hardening CFA, ASR, atau Network Protection lama terlalu agresif." },
            @{ Badge="SVC"; Name="Services"; Risk="High"; Action="Services"; Detail="Profil service home, gaming, workstation, minimal, restore." },
            @{ Badge="UPD"; Name="Updates"; Risk="Medium"; Action="Updates"; Detail="Kontrol Windows Update, audit driver, upgrade winget." },
            @{ Badge="PWR"; Name="Power"; Risk="Low"; Action="Power"; Detail="Power plan, gaming mode, latency, dan power audit." },
            @{ Badge="APP"; Name="Selectable Debloater"; Risk="Medium"; Action="Apps"; Detail="Pilih sendiri app bawaan Windows yang ingin dihapus; Camera, Photos, Store, Calculator tetap dilindungi." },
            @{ Badge="STR"; Name="Startup Optimizer"; Risk="Medium"; Action="StartupOptimizer"; Detail="Audit Run key startup dan scheduled task pihak ketiga, lalu disable pilihan." },
            @{ Badge="CMP"; Name="Component Cleanup"; Risk="Medium"; Action="ComponentCleanup"; Detail="Analisis WinSxS dan jalankan DISM StartComponentCleanup setelah disetujui." },
            @{ Badge="EVT"; Name="Event Log Maintenance"; Risk="Medium"; Action="EventLogMaintenance"; Detail="Export EVTX utama dan optional clear setelah backup." },
            @{ Badge="FEA"; Name="Feature Optimizer"; Risk="Medium"; Action="FeatureOptimizer"; Detail="Audit optional Windows features dan disable komponen legacy terpilih." },
            @{ Badge="NRT"; Name="Network Repair Toolkit"; Risk="Medium"; Action="NetworkRepair"; Detail="Flush DNS, renew DHCP, reset proxy, atau repair Winsock/TCP dengan konfirmasi." },
            @{ Badge="DEV"; Name="Device Snapshot"; Risk="Read-only"; Action="DeviceSnapshot"; Detail="Inventaris OS, hardware, driver, disk, BitLocker, TPM, dan Secure Boot." },
            @{ Badge="BEN"; Name="Before/After Benchmark"; Risk="Read-only"; Action="BenchmarkReport"; Detail="Capture baseline performa dan bandingkan setelah maintenance." },
            @{ Badge="PVR"; Name="Privacy Review"; Risk="Read-only"; Action="PrivacyReview"; Detail="Audit privacy tanpa mengunci Camera, Microphone, dan Location dari sisi organization policy." },
            @{ Badge="NDG"; Name="Network Diagnostics"; Risk="Read-only"; Action="NetworkDiagnostics"; Detail="Diagnostik adapter, DNS, route, TCP, dan konektivitas." },
            @{ Badge="HV"; Name="Container/Hyper-V Tuning"; Risk="Medium"; Action="ContainerHyperVTuning"; Detail="Audit WSL2 dan Hyper-V; tulis .wslconfig aman hanya jika disetujui." },
            @{ Badge="ZT"; Name="Zero-Trust Security"; Risk="Medium"; Action="ZeroTrustSecurity"; Detail="Audit Defender, firewall, SMB, LSA, VBS, HVCI, dan policy ASR opsional." },
            @{ Badge="GM"; Name="Game Mode Ultra"; Risk="Medium"; Action="GameModeUltra"; Detail="Audit dan terapkan Game Mode, GameDVR, HAGS aman tanpa BCDEdit otomatis." },
            @{ Badge="NPU"; Name="AI & NPU Caching"; Risk="Read-only"; Action="AINPUCaching"; Detail="Inventaris akselerator AI dan ukuran cache model; optional policy batas cache lokal." },
            @{ Badge="NVMe"; Name="NVMe DirectStorage"; Risk="Medium"; Action="StorageTiering"; Detail="Audit BypassIO, health SSD, ReTrim, dan Storage Spaces tiering." },
            @{ Badge="RAC"; Name="Remote Readiness"; Risk="Read-only"; Action="RemoteReadiness"; Detail="Cek WinRM, OpenSSH, RDP, QEMU Guest Agent, firewall, dan RMM tanpa membuka akses." },
            @{ Badge="WUR"; Name="Update Repair"; Risk="Medium"; Action="UpdateRepair"; Detail="Audit Windows Update dan jalankan DISM/SFC atau reset component hanya setelah konfirmasi." },
            @{ Badge="PWR"; Name="Power Plan Tuning"; Risk="Medium"; Action="PowerPlanTuning"; Detail="Audit powercfg dan ganti power plan setelah disetujui." },
            @{ Badge="SA"; Name="Security Audit"; Risk="Read-only"; Action="SecurityAudit"; Detail="Audit read-only Defender, firewall, UAC, SMB, TPM, Secure Boot, dan BitLocker." },
            @{ Badge="PRO"; Name="Optimization Profile"; Risk="Medium"; Action="Profile"; Detail="Pilih profil optimasi office, gaming, balanced, atau recovery." },
            @{ Badge="BKP"; Name="Backup"; Risk="Low"; Action="Backup"; Detail="Buat backup registry, profil Wi-Fi, dan driver sebelum perubahan lebih dalam." },
            @{ Badge="THR"; Name="Threat Monitor"; Risk="Read-only"; Action="ThreatMonitor"; Detail="Periksa Defender, proses mencurigakan, aktivitas network, dan anomali script." },
            @{ Badge="AIM"; Name="Autoimmune Shield"; Risk="High"; Action="Autoimmune"; Detail="Profil proteksi ransomware dan ASR audit-first; enforce hanya setelah konfirmasi." },
            @{ Badge="INT"; Name="Integrity Scan"; Risk="Read-only"; Action="IntegrityScan"; Detail="Verifikasi file kritis, signature proses, SHA-256, dan indikator tamper." },
            @{ Badge="APP"; Name="Secure Update Manager"; Risk="Signed"; Action="NeoUpdate"; Detail="Update dengan kredensial, verifikasi SHA-256, dan repair otomatis NeoOptimize." },
            @{ Badge="RMT"; Name="Remote Access Bootstrap"; Risk="Dry-run"; Action="RemoteAccess"; Detail="Cek kesiapan WinRM, OpenSSH, dan QEMU Guest Agent lab tanpa mengaktifkan akses remote diam-diam." },
            @{ Badge="AGT"; Name="Agent Audit"; Risk="Read-only"; Action="AgentAudit"; Detail="Endpoint score, findings, report, dan rencana remediation aman." }
        )
    }
}

function T {
    param([string]$Key)
    return $Script:L[$Script:UiLanguage][$Key]
}

$Script:OverviewModules = @(
    @{ Icon="▦"; Color="#00F0FF"; Name="System Dashboard";      Action="Dashboard";         Detail="Refresh hardware, disk, OS, uptime, process, and live performance overview." },
    @{ Icon="AI"; Color="#00FF9D"; Name="AI Doctor Health";     Action="AIPlan";           Detail="Run the AI Doctor plan using NeoCore, local models, NullClaw, or configured API models." },
    @{ Icon="NE"; Color="#00FF9D"; Name="NEO Operator";         Action="AIInteractive";    Detail="Talk with NEO, inspect skills/MCP status, and run confirmed local actions." },
    @{ Icon="AG"; Color="#00FF9D"; Name="NEO Agentic Autopilot"; Action="NEOAgentic";      Detail="Let NEO observe, plan, request approval, act through safe modules, verify, and write memory." },
    @{ Icon="PS"; Color="#00F0FF"; Name="NEO Script Forge";     Action="AIScriptForge";    Detail="Create safe PowerShell/CMD audit scripts with hash metadata and RMM/OpenFang telemetry." },
    @{ Icon="CAT"; Color="#00F0FF"; Name="Capability Catalog";  Action="AICatalog";        Detail="Inspect the safety map for diagnostics, repair, cleanup, security, storage, update, and operator workflows." },
    @{ Icon="🎙"; Color="#A855F7"; Name="Voice Command";        Action="VoiceCommand";     Detail="Open Windows speech command control for safe NeoOptimize actions." },
    @{ Icon="PER"; Color="#FFCC00"; Name="Permission Audit";    Action="Permissions";      Detail="Audit elevation, UAC, WMI, services, and remote-access posture without changing UAC or opening ports." },
    @{ Icon="HW"; Color="#00F0FF"; Name="Device Collector";     Action="Collect";          Detail="Collect OS, hardware, process, service, activation, and benchmark telemetry." },
    @{ Icon="🔎"; Color="#00F0FF"; Name="Deep Scan";            Action="DeepScan";         Detail="Scan drives and folders for junk, obsolete packages, caches, and residual files." },
    @{ Icon="🩺"; Color="#00F0FF"; Name="System Diagnostics";   Action="SystemDiagnostics";Detail="Detect boot, WinRE, driver, event log, disk, and Windows health anomalies." },
    @{ Icon="DOC"; Color="#00FF9D"; Name="NEO Windows Doctor";  Action="WindowsDoctor";    Detail="Correlate diagnostics, anomaly scoring, AI plan, MCP context, and NullClaw bridge." },
    @{ Icon="📊"; Color="#00F0FF"; Name="Disk Status";          Action="DiskStatus";       Detail="Audit volume capacity, health, physical disk state, and export a disk report." },
    @{ Icon="✓"; Color="#00F0FF"; Name="Scan Disk";             Action="DiskScan";         Detail="Run online disk scan using Repair-Volume or chkdsk /scan fallback." },
    @{ Icon="AG"; Color="#A855F7"; Name="Agent Audit";          Action="AgentAudit";       Detail="Review endpoint score, findings, reports, and safe remediation plan." },
    @{ Icon="🧹"; Color="#00F0FF"; Name="System Cleaner";        Action="Cleaner";           Detail="Deep clean temp files, browser caches, prefetch, WER dumps, DNS cache, and recycle bin." },
    @{ Icon="◆"; Color="#00FF9D"; Name="Smart Optimize";       Action="SmartOptimize";    Detail="Run safe cleanup, memory care, disk scan, and TRIM/defrag workflow." },
    @{ Icon="CLR"; Color="#00F0FF"; Name="Clean All Junk";      Action="CleanAll";         Detail="Clean temp, prefetch, browser cache, shader cache, update cache, and recycle bin." },
    @{ Icon="⏱"; Color="#00F0FF"; Name="Schedule Cleanup";     Action="ScheduleClean";    Detail="Install a daily hidden cleanup task at 03:30 as SYSTEM." },
    @{ Icon="⚡"; Color="#A855F7"; Name="Performance Tuner";     Action="Performance";       Detail="Tune memory, boot flow, visual effects, and responsiveness." },
    @{ Icon="🔒"; Color="#00FF9D"; Name="Privacy Hardener";      Action="Privacy";           Detail="Reduce telemetry, suggestions, background noise, and tracking surfaces." },
    @{ Icon="🌐"; Color="#00F0FF"; Name="Network Optimizer";     Action="Network";           Detail="Adjust TCP/IP, DNS, QoS, and low-latency settings." },
    @{ Icon="🛡"; Color="#FF3366"; Name="Security Audit";        Action="Security";          Detail="Audit Defender, firewall, SMB, TLS, UAC, and exploit posture. Hardening requires ENFORCE." },
    @{ Icon="DF"; Color="#FFCC00"; Name="Defender Lab Recovery"; Action="DefenderAuditMode"; Detail="Move lab CFA, ASR, and Network Protection rules to AuditMode after aggressive old hardening." },
    @{ Icon="⚙"; Color="#FFCC00"; Name="Services Manager";       Action="Services";          Detail="Switch between home, gaming, workstation, minimal, and restore profiles." },
    @{ Icon="↻"; Color="#A855F7"; Name="Update Manager";         Action="Updates";           Detail="Audit Windows Update, drivers, and winget packages." },
    @{ Icon="🔋"; Color="#00FF9D"; Name="Power & Gaming Mode";   Action="Power";             Detail="Apply power plans, boost latency, and game-friendly settings." },
    @{ Icon="APP"; Color="#FFCC00"; Name="Selectable Debloater";Action="Apps";             Detail="Choose bundled Windows apps to uninstall while protecting Camera, Photos, Store, Calculator, and App Installer." },
    @{ Icon="STR"; Color="#FFCC00"; Name="Startup Optimizer";   Action="StartupOptimizer"; Detail="Audit and disable selected startup entries and third-party scheduled tasks." },
    @{ Icon="CMP"; Color="#00FF9D"; Name="Component Cleanup";   Action="ComponentCleanup"; Detail="Analyze WinSxS and run approved DISM component cleanup." },
    @{ Icon="EVT"; Color="#00F0FF"; Name="Event Log Maintenance"; Action="EventLogMaintenance"; Detail="Export EVTX logs and optionally clear selected logs after backup." },
    @{ Icon="FEA"; Color="#FFCC00"; Name="Feature Optimizer";   Action="FeatureOptimizer"; Detail="Audit optional Windows features and disable selected legacy components." },
    @{ Icon="NRT"; Color="#FF3366"; Name="Network Repair Toolkit"; Action="NetworkRepair"; Detail="Flush DNS, renew DHCP, reset proxy, or confirmed Winsock/TCP repair." },
    @{ Icon="DEV"; Color="#00F0FF"; Name="Device Snapshot";      Action="DeviceSnapshot"; Detail="Inventory OS, hardware, drivers, disks, BitLocker, TPM, and Secure Boot." },
    @{ Icon="BEN"; Color="#00F0FF"; Name="Before/After Benchmark"; Action="BenchmarkReport"; Detail="Capture performance baseline and compare after maintenance." },
    @{ Icon="PVR"; Color="#00F0FF"; Name="Privacy Review";       Action="PrivacyReview"; Detail="Audit privacy settings without organization-locking Camera, Microphone, or Location." },
    @{ Icon="NDG"; Color="#00F0FF"; Name="Network Diagnostics";  Action="NetworkDiagnostics"; Detail="Run connectivity, DNS, route, adapter, and TCP diagnostics." },
    @{ Icon="HV"; Color="#FFCC00"; Name="Container/Hyper-V";     Action="ContainerHyperVTuning"; Detail="Audit WSL2 and Hyper-V, then write safe .wslconfig only with approval." },
    @{ Icon="ZT"; Color="#FFCC00"; Name="Zero-Trust Security";   Action="ZeroTrustSecurity"; Detail="Audit Defender, firewall, SMB, LSA, VBS, HVCI, and optional ASR rules." },
    @{ Icon="GM"; Color="#FFCC00"; Name="Game Mode Ultra";       Action="GameModeUltra"; Detail="Apply safe Game Mode, GameDVR, and HAGS settings without BCDEdit changes." },
    @{ Icon="NPU"; Color="#00FF9D"; Name="AI & NPU Caching";     Action="AINPUCaching"; Detail="Inventory AI accelerators and model cache size, with optional local cache policy." },
    @{ Icon="NVMe"; Color="#00FF9D"; Name="NVMe DirectStorage";  Action="StorageTiering"; Detail="Audit BypassIO, SSD health, ReTrim, and Storage Spaces tiering." },
    @{ Icon="RAC"; Color="#00F0FF"; Name="Remote Readiness";     Action="RemoteReadiness"; Detail="Check WinRM, OpenSSH, RDP, QEMU Guest Agent, firewall, and RMM without enabling access." },
    @{ Icon="WUR"; Color="#FFCC00"; Name="Update Repair";        Action="UpdateRepair"; Detail="Audit Windows Update and run DISM/SFC or component reset only after confirmation." },
    @{ Icon="PWR"; Color="#FFCC00"; Name="Power Plan Tuning";    Action="PowerPlanTuning"; Detail="Audit powercfg and switch power plans after approval." },
    @{ Icon="SA"; Color="#00F0FF"; Name="Security Audit";        Action="SecurityAudit"; Detail="Read-only Defender, firewall, UAC, SMB, TPM, Secure Boot, and BitLocker audit." },
    @{ Icon="PRO"; Color="#00FF9D"; Name="Optimization Profile"; Action="Profile";          Detail="Select office, gaming, balanced, or recovery profiles for safer recommendations." },
    @{ Icon="BKP"; Color="#00F0FF"; Name="System Backup";       Action="Backup";           Detail="Back up registry, Wi-Fi profiles, and drivers before deeper maintenance." },
    @{ Icon="THR"; Color="#A855F7"; Name="Threat Monitor";      Action="ThreatMonitor";    Detail="Scan Defender state, suspicious processes, network connections, and script telemetry." },
    @{ Icon="AIM"; Color="#FFCC00"; Name="Autoimmune Shield";   Action="Autoimmune";       Detail="Audit-first Defender ASR, Controlled Folder Access, and Network Protection profile." },
    @{ Icon="INT"; Color="#00F0FF"; Name="Integrity Scan";      Action="IntegrityScan";    Detail="Check critical binaries, running process signatures, SHA-256, and tamper risk." },
    @{ Icon="FIX"; Color="#FF3366"; Name="Repair Disk";         Action="DiskRepair";       Detail="Run offline scan/fix or schedule chkdsk /F when required." },
    @{ Icon="TRM"; Color="#00FF9D"; Name="Defrag / TRIM";       Action="DiskOptimize";     Detail="Analyze and optimize fixed volumes with SSD TRIM support." },
    @{ Icon="HLT"; Color="#FFCC00"; Name="Health Repair";       Action="HealthRepair";     Detail="Run DISM component cleanup, RestoreHealth, and SFC scan." },
    @{ Icon="ERR"; Color="#FF3366"; Name="Windows Error Fix";   Action="WindowsErrorFix";  Detail="Run conservative Windows repair after NEO Doctor review and confirmation." },
    @{ Icon="🛠"; Color="#64748B"; Name="System Repair";         Action="SystemRepair";     Detail="Enable WinRE, run DISM RestoreHealth, SFC, update reset, and recovery checks." },
    @{ Icon="↥"; Color="#00FF9D"; Name="Secure Update Manager"; Action="NeoUpdate";         Detail="Credential-gated update with SHA-256 integrity scan and automatic repair." },
    @{ Icon="RA"; Color="#FFCC00"; Name="Remote Access Bootstrap"; Action="RemoteAccess"; Detail="Dry-run status for WinRM, OpenSSH, and lab QEMU Guest Agent. Enabling requires explicit administrator consent." }
)
$Script:ModulePageTitle = ""
$Script:ModulePageNote = ""
$Script:ModuleActionFilter = @()
$Script:ModuleGroups = @{
    Diagnostics = @("Dashboard", "Collect", "DeviceSnapshot", "BenchmarkReport", "PrivacyReview", "NetworkDiagnostics", "AIPlan", "AIInteractive", "NEOAgentic", "AIScriptForge", "AICatalog", "VoiceCommand", "DeepScan", "SystemDiagnostics", "WindowsDoctor", "DiskStatus", "DiskScan", "Backup", "AgentAudit", "RemoteAccess", "RemoteReadiness")
    Security    = @("SecurityAudit", "Security", "ZeroTrustSecurity", "DefenderAuditMode", "ThreatMonitor", "IntegrityScan", "Autoimmune", "Permissions", "Privacy", "PrivacyReview", "Network", "Services", "RemoteReadiness")
    Optimize    = @("SmartOptimize", "Cleaner", "CleanAll", "ScheduleClean", "Performance", "Power", "PowerPlanTuning", "Apps", "StartupOptimizer", "ComponentCleanup", "EventLogMaintenance", "FeatureOptimizer", "NetworkRepair", "ContainerHyperVTuning", "GameModeUltra", "AINPUCaching", "StorageTiering", "UpdateRepair", "Profile", "Updates", "NeoUpdate")
    Disk        = @("DiskStatus", "DiskScan", "DiskRepair", "DiskOptimize", "StorageTiering", "HealthRepair", "WindowsErrorFix", "SystemRepair", "UpdateRepair")
}

$Script:CpuSeries = [System.Collections.Generic.List[double]]::new()
$Script:GpuSeries = [System.Collections.Generic.List[double]]::new()
$Script:RamSeries = [System.Collections.Generic.List[double]]::new()
$Script:DiskSeries = [System.Collections.Generic.List[double]]::new()
$Script:NetSeries = [System.Collections.Generic.List[double]]::new()
$Script:TaskBreakdown = @(
    @{ Name = "Clean";    Count = 12 },
    @{ Name = "Perf";     Count = 8 },
    @{ Name = "Security"; Count = 15 },
    @{ Name = "Updates";   Count = 5 },
    @{ Name = "Network";   Count = 9 },
    @{ Name = "Power";     Count = 6 }
)
$Script:RmmSnapshot = $null
$Script:LastRmmRefresh = [DateTime]::MinValue
$Script:RmmStartupDeferUntil = (Get-Date).AddSeconds(4)
$Script:RefreshTimer = $null
$Script:UiTaskRunning = $false
$Script:UiTaskName = ""
$Script:UiTaskTimer = $null
$Script:EngineActionSet = $null

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NeoOptimize Control Center" Width="1080" Height="620" MinWidth="980" MinHeight="580"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource PageBrush}" FontFamily="{DynamicResource MainFontFamily}">
  <Window.Resources>
    <FontFamily x:Key="MainFontFamily">Segoe UI</FontFamily>
    <FontFamily x:Key="MonoFontFamily">Consolas</FontFamily>
    <SolidColorBrush x:Key="PageBrush" Color="#06080D"/>
    <SolidColorBrush x:Key="SidebarBrush" Color="#080F1A"/>
    <SolidColorBrush x:Key="PanelBrush" Color="#121B2B"/>
    <SolidColorBrush x:Key="PanelAltBrush" Color="#0C121D"/>
    <SolidColorBrush x:Key="LineBrush" Color="#14FFFFFF"/>
    <SolidColorBrush x:Key="TextBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="SidebarTextBrush" Color="#FFFFFF"/>
    <SolidColorBrush x:Key="MutedBrush" Color="#A0AEC0"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#00F0FF"/>
    <SolidColorBrush x:Key="AccentTextBrush" Color="#05131C"/>
    <SolidColorBrush x:Key="GoodBrush" Color="#00FF9D"/>
    <SolidColorBrush x:Key="WarnBrush" Color="#FFCC00"/>
    <SolidColorBrush x:Key="NavBrush" Color="#08111B"/>
    <SolidColorBrush x:Key="NavHoverBrush" Color="#10192A"/>
    <SolidColorBrush x:Key="PressedBrush" Color="#071018"/>
    <SolidColorBrush x:Key="DangerBrush" Color="#FF3366"/>
    <SolidColorBrush x:Key="WorkerBrush" Color="#07101A"/>

    <Style x:Key="ButtonChrome" TargetType="Button">
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="15,10"/>
      <Setter Property="MinHeight" Value="40"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="HorizontalContentAlignment" Value="Center"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Chrome"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="8">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                                VerticalAlignment="{TemplateBinding VerticalContentAlignment}"
                                Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Chrome" Property="Opacity" Value="0.90"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Chrome" Property="Opacity" Value="0.78"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Chrome" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavButton" TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource NavBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource SidebarTextBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,5"/>
      <Setter Property="MinHeight" Value="32"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Chrome" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <Grid>
                <Border Width="4" Background="{DynamicResource AccentBrush}" HorizontalAlignment="Left" CornerRadius="8,0,0,8" Opacity="0.9"/>
                <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Left" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Chrome" Property="Background" Value="{DynamicResource NavHoverBrush}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Chrome" Property="Opacity" Value="0.78"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ButtonChrome}">
      <Setter Property="Background" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource AccentTextBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
    </Style>
    <Style x:Key="SecondaryButton" TargetType="Button" BasedOn="{StaticResource ButtonChrome}">
      <Setter Property="Background" Value="{DynamicResource PanelAltBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="MinHeight" Value="34"/>
    </Style>
    <Style x:Key="DarkComboBox" TargetType="ComboBox">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Background" Value="{DynamicResource PanelAltBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource LineBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="MinHeight" Value="36"/>
    </Style>
    <Style x:Key="DarkComboBoxItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource TextBrush}"/>
      <Setter Property="Background" Value="{DynamicResource PanelBrush}"/>
      <Setter Property="Padding" Value="8,6"/>
    </Style>
  </Window.Resources>
  <Grid Background="{DynamicResource PageBrush}">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="250"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="{DynamicResource SidebarBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="0,0,1,0">
      <Grid Margin="16">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Grid.Row="0" Margin="0,0,0,10">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="56"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border Width="52" Height="52" Background="#08111B" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12">
            <Image x:Name="BrandLogoImage" Width="42" Height="42" Stretch="Uniform"/>
          </Border>
          <StackPanel Grid.Column="1" Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="NEOOPTIMIZE" Foreground="{DynamicResource SidebarTextBrush}" FontSize="16" FontWeight="Bold"/>
            <Border Height="2" Width="72" HorizontalAlignment="Left" Background="{DynamicResource AccentBrush}" CornerRadius="1" Margin="0,6,0,6"/>
            <TextBlock x:Name="AppTaglineText" Foreground="{DynamicResource MutedBrush}" FontSize="10" TextWrapping="Wrap"/>
          </StackPanel>
        </Grid>
        <Border Grid.Row="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,18" Visibility="Collapsed">
          <StackPanel>
            <TextBlock x:Name="HealthLabelText" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <DockPanel Margin="0,8,0,4">
              <TextBlock x:Name="ScoreText" Text="--" Foreground="{DynamicResource WarnBrush}" FontSize="36" FontWeight="Bold" DockPanel.Dock="Left"/>
              <TextBlock Text="/100" Foreground="{DynamicResource MutedBrush}" FontSize="14" VerticalAlignment="Bottom" Margin="5,0,0,7"/>
            </DockPanel>
            <TextBlock x:Name="HealthText" Foreground="{DynamicResource TextBrush}" FontSize="12" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <StackPanel Grid.Row="2">
          <TextBlock Text="MONITOR" Foreground="{DynamicResource MutedBrush}" FontSize="10" FontWeight="SemiBold" Margin="4,0,0,4"/>
          <Button x:Name="BtnOverview" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnAdvisor" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <TextBlock Text="SECURITY" Foreground="{DynamicResource MutedBrush}" FontSize="10" FontWeight="SemiBold" Margin="4,4,0,4"/>
          <Button x:Name="BtnProviders" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnAudit" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <TextBlock Text="OPTIMIZE" Foreground="{DynamicResource MutedBrush}" FontSize="10" FontWeight="SemiBold" Margin="4,4,0,4"/>
          <Button x:Name="BtnRestore" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnReports" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <TextBlock Text="MANAGE" Foreground="{DynamicResource MutedBrush}" FontSize="10" FontWeight="SemiBold" Margin="4,4,0,4"/>
          <Button x:Name="BtnConsole" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnUsers" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnSettings" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
          <Button x:Name="BtnAbout" Style="{StaticResource NavButton}" Margin="0,0,0,4"/>
        </StackPanel>
        <Border Grid.Row="3" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Visibility="Collapsed">
          <StackPanel>
            <TextBlock x:Name="RmmLabelText" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="RmmStatusText" Foreground="{DynamicResource TextBrush}" FontSize="13" FontWeight="SemiBold" Margin="0,5,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="RmmDetailText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,7,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </Grid>
    </Border>

    <Grid Grid.Column="1" Margin="18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0" Margin="0,0,0,14">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="MainTitleText" Foreground="{DynamicResource TextBrush}" FontSize="16" FontWeight="SemiBold"/>
          <TextBlock x:Name="SubtitleText" Foreground="{DynamicResource MutedBrush}" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <ComboBox x:Name="LanguageCombo" Width="82" Height="36" Margin="0,0,8,0" Style="{StaticResource DarkComboBox}" ItemContainerStyle="{StaticResource DarkComboBoxItem}" Visibility="Collapsed">
            <ComboBoxItem Content="EN" Tag="en"/>
            <ComboBoxItem Content="IN" Tag="id"/>
          </ComboBox>
          <ComboBox x:Name="ThemeCombo" Width="98" Height="36" Margin="0,0,10,0" Style="{StaticResource DarkComboBox}" ItemContainerStyle="{StaticResource DarkComboBoxItem}" Visibility="Collapsed">
            <ComboBoxItem Content="System" Tag="system"/>
            <ComboBoxItem Content="Dark" Tag="dark"/>
            <ComboBoxItem Content="Light" Tag="light"/>
          </ComboBox>
          <Border x:Name="TaskRunningNotice" Background="#182235" BorderBrush="{DynamicResource AccentBrush}" BorderThickness="1" CornerRadius="8" Padding="10,8" Margin="0,0,8,0" Visibility="Collapsed">
            <TextBlock x:Name="TaskRunningText" Text="Task is running..." Foreground="{DynamicResource TextBrush}" FontSize="11" FontWeight="SemiBold"/>
          </Border>
          <Button x:Name="BtnRefresh" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0" Visibility="Visible"/>
          <Button x:Name="BtnFullAuto" Style="{StaticResource PrimaryButton}" Margin="0,0,12,0" Visibility="Visible"/>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="2,0,0,0">
            <Ellipse Width="7" Height="7" Fill="{DynamicResource GoodBrush}" Margin="0,0,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="Live" Foreground="{DynamicResource TextBrush}" FontSize="12" VerticalAlignment="Center"/>
          </StackPanel>
        </StackPanel>
      </Grid>

      <UniformGrid Grid.Row="1" Columns="5" Margin="0,0,0,12" Visibility="Visible">
        <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock x:Name="CpuLabel" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="CpuText" Foreground="{DynamicResource TextBrush}" FontSize="24" FontWeight="Bold" Margin="0,6,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="CpuDetailText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,5,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock x:Name="GpuLabel" Text="GPU" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="GpuText" Text="--" Foreground="{DynamicResource TextBrush}" FontSize="24" FontWeight="Bold" Margin="0,6,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="GpuDetailText" Text="Graphics load" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,5,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
        <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock x:Name="MemoryLabel" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="RamText" Foreground="{DynamicResource TextBrush}" FontSize="24" FontWeight="Bold" Margin="0,6,0,0"/>
            <TextBlock x:Name="RamDetailText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,5,0,0"/>
          </StackPanel>
        </Border>
        <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,10,0">
          <StackPanel>
            <TextBlock x:Name="DiskLabel" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="DiskText" Foreground="{DynamicResource TextBrush}" FontSize="24" FontWeight="Bold" Margin="0,6,0,0"/>
            <TextBlock x:Name="DiskDetailText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,5,0,0"/>
          </StackPanel>
        </Border>
        <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14">
          <StackPanel>
            <TextBlock x:Name="WindowsLabel" Foreground="{DynamicResource MutedBrush}" FontSize="12"/>
            <TextBlock x:Name="OsText" Foreground="{DynamicResource TextBrush}" FontSize="24" FontWeight="Bold" Margin="0,6,0,0" TextWrapping="Wrap"/>
            <TextBlock x:Name="UptimeText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,5,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </Border>
      </UniformGrid>

      <Grid Grid.Row="2">
        <Grid x:Name="PageOverview">
          <Grid.RowDefinitions>
            <RowDefinition Height="178"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="178"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="12" Margin="0,0,12,12" ToolTip="Open AI Doctor">
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
              <Border x:Name="HealthRingBorder" Width="104" Height="104" BorderBrush="{DynamicResource WarnBrush}" BorderThickness="9" CornerRadius="52" Background="{DynamicResource PanelAltBrush}">
                <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center">
                  <TextBlock x:Name="OverviewScoreText" Text="82" Foreground="{DynamicResource WarnBrush}" FontSize="23" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,14,0,0"/>
                  <TextBlock Text="/ 100" Foreground="{DynamicResource MutedBrush}" FontSize="10" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                </StackPanel>
              </Border>
              <TextBlock x:Name="OverviewHealthText" Text="GOOD" Foreground="{DynamicResource WarnBrush}" FontSize="12" FontWeight="Bold" Margin="0,8,0,2" HorizontalAlignment="Center"/>
              <TextBlock Text="AI Doctor Health" Foreground="{DynamicResource MutedBrush}" FontSize="11" HorizontalAlignment="Center"/>
            </StackPanel>
          </Border>

          <Border Grid.Column="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <DockPanel Margin="0,0,0,10">
                <TextBlock Text="Recommended Care" Foreground="{DynamicResource TextBrush}" FontSize="13" FontWeight="SemiBold" DockPanel.Dock="Left"/>
                <TextBlock x:Name="OverviewModeText" Text="SAFE MODE" Foreground="{DynamicResource GoodBrush}" FontSize="11" FontWeight="Bold" DockPanel.Dock="Right"/>
              </DockPanel>
              <UniformGrid Grid.Row="1" Columns="4">
                <Button x:Name="BtnOverviewDoctor" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0" Content="AI Doctor"/>
                <Button x:Name="BtnOverviewSafeCare" Style="{StaticResource PrimaryButton}" Margin="0,0,8,0" Content="Safe Care"/>
                <Button x:Name="BtnOverviewOptimize" Style="{StaticResource SecondaryButton}" Margin="0,0,8,0" Content="Optimize"/>
                <Button x:Name="BtnOverviewReports" Style="{StaticResource SecondaryButton}" Content="Reports"/>
              </UniformGrid>
            </Grid>
          </Border>

          <Border Grid.Row="1" Grid.ColumnSpan="2" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock Text="OPTIMIZATION MODULES" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="Bold" Margin="0,0,0,12"/>
              <UniformGrid x:Name="OverviewOperationRows" Grid.Row="1" Columns="4"/>
            </Grid>
          </Border>
        </Grid>

        <Grid x:Name="PageModules" Visibility="Collapsed">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14" Margin="0,0,0,12">
            <StackPanel>
              <TextBlock x:Name="ModulesTitleText" Foreground="{DynamicResource TextBrush}" FontSize="14" FontWeight="SemiBold"/>
              <TextBlock x:Name="ModulesNoteText" Foreground="{DynamicResource MutedBrush}" FontSize="11" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="14">
            <UniformGrid x:Name="OperationRows" Columns="4"/>
          </Border>
        </Grid>

        <Grid x:Name="PageAi" Visibility="Collapsed">
          <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="16">
            <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <TextBlock x:Name="AiPanelText" Foreground="{DynamicResource TextBrush}" FontSize="18" FontWeight="SemiBold"/>
                <TextBlock x:Name="AiNoteText" Foreground="{DynamicResource MutedBrush}" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,14"/>
                <Border Background="{DynamicResource PanelAltBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="8" Padding="12" Margin="0,0,0,14">
                  <TextBlock x:Name="AiStatusText" Foreground="{DynamicResource TextBrush}" FontSize="12" TextWrapping="Wrap"/>
                </Border>
                <Button x:Name="BtnAiAdvisor2" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8"/>
                <Button x:Name="BtnAiOperator2" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
                <Button x:Name="BtnAiProviders2" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
                <Button x:Name="BtnStartMiniTray" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
                <Button x:Name="BtnCloudStatus" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8"/>
                <Button x:Name="BtnCloudOpen" Style="{StaticResource SecondaryButton}" Margin="0,0,0,10"/>
                <Button x:Name="BtnNullClawDocs" Style="{StaticResource SecondaryButton}" Visibility="Collapsed"/>
                <TextBlock Text="AI CONNECTORS" Foreground="{DynamicResource MutedBrush}" FontSize="10" FontWeight="Bold" Margin="0,6,0,8"/>
                <StackPanel x:Name="ConnectorRows"/>
              </StackPanel>
            </ScrollViewer>
          </Border>
        </Grid>

        <Grid x:Name="PageReports" Visibility="Collapsed">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="1*"/>
            <ColumnDefinition Width="1*"/>
          </Grid.ColumnDefinitions>
          <Border Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="16" Margin="0,0,10,0">
            <StackPanel>
              <TextBlock x:Name="TaskQueueTitleText" Foreground="{DynamicResource TextBrush}" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock x:Name="TaskQueueEmptyText" Foreground="{DynamicResource MutedBrush}" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,14"/>
              <Border Background="{DynamicResource PanelAltBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="18" Height="140">
                <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                  <TextBlock Text="STATUS" Foreground="{DynamicResource MutedBrush}" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                  <TextBlock Text="No task is running." Foreground="{DynamicResource TextBrush}" FontSize="12" TextWrapping="Wrap" TextAlignment="Center"/>
                </StackPanel>
              </Border>
            </StackPanel>
          </Border>
          <Border Grid.Column="1" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="16">
            <StackPanel>
              <TextBlock Text="Reports &amp; Tools" Foreground="{DynamicResource TextBrush}" FontSize="18" FontWeight="SemiBold"/>
              <TextBlock Text="Open reports, disk status, profile audit, or AI model settings without crowding the dashboard." Foreground="{DynamicResource MutedBrush}" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,14"/>
              <Button x:Name="BtnOpenReports" Style="{StaticResource PrimaryButton}" Margin="0,0,0,8" Content="Open Reports"/>
              <Button x:Name="BtnDiskStatusPage" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8" Content="Disk Status"/>
              <Button x:Name="BtnProfilePage" Style="{StaticResource SecondaryButton}" Margin="0,0,0,8" Content="Profile Audit"/>
              <Button x:Name="BtnModelSettingsPage" Style="{StaticResource SecondaryButton}" Content="AI Model Settings"/>
            </StackPanel>
          </Border>
        </Grid>
      </Grid>

      <Border x:Name="WorkerPanel" Grid.Row="3" Background="{DynamicResource WorkerBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="10" Margin="0,12,0,0" MinHeight="118" Visibility="Visible">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <DockPanel Margin="0,0,0,7">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
              <Button x:Name="BtnClearWorker" Style="{StaticResource SecondaryButton}" Content="Clear" MinHeight="28" Padding="10,5" Margin="0,0,8,0"/>
              <Button x:Name="BtnOpenWorkerLog" Style="{StaticResource SecondaryButton}" Content="Open Log" MinHeight="28" Padding="10,5"/>
            </StackPanel>
            <TextBlock x:Name="WorkerTitleText" Text="Worker Output" Foreground="{DynamicResource TextBrush}" FontSize="12" FontWeight="SemiBold" DockPanel.Dock="Left"/>
          </DockPanel>
          <TextBox x:Name="WorkerOutputText"
                   Grid.Row="1"
                   Text="Worker idle. Run a module to see live transcript here."
                   Background="{DynamicResource PanelAltBrush}"
                   Foreground="{DynamicResource TextBrush}"
                   BorderBrush="{DynamicResource LineBrush}"
                   BorderThickness="1"
                   Padding="9,7"
                   FontFamily="{DynamicResource MonoFontFamily}"
                   FontSize="10"
                   IsReadOnly="True"
                   AcceptsReturn="True"
                   TextWrapping="Wrap"
                   VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Disabled"
                   MinHeight="72"/>
        </Grid>
      </Border>

      <Border Grid.Row="4" Background="{DynamicResource PanelBrush}" BorderBrush="{DynamicResource LineBrush}" BorderThickness="1" CornerRadius="12" Padding="10" Margin="0,10,0,0" Visibility="Visible">
        <DockPanel>
          <TextBlock Text="Status" Foreground="{DynamicResource MutedBrush}" FontSize="12" DockPanel.Dock="Left" Margin="0,0,12,0"/>
          <TextBlock x:Name="StatusText" Foreground="{DynamicResource TextBrush}" FontSize="12"/>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

try {
    $xml = [xml]$xaml
    $reader = [System.Xml.XmlNodeReader]::new($xml)
    $Window = [System.Windows.Markup.XamlReader]::Load($reader)
} catch {
    Write-UiLog "XAML load failed: $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("NeoOptimize UI failed to load: $($_.Exception.Message)", "NeoOptimize", "OK", "Error") | Out-Null
    exit 1
}

function Find-Control {
    param([string]$Name)
    return $Window.FindName($Name)
}

function Set-ControlValue {
    param(
        [string]$Name,
        [object]$Value,
        [string]$PreferredProperty = "Text"
    )

    $ctrl = Find-Control $Name
    if (-not $ctrl) { return }

    $preferred = $ctrl.GetType().GetProperty($PreferredProperty)
    if ($preferred) {
        $preferred.SetValue($ctrl, $Value, $null)
        return
    }

    $fallback = $ctrl.GetType().GetProperty("Content")
    if ($fallback) {
        $fallback.SetValue($ctrl, $Value, $null)
    }
}

function Set-ControlText {
    param([string]$Name, [object]$Value)
    Set-ControlValue -Name $Name -Value $Value -PreferredProperty "Text"
}

function Set-ControlContent {
    param([string]$Name, [object]$Value)
    Set-ControlValue -Name $Name -Value $Value -PreferredProperty "Content"
}

function Add-ControlClick {
    param([string]$Name, [scriptblock]$Handler)
    $ctrl = Find-Control $Name
    if ($ctrl -and $ctrl.GetType().GetEvent("Click")) {
        $handlerClosure = $Handler.GetNewClosure()
        $ctrl.Add_Click({
            if ($Script:UiTaskRunning) {
                Show-NeoBusyNotice
                return
            }
            try {
                & $handlerClosure
            } catch {
                $message = $_.Exception.Message
                Write-UiLog "UI action failed for ${Name}: $message"
                End-NeoUiTask -Message ("Action failed: {0}" -f $Name)
                try {
                    [System.Windows.MessageBox]::Show(
                        ("NeoOptimize action failed:`n{0}" -f $message),
                        "NeoOptimize",
                        "OK",
                        "Warning"
                    ) | Out-Null
                } catch {}
            }
        }.GetNewClosure())
    }
}

function Set-ResourceColor {
    param([string]$Name, [string]$Color)
    $Window.Resources[$Name] = New-Brush $Color
}

function New-Brush {
    param([string]$Color)
    return $Script:BrushConverter.ConvertFromString($Color)
}

function Apply-BrandAssets {
    try {
        if (Test-Path $Script:IconPath) {
            $Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($Script:IconPath, [System.UriKind]::Absolute))
        }
        $logo = Find-Control "BrandLogoImage"
        if ($logo -and (Test-Path $Script:LogoPath)) {
            $logo.Source = [System.Windows.Media.Imaging.BitmapImage]::new([System.Uri]::new($Script:LogoPath, [System.UriKind]::Absolute))
        }
    } catch {
        Write-UiLog "Brand asset load failed: $($_.Exception.Message)"
    }
}

function Apply-Theme {
    $theme = Resolve-Theme
    if ($theme -eq "light") {
        $colors = @{
            Page="#F4F7FB"; Sidebar="#101826"; Panel="#FFFFFF"; PanelAlt="#F8FAFC"; Line="#D7E0EC"
            Text="#0F172A"; SidebarText="#F8FAFC"; Muted="#5B677A"; Accent="#0284C7"; AccentText="#FFFFFF"
            Good="#059669"; Warn="#B45309"; Nav="#182235"; NavHover="#243044"; Pressed="#111827"; Danger="#DC2626"
        }
    } else {
        $colors = @{
            Page="#06080D"; Sidebar="#080F1A"; Panel="#121B2B"; PanelAlt="#0C121D"; Line="#14FFFFFF"
            Text="#FFFFFF"; SidebarText="#FFFFFF"; Muted="#A0AEC0"; Accent="#00F0FF"; AccentText="#05131C"
            Good="#00FF9D"; Warn="#FFCC00"; Nav="#08111B"; NavHover="#10192A"; Pressed="#071018"; Danger="#FF3366"
        }
    }
    Set-ResourceColor "PageBrush" $colors.Page
    Set-ResourceColor "SidebarBrush" $colors.Sidebar
    Set-ResourceColor "PanelBrush" $colors.Panel
    Set-ResourceColor "PanelAltBrush" $colors.PanelAlt
    Set-ResourceColor "LineBrush" $colors.Line
    Set-ResourceColor "TextBrush" $colors.Text
    Set-ResourceColor "SidebarTextBrush" $colors.SidebarText
    Set-ResourceColor "MutedBrush" $colors.Muted
    Set-ResourceColor "AccentBrush" $colors.Accent
    Set-ResourceColor "AccentTextBrush" $colors.AccentText
    Set-ResourceColor "GoodBrush" $colors.Good
    Set-ResourceColor "WarnBrush" $colors.Warn
    Set-ResourceColor "NavBrush" $colors.Nav
    Set-ResourceColor "NavHoverBrush" $colors.NavHover
    Set-ResourceColor "PressedBrush" $colors.Pressed
    Set-ResourceColor "DangerBrush" $colors.Danger
}

function Set-Status {
    param([string]$Text)
    Set-ControlText -Name "StatusText" -Value $Text
}

function Set-WorkerTitle {
    param([string]$Text)
    Set-ControlText -Name "WorkerTitleText" -Value $Text
}

function Set-WorkerOutput {
    param([string]$Text)
    $box = Find-Control "WorkerOutputText"
    if (-not $box) { return }
    $box.Text = if ([string]::IsNullOrWhiteSpace($Text)) { "Worker has not written output yet." } else { $Text }
    try {
        $box.CaretIndex = $box.Text.Length
        $box.ScrollToEnd()
    } catch {}
}

function Get-TailText {
    param(
        [string]$Path,
        [int]$Tail = 90
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) { return "" }
    try {
        return ((Get-Content -Path $Path -Tail $Tail -ErrorAction Stop) -join [Environment]::NewLine).Trim()
    } catch {
        return ""
    }
}

function Get-NeoSafeFileLabel {
    param([string]$Label)
    $safe = ([string]$Label -replace '[^A-Za-z0-9_.-]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "worker" }
    return $safe
}

function New-NeoWorkerFiles {
    param([string]$Label)
    if (-not (Test-Path $Script:WorkerReportsPath)) {
        New-Item -Path $Script:WorkerReportsPath -ItemType Directory -Force | Out-Null
    }
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safe = Get-NeoSafeFileLabel $Label
    return [PSCustomObject]@{
        Stdout = Join-Path $Script:WorkerReportsPath "${stamp}_${safe}.stdout.log"
        Stderr = Join-Path $Script:WorkerReportsPath "${stamp}_${safe}.stderr.log"
        Transcript = Join-Path $Script:WorkerReportsPath "${stamp}_${safe}.transcript.log"
    }
}

function Update-NeoWorkerOutput {
    param(
        [string]$Label = $Script:WorkerLastLabel,
        [int]$ExitCode = -9999
    )

    $blocks = New-Object System.Collections.Generic.List[string]
    $transcript = Get-TailText -Path $Script:WorkerTranscriptPath -Tail 120
    $stdout = Get-TailText -Path $Script:WorkerStdoutPath -Tail 80
    $stderr = Get-TailText -Path $Script:WorkerStderrPath -Tail 80

    if ($transcript) { $blocks.Add("=== TRANSCRIPT ===`r`n$transcript") }
    if ($stdout) { $blocks.Add("=== STDOUT ===`r`n$stdout") }
    if ($stderr) { $blocks.Add("=== STDERR ===`r`n$stderr") }

    $suffix = if ($ExitCode -eq -9999) { "running" } else { "exit $ExitCode" }
    Set-WorkerTitle ("Worker Output - {0} ({1})" -f $Label, $suffix)

    if ($blocks.Count -eq 0) {
        Set-WorkerOutput ("Worker starting: {0}`r`nTranscript: {1}`r`nStdout: {2}`r`nStderr: {3}" -f $Label, $Script:WorkerTranscriptPath, $Script:WorkerStdoutPath, $Script:WorkerStderrPath)
        return
    }

    $text = ($blocks -join "`r`n`r`n")
    if ($text.Length -gt 18000) {
        $text = $text.Substring($text.Length - 18000)
    }
    Set-WorkerOutput $text
}

function Clear-NeoWorkerOutput {
    $Script:WorkerLastLabel = ""
    Set-WorkerTitle "Worker Output"
    Set-WorkerOutput "Worker idle. Run a module to see live transcript here."
}

function Open-NeoWorkerLog {
    $target = if (Test-Path $Script:WorkerTranscriptPath) { $Script:WorkerTranscriptPath } elseif (Test-Path $Script:WorkerStdoutPath) { $Script:WorkerStdoutPath } else { $Script:WorkerReportsPath }
    try {
        Start-Process $target | Out-Null
        Set-Status "Opened worker log."
    } catch {
        Write-UiLog "Open worker log failed: $($_.Exception.Message)"
        Set-Status "Cannot open worker log."
    }
}

function Get-NeoVisualChildren {
    param([System.Windows.DependencyObject]$Parent)

    $items = New-Object System.Collections.ArrayList
    if (-not $Parent) { return @() }

    try {
        $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent)
    } catch {
        return @()
    }

    for ($i = 0; $i -lt $count; $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        [void]$items.Add($child)
        foreach ($nested in (Get-NeoVisualChildren $child)) {
            [void]$items.Add($nested)
        }
    }

    return @($items)
}

function Show-NeoBusyNotice {
    $label = if ([string]::IsNullOrWhiteSpace($Script:UiTaskName)) { "NeoOptimize task" } else { $Script:UiTaskName }
    Set-Status ("Task sedang berjalan: {0}" -f $label)
    $notice = Find-Control "TaskRunningNotice"
    $text = Find-Control "TaskRunningText"
    if ($text) { $text.Text = ("Running: {0}" -f $label) }
    if ($notice) { $notice.Visibility = "Visible" }
}

function Set-NeoUiBusy {
    param(
        [bool]$Busy,
        [string]$Label = ""
    )

    $Script:UiTaskRunning = $Busy
    $Script:UiTaskName = if ($Busy) { $Label } else { "" }

    $notice = Find-Control "TaskRunningNotice"
    $text = Find-Control "TaskRunningText"
    if ($notice) { $notice.Visibility = if ($Busy) { "Visible" } else { "Collapsed" } }
    if ($text) { $text.Text = if ($Busy) { ("Running: {0}" -f $Label) } else { "Task is running..." } }

    try {
        foreach ($button in (Get-NeoVisualChildren $Window | Where-Object { $_ -is [System.Windows.Controls.Button] })) {
            $button.IsEnabled = $true
        }
    } catch {
        Write-UiLog "Busy button state update failed: $($_.Exception.Message)"
    }

    $rows = Find-Control "OperationRows"
    if ($rows) {
        foreach ($child in $rows.Children) {
            $child.IsEnabled = -not $Busy
            $child.Opacity = if ($Busy) { 0.55 } else { 1.0 }
            $child.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { [System.Windows.Input.Cursors]::Hand }
        }
    }

    $Window.Cursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { [System.Windows.Input.Cursors]::Arrow }
    if ($Busy) {
        Set-Status ("Task sedang berjalan: {0}" -f $Label)
    }
}

function Try-BeginNeoUiTask {
    param([string]$Label)
    if ($Script:UiTaskRunning) {
        Show-NeoBusyNotice
        return $false
    }
    Set-NeoUiBusy -Busy $true -Label $Label
    return $true
}

function End-NeoUiTask {
    param([string]$Message = "")
    if ($Script:UiTaskTimer) {
        try { $Script:UiTaskTimer.Stop() } catch {}
        $Script:UiTaskTimer = $null
    }
    Set-NeoUiBusy -Busy $false
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        Set-Status $Message
    }
}

function Watch-NeoProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [string]$Label
    )

    if (-not $Process) {
        End-NeoUiTask -Message ("Task finished: {0}" -f $Label)
        return
    }

    if ($Script:UiTaskTimer) {
        try { $Script:UiTaskTimer.Stop() } catch {}
    }

    $startedAt = [DateTime]::UtcNow
    $longRunningLabels = @("SystemRepair", "WindowsErrorFix", "DiskRepair", "Services", "DefenderAuditMode", "Permissions", "Apps", "Autoimmune", (T "FullAuto"))
    $timeoutSeconds = if ($Label -in $longRunningLabels) { 900 } else { 90 }

    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        try {
            try { $Process.Refresh() } catch {}
            Update-NeoWorkerOutput -Label $Label
            if ($Process.HasExited) {
                $timer.Stop()
                $exit = $Process.ExitCode
                $Script:UiTaskTimer = $null
                Update-NeoWorkerOutput -Label $Label -ExitCode $exit
                End-NeoUiTask -Message ("Task finished: {0} (exit {1})" -f $Label, $exit)
            } elseif ((([DateTime]::UtcNow - $startedAt).TotalSeconds) -gt $timeoutSeconds) {
                $timer.Stop()
                $Script:UiTaskTimer = $null
                Update-NeoWorkerOutput -Label $Label
                End-NeoUiTask -Message ("Task monitor released: {0}" -f $Label)
            } else {
                Show-NeoBusyNotice
            }
        } catch {
            $timer.Stop()
            $Script:UiTaskTimer = $null
            End-NeoUiTask -Message ("Task state refreshed: {0}" -f $Label)
        }
    })
    $Script:UiTaskTimer = $timer
    $timer.Start()
}

function Invoke-NeoUiTask {
    param(
        [string]$Label,
        [scriptblock]$Work
    )

    if (-not (Try-BeginNeoUiTask $Label)) { return }
    try {
        & $Work
    } finally {
        End-NeoUiTask -Message ("Ready after: {0}" -f $Label)
    }
}

function Set-ComboSelectionByTag {
    param($Combo, [string]$Tag)
    for ($i = 0; $i -lt $Combo.Items.Count; $i++) {
        if ([string]$Combo.Items[$i].Tag -eq $Tag) {
            $Combo.SelectedIndex = $i
            return
        }
    }
}

function Resolve-FontFamily {
    param(
        [string]$RelativePath,
        [string]$FamilyName,
        [string]$Fallback = "Segoe UI"
    )

    $fontPath = Join-Path $Script:Root $RelativePath
    try {
        if (Test-Path $fontPath) {
            $uri = [System.Uri]::new((Resolve-Path $fontPath).Path, [System.UriKind]::Absolute).AbsoluteUri
            return [System.Windows.Media.FontFamily]::new("$uri#$FamilyName")
        }
    } catch {
        Write-UiLog "Font load failed for ${RelativePath}: $($_.Exception.Message)"
    }

    try {
        return [System.Windows.Media.FontFamily]::new($Fallback)
    } catch {
        return [System.Windows.Media.FontFamily]::new("Segoe UI")
    }
}

function Apply-Fonts {
    $main = Resolve-FontFamily -RelativePath "assets\fonts\Inter-Variable.ttf" -FamilyName "Inter" -Fallback "Segoe UI Variable"
    $mono = Resolve-FontFamily -RelativePath "assets\fonts\JetBrainsMono-Variable.ttf" -FamilyName "JetBrains Mono" -Fallback "Cascadia Mono"

    $Window.Resources["MainFontFamily"] = $main
    $Window.Resources["MonoFontFamily"] = $mono
    $Window.FontFamily = $main

    foreach ($name in @(
        "RmmDetailText",
        "AiStatusText",
        "StatusText",
        "WorkerTitleText",
        "WorkerOutputText"
    )) {
        $ctrl = Find-Control $name
        if ($ctrl) { $ctrl.FontFamily = $mono }
    }
}

function Start-NeoProcess {
    param([string]$Label, [string]$CommandText)
    try {
        $workerFiles = New-NeoWorkerFiles -Label $Label
        $Script:WorkerStdoutPath = $workerFiles.Stdout
        $Script:WorkerStderrPath = $workerFiles.Stderr
        $Script:WorkerTranscriptPath = $workerFiles.Transcript
        $Script:WorkerLastLabel = $Label
        Set-WorkerTitle ("Worker Output - {0} (starting)" -f $Label)
        Set-WorkerOutput ("Starting local NeoOptimize worker: {0}`r`nTranscript: {1}" -f $Label, $Script:WorkerTranscriptPath)

        $safeTitle = ($Label -replace "'", "''")
        $consolePrelude = "try { `$host.UI.RawUI.WindowTitle = 'NeoOptimize - $safeTitle'; `$host.UI.RawUI.WindowSize = [System.Management.Automation.Host.Size]::new(108,32); `$host.UI.RawUI.BufferSize = [System.Management.Automation.Host.Size]::new(108,3000) } catch {}"
        $transcriptLiteral = Quote-PsLiteral $Script:WorkerTranscriptPath
        $wrappedCommand = "$consolePrelude; `$neoExitCode = 0; try { Start-Transcript -Path $transcriptLiteral -Force | Out-Null } catch {}; try { $CommandText } catch { Write-Error `$_; `$neoExitCode = 1 }; try { Stop-Transcript | Out-Null } catch {}; Start-Sleep -Seconds 2; if (`$neoExitCode -ne 0) { exit `$neoExitCode }"
        $argumentText = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command $(Quote-Arg $wrappedCommand)"
        $proc = Start-Process -FilePath (Get-PowerShellExe) -ArgumentList $argumentText -WorkingDirectory $Script:Root -WindowStyle Hidden -RedirectStandardOutput $Script:WorkerStdoutPath -RedirectStandardError $Script:WorkerStderrPath -PassThru
        Write-UiLog "Started action '$Label' as PID $($proc.Id)."
        Set-Status ("Action running with administrator access: {0}" -f $Label)
        Watch-NeoProcess -Process $proc -Label $Label
        return $true
    } catch {
        Write-UiLog "Failed to start action '$Label': $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show(("Cannot start {0}: {1}" -f $Label, $_.Exception.Message), "NeoOptimize", "OK", "Error") | Out-Null
        return $false
    }
}

function Confirm-NeoUiAction {
    param(
        [string]$Title,
        [string]$Message
    )
    $result = [System.Windows.MessageBox]::Show($Message, $Title, "YesNo", "Warning")
    return ($result -eq [System.Windows.MessageBoxResult]::Yes)
}

function Start-NeoAction {
    param([string]$Action)

    if ($Action -eq "NeoUpdate") {
        Show-NeoUpdateManagerDialog
        return
    }
    if ($Action -eq "AIPlan") {
        Invoke-AiDoctor
        return
    }
    if ($Action -eq "AIInteractive") {
        Show-NeoAiPage -NavName "BtnAudit"
        Set-ControlText "AiStatusText" "NEO interactive chat is available from the mini tray. The main NeoOptimize UI stays clean for monitoring, modules, reports, and settings."
        Start-NeoMiniTray -OpenChat
        Set-Status "NEO chat opened from mini tray."
        return
    }
    if ($Action -eq "AIProviders") {
        Invoke-NeoAiPanelTool -Mode "Providers"
        return
    }
    if ($Action -eq "AIEnvironment") {
        Invoke-NeoAiPanelTool -Mode "Environment"
        return
    }
    if ($Action -eq "AICatalog") {
        Invoke-NeoAiPanelTool -Mode "Catalog"
        return
    }
    if ($Action -eq "AIScriptForge") {
        Invoke-NeoAiPanelTool -Mode "ScriptForge" -Question "Create a read-only PowerShell system audit and Windows maintenance script with safe defaults."
        return
    }
    if ($Action -eq "VoiceCommand") {
        $voice = Join-Path $Script:Root "NeoOptimize.VoiceCommand.ps1"
        if (Test-Path $voice) {
            Start-Process -FilePath (Get-PowerShellExe) -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $(Quote-Arg $voice)" -WorkingDirectory $Script:Root -WindowStyle Hidden | Out-Null
            Set-Status "Voice command opened."
        }
        return
    }
    if (-not (Test-NeoUiActionAvailable $Action)) {
        Set-Status ("{0} is not available in this NeoOptimize build." -f $Action)
        Write-UiLog "Action '$Action' is not present in the engine ValidateSet."
        return
    }

    if (-not (Try-BeginNeoUiTask $Action)) { return }
    $processOwnsBusyState = $false

    try {
        if ($Action -eq "Dashboard") {
            Update-SystemDashboard
            Set-Status "Dashboard refreshed."
            return
        }
        if ($Action -eq "FreeAgentProviders") {
            Update-AiProviderStatus
            Set-Status (T "Providers")
            return
        }
        if ($Action -eq "AIModelSettings") {
            Show-AiModelSettings
            return
        }
        if ($Action -in @("SystemRepair", "WindowsErrorFix", "DiskRepair", "Services", "DefenderAuditMode", "Permissions", "Apps", "Autoimmune")) {
            if (-not (Confirm-NeoUiAction -Title "Confirm $Action" -Message "$Action can change Windows configuration. Continue with hidden worker execution?")) {
                Set-Status "$Action cancelled."
                return
            }
        }
        if (-not (Test-Path $Script:EnginePath)) {
            [System.Windows.MessageBox]::Show((T "MissingEngine"), "NeoOptimize", "OK", "Error") | Out-Null
            return
        }
        $localOnlyActions = @("AIInteractive", "NEOAgentic", "AIScriptForge", "AICatalog", "AIProviders", "AIEnvironment", "VoiceCommand", "NeoUpdate")
        $rmmCfg = Read-RmmConfig
        if (($Action -notin $localOnlyActions) -and $rmmCfg.dispatch_to_online_agents -and (Invoke-RmmDispatch $Action)) {
            Set-WorkerTitle ("RMM Worker - {0} (hidden endpoint execution)" -f $Action)
            Set-WorkerOutput ("Queued {0} through RMM.`r`nEndpoint worker remains hidden by design. Watch RMM command history and agent telemetry for stdout/stderr/report results." -f $Action)
            Update-SystemDashboard
            return
        }
        $command = "& $(Quote-Arg $Script:EnginePath) -Action $Action"
        if (Start-NeoProcess -Label $Action -CommandText $command) {
            $processOwnsBusyState = $true
        }
    } finally {
        if (-not $processOwnsBusyState) {
            End-NeoUiTask -Message ("Ready after: {0}" -f $Action)
        }
    }
}

function Start-NeoFullAuto {
    if ($Script:UiTaskRunning) {
        Show-NeoBusyNotice
        return
    }
    if (-not (Confirm-NeoUiAction -Title (T "ConfirmTitle") -Message (T "ConfirmFullAuto"))) {
        Set-Status "Safe Care cancelled."
        return
    }
    if (-not (Try-BeginNeoUiTask (T "FullAuto"))) { return }
    $processOwnsBusyState = $false
    try {
        $command = "& $(Quote-Arg $Script:EnginePath) -FullAuto"
        if (Start-NeoProcess -Label (T "FullAuto") -CommandText $command) {
            $processOwnsBusyState = $true
        }
    } finally {
        if (-not $processOwnsBusyState) {
            End-NeoUiTask -Message "Ready after Safe Care."
        }
    }
}

function Invoke-AiDoctor {
    if (-not (Try-BeginNeoUiTask "AI Doctor")) { return }
    $aiScript = Join-Path $Script:Root "NeoOptimize.AIAgent.ps1"
    try {
        if (-not (Test-Path $aiScript)) {
            [System.Windows.MessageBox]::Show("NeoOptimize AI Doctor script was not found.", "NeoOptimize AI Doctor", "OK", "Error") | Out-Null
            return
        }
        Show-NeoAiPage -NavName "BtnAudit"
        Set-ControlText "AiStatusText" "Running AI Doctor with NeoCore, local model fallback, NullClaw bridge, skills, MCP catalog, and telemetry envelope..."
        $answer = Invoke-NeoAiCapture -Mode "Plan" -TimeoutMs 120000
        Set-NeoAiStatusOutput $answer
    } finally {
        End-NeoUiTask -Message "Ready after AI Doctor."
    }
}

function Invoke-NeoAiCapture {
    param(
        [ValidateSet("Plan", "Interactive", "Environment", "Policy", "Providers", "Roles", "Catalog", "ScriptForge")]
        [string]$Mode,
        [string]$Question = "",
        [int]$TimeoutMs = 90000
    )

    $agent = Join-Path $Script:Root "NeoOptimize.AIAgent.ps1"
    if (-not (Test-Path $agent)) { return "NeoOptimize.AIAgent.ps1 was not found." }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Get-PowerShellExe
    $psi.WorkingDirectory = $Script:Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $args = "-NoProfile -ExecutionPolicy Bypass -File $(Quote-Arg $agent) -Mode $Mode -NoOpen"
    if (-not [string]::IsNullOrWhiteSpace($Question)) {
        $args = "$args -Question $(Quote-Arg $Question)"
    }
    $psi.Arguments = $args

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { return "NEO could not start." }
    if (-not $proc.WaitForExit($TimeoutMs)) {
        try { $proc.Kill() } catch {}
        return "NEO timed out. Try a shorter task, or check model/provider status."
    }

    $stdout = $proc.StandardOutput.ReadToEnd().Trim()
    $stderr = $proc.StandardError.ReadToEnd().Trim()
    if ($stdout) { return $stdout }
    if ($stderr) { return $stderr }
    return "NEO completed but returned no text output. Check reports\\ai for generated reports."
}

function Append-NeoChat {
    param([string]$Role, [string]$Text)
    $history = Find-Control "NeoChatHistory"
    if (-not $history) { return }
    $cleanText = if ([string]::IsNullOrWhiteSpace($Text)) { "(empty)" } else { $Text.Trim() }
    $history.AppendText(("{0}: {1}`r`n`r`n" -f $Role, $cleanText))
    try {
        $history.SelectionStart = $history.Text.Length
        $history.ScrollToEnd()
    } catch {}
}

function Set-NeoAiStatusOutput {
    param([string]$Text)
    $cleanText = if ([string]::IsNullOrWhiteSpace($Text)) { "NEO returned no output. Check reports\\ai for details." } else { $Text.Trim() }
    if ($cleanText.Length -gt 1800) {
        $cleanText = $cleanText.Substring(0, 1800) + "`r`n`r`nOutput truncated. Full reports are stored in reports\\ai."
    }
    Set-ControlText "AiStatusText" $cleanText
}

function Invoke-NeoChatQuestion {
    $input = Find-Control "NeoChatInput"
    if (-not $input) { return }
    $question = [string]$input.Text
    if ([string]::IsNullOrWhiteSpace($question)) { return }
    $input.Text = ""
    if (-not (Try-BeginNeoUiTask "NEO Chat")) { return }
    try {
        Append-NeoChat "You" $question
        Append-NeoChat "System" "NEO is reading local telemetry, skills, MCP connectors, model providers, and safety policy."
        $answer = Invoke-NeoAiCapture -Mode "Interactive" -Question $question -TimeoutMs 90000
        Append-NeoChat "NEO" $answer
    } finally {
        End-NeoUiTask -Message "Ready after NEO chat."
    }
}

function Invoke-NeoAiPanelTool {
    param(
        [ValidateSet("Environment", "Policy", "Providers", "Roles", "Catalog", "ScriptForge")]
        [string]$Mode,
        [string]$Question = ""
    )
    if (-not (Try-BeginNeoUiTask "NEO $Mode")) { return }
    try {
        Show-NeoAiPage -NavName "BtnAudit"
        Set-ControlText "AiStatusText" "Running NEO $Mode..."
        $answer = Invoke-NeoAiCapture -Mode $Mode -Question $Question -TimeoutMs 90000
        Set-NeoAiStatusOutput $answer
    } finally {
        End-NeoUiTask -Message "Ready after NEO $Mode."
    }
}

function Start-NeoMiniTray {
    param([switch]$OpenChat)
    try {
        $launcher = Join-Path $Script:Root "NeoOptimize.Launcher.ps1"
        $tray = Join-Path $Script:Root "NeoOptimize.Tray.ps1"
        $trayArgs = if ($OpenChat) { " -OpenChat" } else { "" }
        if (Test-Path $launcher) {
            $launcherArgs = if ($OpenChat) { "-Tray -OpenChat" } else { "-Tray" }
            Start-Process -FilePath (Get-PowerShellExe) -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $(Quote-Arg $launcher) $launcherArgs" -WorkingDirectory $Script:Root -WindowStyle Hidden | Out-Null
        } elseif (Test-Path $tray) {
            Start-Process -FilePath (Get-PowerShellExe) -ArgumentList "-Sta -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $(Quote-Arg $tray)$trayArgs" -WorkingDirectory $Script:Root -WindowStyle Hidden | Out-Null
        } else {
            [System.Windows.MessageBox]::Show("NeoOptimize tray companion was not found.", "NeoOptimize", "OK", "Warning") | Out-Null
            return
        }
        Set-Status "Mini tray companion started. Check the Windows notification area."
    } catch {
        Write-UiLog "Mini tray start failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Cannot start mini tray: $($_.Exception.Message)", "NeoOptimize", "OK", "Error") | Out-Null
    }
}

function Open-ReportsFolder {
    if (-not (Test-Path $Script:ReportsPath)) { New-Item -Path $Script:ReportsPath -ItemType Directory -Force | Out-Null }
    $LatestLog = Get-ChildItem -Path $Script:ReportsPath -Filter "*.log" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($LatestLog) {
        Start-Process notepad.exe -ArgumentList (Quote-Arg $LatestLog.FullName)
        Set-Status "Opened latest report log."
    } else {
        Start-Process notepad.exe -ArgumentList (Quote-Arg "$Script:ReportsPath\NeoOptimize.log")
        Set-Status "Opened report log path."
    }
}

function Open-ConfigFolder {
    $configDir = Split-Path -Parent $Script:ConfigPath
    if (-not (Test-Path $configDir)) { New-Item -Path $configDir -ItemType Directory -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList (Quote-Arg $configDir)
    Set-Status "Opened NeoOptimize config folder."
}

function Test-NeoProfileComplete {
    return (-not [string]::IsNullOrWhiteSpace($Script:UserName)) -and (-not [string]::IsNullOrWhiteSpace($Script:UserPhone))
}

function Show-NeoProfileLoginDialog {
    param([switch]$Force)

    if ((-not $Force) -and (Test-NeoProfileComplete)) { return $true }

    $profileXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NeoOptimize Login"
        Width="440"
        Height="360"
        WindowStartupLocation="CenterOwner"
        ResizeMode="NoResize"
        Background="#07101D">
  <Border Margin="16" Background="#111C2E" BorderBrush="#263A56" BorderThickness="1" CornerRadius="14" Padding="18">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Text="NeoOptimize Login" Foreground="#E6EEF8" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock Grid.Row="1" Text="Local profile for NeoOptimize only. RMM keeps username and password login." Foreground="#8B98AB" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,18"/>

      <StackPanel Grid.Row="2" Margin="0,0,0,12">
        <TextBlock Text="Name" Foreground="#AAB8CC" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <TextBox x:Name="ProfileNameBox" Height="36" Background="#0B1322" Foreground="#E6EEF8" BorderBrush="#263A56" Padding="10,7" FontSize="13"/>
      </StackPanel>

      <StackPanel Grid.Row="3" Margin="0,0,0,12">
        <TextBlock Text="Phone Number" Foreground="#AAB8CC" FontSize="12" FontWeight="SemiBold" Margin="0,0,0,6"/>
        <TextBox x:Name="ProfilePhoneBox" Height="36" Background="#0B1322" Foreground="#E6EEF8" BorderBrush="#263A56" Padding="10,7" FontSize="13"/>
      </StackPanel>

      <TextBlock x:Name="ProfileMessageText" Grid.Row="4" Foreground="#FFCC33" FontSize="12" TextWrapping="Wrap"/>

      <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="ProfileSkipButton" Content="Later" Width="86" Height="34" Margin="0,0,8,0" Background="#132136" Foreground="#E6EEF8" BorderBrush="#263A56"/>
        <Button x:Name="ProfileSaveButton" Content="Save" Width="100" Height="34" Background="#00D6E6" Foreground="#020812" BorderBrush="#00D6E6" FontWeight="SemiBold"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

    try {
        $reader = [System.Xml.XmlNodeReader]::new(([xml]$profileXaml))
        $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
        if ($Window) { $dialog.Owner = $Window }

        $nameBox = $dialog.FindName("ProfileNameBox")
        $phoneBox = $dialog.FindName("ProfilePhoneBox")
        $messageText = $dialog.FindName("ProfileMessageText")
        $saveButton = $dialog.FindName("ProfileSaveButton")
        $skipButton = $dialog.FindName("ProfileSkipButton")

        if ($nameBox) { $nameBox.Text = [string]$Script:UserName }
        if ($phoneBox) { $phoneBox.Text = [string]$Script:UserPhone }
        if ($messageText) { $messageText.Text = "This profile is stored locally in NeoOptimize config." }

        $saveButton.Add_Click({
            $name = ([string]$nameBox.Text).Trim()
            $phone = ([string]$phoneBox.Text).Trim()
            if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($phone)) {
                $messageText.Text = "Name and phone number are required for the NeoOptimize local profile."
                return
            }
            $Script:UserName = $name
            $Script:UserPhone = $phone
            if ([string]::IsNullOrWhiteSpace($Script:ProfileCreatedAt)) {
                $Script:ProfileCreatedAt = (Get-Date).ToString("s")
            }
            Save-UiConfig
            Set-Status "NeoOptimize profile saved."
            $dialog.DialogResult = $true
            $dialog.Close()
        }.GetNewClosure())
        $skipButton.Add_Click({
            $dialog.DialogResult = $false
            $dialog.Close()
        }.GetNewClosure())

        [void]$dialog.ShowDialog()
        return (Test-NeoProfileComplete)
    } catch {
        Write-UiLog "Profile login dialog failed: $($_.Exception.Message)"
        return $false
    }
}

function Open-NeoExternalLink {
    param([string]$Url)
    try {
        Start-Process $Url | Out-Null
        Set-Status "Opened: $Url"
    } catch {
        Write-UiLog "Open link failed for ${Url}: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Cannot open link: $Url", "NeoOptimize", "OK", "Warning") | Out-Null
    }
}

function Add-OperationRow {
    param($Item)
    $rows = Find-Control "OperationRows"
    $card = [System.Windows.Controls.Border]::new()
    $card.Background = $Window.Resources["PanelAltBrush"]
    $card.BorderBrush = $Window.Resources["LineBrush"]
    $card.BorderThickness = [System.Windows.Thickness]::new(1)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $card.Padding = [System.Windows.Thickness]::new(9, 8, 9, 7)
    $card.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
    $card.MinHeight = 76
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    $card.Tag = $Item.Action
    $card.ToolTip = $Item.Detail

    $root = [System.Windows.Controls.Grid]::new()
    $root.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
    $root.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())

    $top = [System.Windows.Controls.Grid]::new()
    $topLeft = [System.Windows.Controls.ColumnDefinition]::new()
    $topLeft.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $topRight = [System.Windows.Controls.ColumnDefinition]::new()
    $topRight.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Auto)
    $top.ColumnDefinitions.Add($topLeft)
    $top.ColumnDefinitions.Add($topRight)

    $accent = if ($Item.Color) { [string]$Item.Color } else { "#00F0FF" }

    $badge = [System.Windows.Controls.Border]::new()
    $badge.Width = 22
    $badge.Height = 22
    $badge.CornerRadius = [System.Windows.CornerRadius]::new(5)
    $badge.Background = $Window.Resources["NavBrush"]
    $badge.BorderBrush = New-Brush $accent
    $badge.BorderThickness = [System.Windows.Thickness]::new(1)

    $badgeText = [System.Windows.Controls.TextBlock]::new()
    $badgeText.Text = [string]$Item.Icon
    $badgeText.FontSize = 12
    $badgeText.FontWeight = "Bold"
    $badgeText.FontFamily = [System.Windows.Media.FontFamily]::new("Segoe UI Symbol")
    $badgeText.HorizontalAlignment = "Center"
    $badgeText.VerticalAlignment = "Center"
    $badgeText.Foreground = New-Brush $accent
    $badge.Child = $badgeText
    [System.Windows.Controls.Grid]::SetColumn($badge, 0)
    $top.Children.Add($badge) | Out-Null

    $runText = [System.Windows.Controls.TextBlock]::new()
    $runText.Text = "RUN"
    $runText.Foreground = New-Brush $accent
    $runText.FontSize = 9
    $runText.FontWeight = "Bold"
    $runText.FontFamily = $Window.Resources["MonoFontFamily"]
    $runText.HorizontalAlignment = "Right"
    $runText.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($runText, 1)
    $top.Children.Add($runText) | Out-Null

    [System.Windows.Controls.Grid]::SetRow($top, 0)
    $root.Children.Add($top) | Out-Null

    $meta = [System.Windows.Controls.StackPanel]::new()
    $meta.Orientation = "Vertical"
    $meta.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = $Item.Name
    $title.Foreground = $Window.Resources["TextBrush"]
    $title.FontWeight = "SemiBold"
    $title.FontSize = 10
    $title.TextTrimming = "CharacterEllipsis"
    $title.TextWrapping = "Wrap"
    $meta.Children.Add($title) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($meta, 1)
    $root.Children.Add($meta) | Out-Null

    $statusRow = [System.Windows.Controls.StackPanel]::new()
    $statusRow.Orientation = "Horizontal"
    $statusRow.Margin = [System.Windows.Thickness]::new(0, 5, 0, 0)
    $statusRow.HorizontalAlignment = "Left"

    $dot = [System.Windows.Shapes.Ellipse]::new()
    $dot.Width = 6
    $dot.Height = 6
    $dot.Fill = New-Brush $accent
    $dot.VerticalAlignment = "Center"
    $dot.Margin = [System.Windows.Thickness]::new(0, 0, 6, 0)
    $statusRow.Children.Add($dot) | Out-Null

    $state = [System.Windows.Controls.TextBlock]::new()
    $state.Text = "CLICK"
    $state.Foreground = New-Brush $accent
    $state.FontSize = 8
    $state.FontWeight = "Bold"
    $state.FontFamily = $Window.Resources["MonoFontFamily"]
    $statusRow.Children.Add($state) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($statusRow, 2)
    $root.Children.Add($statusRow) | Out-Null

    $card.Child = $root
    $card.Add_PreviewMouseLeftButtonUp({
        param($sender, $eventArgs)
        if ($sender.Tag) {
            $eventArgs.Handled = $true
            Start-NeoAction ([string]$sender.Tag)
        }
    })
    $card.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        if ($sender.Tag) { Start-NeoAction ([string]$sender.Tag) }
    })
    $card.Add_MouseEnter({
        param($sender, $eventArgs)
        $sender.BorderBrush = $Window.Resources["AccentBrush"]
    })
    $card.Add_MouseLeave({
        param($sender, $eventArgs)
        $sender.BorderBrush = $Window.Resources["LineBrush"]
    })
    $rows.Children.Add($card) | Out-Null
}

function Get-NeoEngineActionSet {
    if ($Script:EngineActionSet) { return $Script:EngineActionSet }

    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $set.Add("AIModelSettings") | Out-Null

    try {
        if (Test-Path $Script:EnginePath) {
            $content = Get-Content -Path $Script:EnginePath -Raw
            $match = [regex]::Match($content, '\[ValidateSet\(([\s\S]*?)\)\]\s*\[string\]\$Action')
            if ($match.Success) {
                foreach ($item in [regex]::Matches($match.Groups[1].Value, '"([^"]+)"')) {
                    $set.Add($item.Groups[1].Value) | Out-Null
                }
            }
        }
    } catch {
        Write-UiLog "Failed to parse engine action list: $($_.Exception.Message)"
    }

    $Script:EngineActionSet = $set
    return $Script:EngineActionSet
}

function Test-NeoUiActionAvailable {
    param([string]$Action)

    if ([string]::IsNullOrWhiteSpace($Action)) { return $false }
    $set = Get-NeoEngineActionSet
    if ($set.Count -le 1) {
        # Fail open if the parser cannot read ValidateSet. The engine still owns
        # final validation and will reject unsupported actions safely.
        return $true
    }
    return $set.Contains($Action)
}

function Get-NeoAvailableOperations {
    param([array]$Items)

    return @($Items | Where-Object { Test-NeoUiActionAvailable ([string]$_.Action) })
}

function Render-Operations {
    $rows = Find-Control "OperationRows"
    $items = @(Get-NeoAvailableOperations $Script:OverviewModules)
    if ($Script:ModuleActionFilter -and $Script:ModuleActionFilter.Count -gt 0) {
        $items = @($items | Where-Object { $Script:ModuleActionFilter -contains $_.Action })
    }
    if ($rows) {
        $rows.Children.Clear()
        foreach ($item in $items) { Add-OperationRow $item }
    }
    Render-OverviewOperations
}

function Add-OverviewOperationCard {
    param($Item)

    $rows = Find-Control "OverviewOperationRows"
    if (-not $rows) { return }

    $card = [System.Windows.Controls.Border]::new()
    $card.Background = $Window.Resources["PanelAltBrush"]
    $card.BorderBrush = $Window.Resources["LineBrush"]
    $card.BorderThickness = [System.Windows.Thickness]::new(1)
    $card.CornerRadius = [System.Windows.CornerRadius]::new(7)
    $card.Padding = [System.Windows.Thickness]::new(10, 8, 10, 7)
    $card.Margin = [System.Windows.Thickness]::new(0, 0, 10, 8)
    $card.MinHeight = 48
    $card.Cursor = [System.Windows.Input.Cursors]::Hand
    $card.Tag = $Item.Action
    $card.ToolTip = $Item.Detail

    $accent = if ($Item.Color) { [string]$Item.Color } else { "#00F0FF" }

    $root = [System.Windows.Controls.Grid]::new()
    $root.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new()) | Out-Null
    $root.ColumnDefinitions[0].Width = [System.Windows.GridLength]::new(9)
    $root.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new()) | Out-Null

    $bar = [System.Windows.Controls.Border]::new()
    $bar.Width = 7
    $bar.Height = 20
    $bar.VerticalAlignment = "Top"
    $bar.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)
    $bar.CornerRadius = [System.Windows.CornerRadius]::new(2)
    $bar.Background = New-Brush $accent
    $root.Children.Add($bar) | Out-Null

    $text = [System.Windows.Controls.StackPanel]::new()
    $text.Margin = [System.Windows.Thickness]::new(10, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($text, 1)

    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = [string]$Item.Name
    $title.Foreground = $Window.Resources["TextBrush"]
    $title.FontSize = 12
    $title.FontWeight = "SemiBold"
    $title.TextTrimming = "CharacterEllipsis"

    $detail = [System.Windows.Controls.TextBlock]::new()
    $detail.Text = [string]$Item.Detail
    $detail.Foreground = $Window.Resources["MutedBrush"]
    $detail.FontSize = 9
    $detail.TextTrimming = "CharacterEllipsis"
    $detail.Margin = [System.Windows.Thickness]::new(0, 2, 0, 0)

    $text.Children.Add($title) | Out-Null
    $text.Children.Add($detail) | Out-Null
    $root.Children.Add($text) | Out-Null

    $card.Child = $root
    $card.Add_PreviewMouseLeftButtonUp({
        param($sender, $eventArgs)
        if ($sender.Tag) {
            $eventArgs.Handled = $true
            Start-NeoAction ([string]$sender.Tag)
        }
    })
    $card.Add_MouseEnter({
        param($sender, $eventArgs)
        $sender.BorderBrush = $Window.Resources["AccentBrush"]
    })
    $card.Add_MouseLeave({
        param($sender, $eventArgs)
        $sender.BorderBrush = $Window.Resources["LineBrush"]
    })

    $rows.Children.Add($card) | Out-Null
}

function Render-OverviewOperations {
    $rows = Find-Control "OverviewOperationRows"
    if (-not $rows) { return }
    $rows.Children.Clear()

    $featured = @("DeviceSnapshot", "BenchmarkReport", "Cleaner", "DeepScan", "Apps", "PrivacyReview", "NetworkDiagnostics", "SecurityAudit")
    $items = @(Get-NeoAvailableOperations $Script:OverviewModules | Where-Object { $featured -contains $_.Action } | Select-Object -First 8)
    foreach ($item in $items) {
        Add-OverviewOperationCard $item
    }
}

function Add-ConnectorRow {
    param([string]$Name, [string]$Status)
    $rows = Find-Control "ConnectorRows"
    $grid = [System.Windows.Controls.Grid]::new()
    $grid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
    $c1 = [System.Windows.Controls.ColumnDefinition]::new()
    $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
    $c2 = [System.Windows.Controls.ColumnDefinition]::new()
    $c2.Width = [System.Windows.GridLength]::new(110)
    $grid.ColumnDefinitions.Add($c1)
    $grid.ColumnDefinitions.Add($c2)
    $left = [System.Windows.Controls.TextBlock]::new()
    $left.Text = $Name
    $left.Foreground = $Window.Resources["TextBrush"]
    $left.FontWeight = "SemiBold"
    $right = [System.Windows.Controls.TextBlock]::new()
    $right.Text = $Status
    $right.Foreground = $Window.Resources["MutedBrush"]
    $right.HorizontalAlignment = "Right"
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    $grid.Children.Add($left) | Out-Null
    $grid.Children.Add($right) | Out-Null
    $rows.Children.Add($grid) | Out-Null
}

function Render-Connectors {
    $rows = Find-Control "ConnectorRows"
    $rows.Children.Clear()
    Add-ConnectorRow "GitHub" (T "Configured")
    Add-ConnectorRow "HF Space" (T "Configured")
    Add-ConnectorRow "Supabase" (T "Publishable")
    Add-ConnectorRow "E2B" (T "Dashboard")
}

function Add-ManagedSystemRow {
    param($Agent)

    $rows = Find-Control "ManagedSystemsRows"
    if (-not $rows) { return }

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)
    $grid.Background = $Window.Resources["PanelAltBrush"]
    foreach ($width in @(150, 110, 130, 110, 110, 140)) {
        $col = [System.Windows.Controls.ColumnDefinition]::new()
        $col.Width = [System.Windows.GridLength]::new($width)
        $grid.ColumnDefinitions.Add($col)
    }

    $status = if ($Agent.live_status) { [string]$Agent.live_status } elseif ($Agent.status) { [string]$Agent.status } else { "unknown" }
    $tele = $Agent.tele
    $cpuText = if ($tele -and $null -ne $tele.cpu_pct) { "$($tele.cpu_pct)%" } elseif ($tele -and $null -ne $tele.c) { "$($tele.c)%" } else { "-" }
    $ramText = if ($tele -and $null -ne $tele.ram_used_mb) { "$([math]::Round([double]$tele.ram_used_mb / 1024, 1)) GB" } elseif ($tele -and $null -ne $tele.r) { "$([math]::Round([double]$tele.r / 1024, 1)) GB" } else { "-" }
    $ip = if ($Agent.ip_address) { [string]$Agent.ip_address } elseif ($Agent.public_ip) { [string]$Agent.public_ip } else { "-" }
    $spec = if ($Agent.os) { [string]$Agent.os } elseif ($Agent.cpu) { [string]$Agent.cpu } else { "-" }

    $values = @(
        [string]$Agent.hostname,
        $status.ToUpper(),
        $spec,
        $cpuText,
        $ramText,
        $ip
    )

    for ($i = 0; $i -lt $values.Count; $i++) {
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text = if ([string]::IsNullOrWhiteSpace($values[$i])) { "-" } else { $values[$i] }
        $tb.Foreground = if ($i -eq 1 -and $status -eq "online") { $Window.Resources["GoodBrush"] } elseif ($i -eq 1) { $Window.Resources["WarnBrush"] } else { $Window.Resources["TextBrush"] }
        $tb.FontSize = 11
        $tb.Padding = [System.Windows.Thickness]::new(16, 9, 8, 9)
        $tb.TextTrimming = "CharacterEllipsis"
        [System.Windows.Controls.Grid]::SetColumn($tb, $i)
        $grid.Children.Add($tb) | Out-Null
    }

    $rows.Children.Add($grid) | Out-Null
}

function Render-ManagedSystems {
    param([array]$Agents)

    $rows = Find-Control "ManagedSystemsRows"
    $countText = Find-Control "ManagedSystemsCountText"
    if (-not $rows) { return }

    $rows.Children.Clear()
    $agents = @($Agents)
    if ($countText) { $countText.Text = "$($agents.Count) registered" }

    if ($agents.Count -eq 0) {
        $empty = [System.Windows.Controls.StackPanel]::new()
        $empty.HorizontalAlignment = "Center"
        $empty.VerticalAlignment = "Center"
        $empty.Margin = [System.Windows.Thickness]::new(0, 22, 0, 22)
        $empty.Opacity = 0.85

        $icon = [System.Windows.Controls.TextBlock]::new()
        $icon.Text = "ENDPOINTS"
        $icon.Foreground = $Window.Resources["MutedBrush"]
        $icon.FontSize = 11
        $icon.FontWeight = "Bold"
        $icon.HorizontalAlignment = "Center"
        $empty.Children.Add($icon) | Out-Null

        $msg = [System.Windows.Controls.TextBlock]::new()
        $msg.Text = "No managed endpoints are currently visible on this client dashboard."
        $msg.Foreground = $Window.Resources["TextBrush"]
        $msg.FontSize = 12
        $msg.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)
        $msg.HorizontalAlignment = "Center"
        $empty.Children.Add($msg) | Out-Null

        $rows.Children.Add($empty) | Out-Null
        return
    }

    foreach ($agent in ($agents | Select-Object -First 10)) {
        Add-ManagedSystemRow $agent
    }
}

function Set-ActiveNav {
    param([string]$Name)
    $navNames = @("BtnOverview", "BtnAdvisor", "BtnProviders", "BtnAudit", "BtnRestore", "BtnReports", "BtnConsole", "BtnUsers", "BtnSettings", "BtnAbout")
    foreach ($navName in $navNames) {
        $btn = Find-Control $navName
        if ($btn) {
            $btn.Background = $Window.Resources["NavBrush"]
            $btn.BorderBrush = $Window.Resources["LineBrush"]
            $btn.Foreground = $Window.Resources["SidebarTextBrush"]
        }
    }
    $active = Find-Control $Name
    if ($active) {
        $active.Background = $Window.Resources["NavHoverBrush"]
        $active.BorderBrush = $Window.Resources["AccentBrush"]
        $active.Foreground = $Window.Resources["AccentBrush"]
    }
}

function Show-NeoPage {
    param(
        [string]$PageName,
        [string]$NavName,
        [string]$Title,
        [string]$Subtitle
    )

    foreach ($name in @("PageOverview", "PageModules", "PageAi", "PageReports")) {
        $page = Find-Control $name
        if ($page) {
            $page.Visibility = if ($name -eq $PageName) { "Visible" } else { "Collapsed" }
        }
    }
    Set-ActiveNav $NavName
    if (-not [string]::IsNullOrWhiteSpace($Title)) { Set-ControlText "MainTitleText" $Title }
    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { Set-ControlText "SubtitleText" $Subtitle }
}

function Show-NeoDashboardPage {
    Show-NeoPage -PageName "PageOverview" -NavName "BtnOverview" -Title (T "MainTitle") -Subtitle (T "Subtitle")
}

function Show-NeoModulesPage {
    param(
        [string]$Group,
        [string]$NavName,
        [string]$Title,
        [string]$Subtitle
    )

    $Script:ModuleActionFilter = @()
    if ($Script:ModuleGroups.ContainsKey($Group)) {
        $Script:ModuleActionFilter = @($Script:ModuleGroups[$Group])
    }
    $Script:ModulePageTitle = $Title
    $Script:ModulePageNote = $Subtitle
    Set-ControlText "ModulesTitleText" $Title.ToUpper()
    Set-ControlText "ModulesNoteText" $Subtitle
    Render-Operations
    Show-NeoPage -PageName "PageModules" -NavName $NavName -Title $Title -Subtitle $Subtitle
}

function Show-NeoAiPage {
    param([string]$NavName = "BtnProviders")
    Show-NeoPage -PageName "PageAi" -NavName $NavName -Title (T "AiPanel") -Subtitle (T "AiNote")
    Update-AiProviderStatus
}

function Show-NeoReportsPage {
    param([string]$NavName = "BtnReports")
    Show-NeoPage -PageName "PageReports" -NavName $NavName -Title (T "Reports") -Subtitle "Reports, task state, disk status, profile audit, and model settings."
}

function Get-NeoCounterValue {
    param([string]$Path, [switch]$Sum)
    try {
        $samples = @(Get-Counter -Counter $Path -ErrorAction Stop).CounterSamples
        if ($Sum) {
            return [math]::Max(0, [double](($samples | Measure-Object -Property CookedValue -Sum).Sum))
        }
        return [math]::Max(0, [double](($samples | Measure-Object -Property CookedValue -Average).Average))
    } catch {
        return 0.0
    }
}

function Get-NeoGpuUsage {
    $now = Get-Date
    if ($Script:LastGpuRefresh -ne [DateTime]::MinValue -and (($now - $Script:LastGpuRefresh).TotalSeconds -lt $Script:HeavyRefreshSeconds)) {
        return $Script:LastGpuUsage
    }
    try {
        $samples = @(Get-Counter -Counter "\GPU Engine(*)\Utilization Percentage" -ErrorAction Stop).CounterSamples |
            Where-Object { $_.InstanceName -match "engtype_3d|engtype_compute|engtype_video" }
        $value = [double](($samples | Measure-Object -Property CookedValue -Sum).Sum)
        $Script:LastGpuUsage = [math]::Round([math]::Min(100, [math]::Max(0, $value)), 1)
        $Script:LastGpuRefresh = $now
        return $Script:LastGpuUsage
    } catch {
        $Script:LastGpuRefresh = $now
        return $Script:LastGpuUsage
    }
}

function Get-NeoSystemSnapshot {
    param([switch]$Force)

    $now = Get-Date
    if (-not $Force -and $Script:SystemSnapshot -and (($now - $Script:LastSystemSnapshotRefresh).TotalSeconds -lt $Script:HeavyRefreshSeconds)) {
        return $Script:SystemSnapshot
    }

    try {
        $Script:SystemSnapshot = [PSCustomObject]@{
            OperatingSystem = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            Processor       = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
            ComputerSystem  = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            DiskC           = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            Gpu             = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        $Script:LastSystemSnapshotRefresh = $now
    } catch {
        Write-UiLog "System snapshot refresh failed: $($_.Exception.Message)"
    }

    return $Script:SystemSnapshot
}

function Format-NeoRate {
    param([double]$BytesPerSecond)
    if ($BytesPerSecond -ge 1GB) { return ("{0:N1} GB/s" -f ($BytesPerSecond / 1GB)) }
    if ($BytesPerSecond -ge 1MB) { return ("{0:N1} MB/s" -f ($BytesPerSecond / 1MB)) }
    if ($BytesPerSecond -ge 1KB) { return ("{0:N0} KB/s" -f ($BytesPerSecond / 1KB)) }
    return ("{0:N0} B/s" -f $BytesPerSecond)
}

function Initialize-OverviewSeries {
    if ($Script:CpuSeries.Count -gt 0 -and $Script:RamSeries.Count -gt 0 -and $Script:NetSeries.Count -gt 0) { return }
    for ($i = 0; $i -lt 30; $i++) {
        $Script:CpuSeries.Add([double]0)
        $Script:GpuSeries.Add([double]0)
        $Script:RamSeries.Add([double]0)
        $Script:DiskSeries.Add([double]0)
        $Script:NetSeries.Add([double]0)
    }
}

function Push-OverviewSeriesSample {
    param(
        [System.Collections.Generic.List[double]]$Series,
        [double]$Value,
        [int]$MaxPoints = 30
    )
    $Series.Add([double]$Value)
    while ($Series.Count -gt $MaxPoints) {
        $Series.RemoveAt(0)
    }
}

function Draw-LineChart {
    param(
        [System.Windows.Controls.Canvas]$Canvas,
        [System.Collections.Generic.List[double]]$Series,
        [string]$StrokeColor,
        [string]$FillColor
    )
    if (-not $Canvas -or -not $Series -or $Series.Count -eq 0) { return }
    $Canvas.Children.Clear()

    $width = [math]::Max(240, [double]$Canvas.ActualWidth)
    $height = [math]::Max(120, [double]$Canvas.ActualHeight)
    $padding = 10.0
    $plotWidth = [math]::Max(10, $width - ($padding * 2))
    $plotHeight = [math]::Max(10, $height - ($padding * 2))

    $min = ($Series | Measure-Object -Minimum).Minimum
    $max = ($Series | Measure-Object -Maximum).Maximum
    if ($null -eq $min -or $null -eq $max -or $max -le $min) { $max = $min + 1 }

    $linePoints = [System.Windows.Media.PointCollection]::new()
    $areaPoints = [System.Windows.Media.PointCollection]::new()
    $areaPoints.Add([System.Windows.Point]::new($padding, $height - $padding))

    for ($i = 0; $i -lt $Series.Count; $i++) {
        $x = $padding + ($plotWidth * ($i / [math]::Max(1, $Series.Count - 1)))
        $normalized = ($Series[$i] - $min) / ($max - $min)
        $y = $padding + ($plotHeight - ($normalized * $plotHeight))
        $point = [System.Windows.Point]::new($x, $y)
        $linePoints.Add($point)
        $areaPoints.Add($point)
    }
    $areaPoints.Add([System.Windows.Point]::new($padding + $plotWidth, $height - $padding))

    $area = [System.Windows.Shapes.Polygon]::new()
    $area.Points = $areaPoints
    $area.Fill = New-Brush $FillColor
    $area.Opacity = 1
    $Canvas.Children.Add($area) | Out-Null

    $line = [System.Windows.Shapes.Polyline]::new()
    $line.Points = $linePoints
    $line.Stroke = New-Brush $StrokeColor
    $line.StrokeThickness = 2
    $line.StrokeLineJoin = [System.Windows.Media.PenLineJoin]::Round
    $line.SnapsToDevicePixels = $true
    $Canvas.Children.Add($line) | Out-Null
}

function Draw-TaskBars {
    param(
        [System.Windows.Controls.StackPanel]$Panel,
        [array]$Items,
        [string]$BarColor
    )
    if (-not $Panel) { return }
    $Panel.Children.Clear()
    if (-not $Items) { return }

    $max = [math]::Max(1, ($Items | Measure-Object -Property Count -Maximum).Maximum)
    foreach ($item in $Items) {
        $stack = [System.Windows.Controls.StackPanel]::new()
        $stack.Orientation = "Vertical"
        $stack.Width = 48
        $stack.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $stack.HorizontalAlignment = "Center"
        $stack.VerticalAlignment = "Bottom"

        $track = [System.Windows.Controls.Border]::new()
        $track.Width = 34
        $track.Height = 92
        $track.HorizontalAlignment = "Center"
        $track.VerticalAlignment = "Bottom"
        $track.Background = $Window.Resources["NavBrush"]
        $track.BorderBrush = $Window.Resources["LineBrush"]
        $track.BorderThickness = [System.Windows.Thickness]::new(1)
        $track.CornerRadius = [System.Windows.CornerRadius]::new(5)

        $fill = [System.Windows.Controls.Border]::new()
        $fill.Width = 34
        $fill.Height = [math]::Max(6, [math]::Round(84 * ($item.Count / $max)))
        $fill.HorizontalAlignment = "Center"
        $fill.VerticalAlignment = "Bottom"
        $fill.Background = New-Brush $BarColor
        $fill.CornerRadius = [System.Windows.CornerRadius]::new(5)
        $track.Child = $fill
        $stack.Children.Add($track) | Out-Null

        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $item.Name
        $label.Foreground = $Window.Resources["MutedBrush"]
        $label.FontSize = 8
        $label.HorizontalAlignment = "Center"
        $label.Margin = [System.Windows.Thickness]::new(0, 6, 0, 0)
        $stack.Children.Add($label) | Out-Null

        $Panel.Children.Add($stack) | Out-Null
    }
}

function Read-ModelAgentConfig {
    $fallback = [PSCustomObject]@{
        provider_order = @("ollama", "neocore", "rule_based")
        neocore = [PSCustomObject]@{ policy_path = "models\NeoCore.Policy.json" }
        ollama = [PSCustomObject]@{ endpoint = "http://127.0.0.1:11434/api/generate"; tags_endpoint = "http://127.0.0.1:11434/api/tags"; preferred_models = @("neo-light:latest", "neo:latest", "neo-latest:latest") }
        openai_compatible = [PSCustomObject]@{ enabled = $false; endpoint = "https://api.openai.com/v1/chat/completions"; model = "gpt-4.1-mini"; api_key = "" }
        huggingface = [PSCustomObject]@{ enabled = $false; model = ""; api_key = "" }
        gemini = [PSCustomObject]@{ enabled = $false; model = "gemini-1.5-flash"; api_key = "" }
        nullclaw = [PSCustomObject]@{ command = "nullclaw" }
        voice = [PSCustomObject]@{ enabled = $false; language = "id-ID"; wake_phrase = "neo optimize"; mode = "push_to_talk" }
    }
    if (-not (Test-Path $Script:ModelConfigPath)) { return $fallback }
    try {
        $cfg = Get-Content -Path $Script:ModelConfigPath -Raw | ConvertFrom-Json
        foreach ($name in @($fallback.PSObject.Properties.Name)) {
            if ($cfg.PSObject.Properties.Name -notcontains $name -or $null -eq $cfg.$name) {
                $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $fallback.$name -Force
            }
        }
        return $cfg
    } catch { return $fallback }
}

function Read-RmmConfig {
    $fallback = [PSCustomObject]@{
        service_name = "NeoOptimize Endpoint Sync Agent"
        candidate_server_urls = @()
        auth = [PSCustomObject]@{ token = ""; email = ""; password = "" }
        dispatch_to_online_agents = $false
    }
    if (-not (Test-Path $Script:RmmConfigPath)) { return $fallback }
    try {
        $cfg = Get-Content -Path $Script:RmmConfigPath -Raw | ConvertFrom-Json
        if (-not $cfg.service_name) { $cfg | Add-Member -NotePropertyName service_name -NotePropertyValue $fallback.service_name -Force }
        if (-not $cfg.candidate_server_urls) { $cfg | Add-Member -NotePropertyName candidate_server_urls -NotePropertyValue $fallback.candidate_server_urls -Force }
        if (-not $cfg.auth) { $cfg | Add-Member -NotePropertyName auth -NotePropertyValue $fallback.auth -Force }
        if ($null -eq $cfg.dispatch_to_online_agents) { $cfg | Add-Member -NotePropertyName dispatch_to_online_agents -NotePropertyValue $fallback.dispatch_to_online_agents -Force }
        return $cfg
    } catch {
        return $fallback
    }
}

function Test-RmmServerUrl {
    param([string]$Url)
    try {
        $health = Invoke-RestMethod -Uri ($Url.TrimEnd("/") + "/health") -Method Get -TimeoutSec 2
        if ($health.status -eq "ok") { return $true }
    } catch {}
    return $false
}

function Invoke-RmmJson {
    param(
        [string]$Url,
        [string]$Method = "Get",
        [object]$Body = $null,
        [string]$Token = "",
        [int]$TimeoutSec = 3
    )

    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Uri = $Url
        Method = $Method
        Headers = $headers
        TimeoutSec = $TimeoutSec
    }

    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
    }

    return Invoke-RestMethod @params
}

function Get-RmmAuthToken {
    param(
        [object]$Config,
        [string]$ServerUrl
    )

    if ($Config.auth -and -not [string]::IsNullOrWhiteSpace([string]$Config.auth.token)) {
        return [string]$Config.auth.token
    }
    if (-not [string]::IsNullOrWhiteSpace($env:NEOOPTIMIZE_RMM_TOKEN)) {
        return [string]$env:NEOOPTIMIZE_RMM_TOKEN
    }

    $email = ""
    $password = ""
    if ($Config.auth) {
        if ($Config.auth.email) { $email = [string]$Config.auth.email }
        if ($Config.auth.password) { $password = [string]$Config.auth.password }
    }
    if ([string]::IsNullOrWhiteSpace($email) -and -not [string]::IsNullOrWhiteSpace($env:NEOOPTIMIZE_RMM_EMAIL)) {
        $email = [string]$env:NEOOPTIMIZE_RMM_EMAIL
    }
    if ([string]::IsNullOrWhiteSpace($password) -and -not [string]::IsNullOrWhiteSpace($env:NEOOPTIMIZE_RMM_PASSWORD)) {
        $password = [string]$env:NEOOPTIMIZE_RMM_PASSWORD
    }

    if ([string]::IsNullOrWhiteSpace($email) -or [string]::IsNullOrWhiteSpace($password)) {
        return ""
    }

    try {
        $login = Invoke-RmmJson -Url ($ServerUrl.TrimEnd("/") + "/api/v1/auth/login") -Method "Post" -Body @{ email = $email; password = $password } -TimeoutSec 2
        if ($login.token) { return [string]$login.token }
    } catch {
        Write-UiLog "RMM login failed at ${ServerUrl}: $($_.Exception.Message)"
    }
    return ""
}

function Get-RmmSnapshot {
    $cfg = Read-RmmConfig
    $urls = @($cfg.candidate_server_urls | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $snapshot = [PSCustomObject]@{
        connected = $false
        authenticated = $false
        server_url = ""
        health = $null
        stats = $null
        agents = @()
        commands = @()
        error = ""
    }

    if ($urls.Count -eq 0) {
        $snapshot.error = "Local mode"
        $Script:RmmSnapshot = $snapshot
        return $snapshot
    }

    foreach ($url in $urls) {
        $base = $url.TrimEnd("/")
        try {
            $health = Invoke-RmmJson -Url ($base + "/health") -Method "Get" -TimeoutSec 1
            $snapshot.connected = $true
            $snapshot.server_url = $base
            $snapshot.health = $health

            $token = Get-RmmAuthToken -Config $cfg -ServerUrl $base
            if (-not [string]::IsNullOrWhiteSpace($token)) {
                $snapshot.authenticated = $true
                try {
                    $snapshot.stats = Invoke-RmmJson -Url ($base + "/api/v1/dashboard/stats") -Method "Get" -Token $token -TimeoutSec 2
                    $agentResponse = Invoke-RmmJson -Url ($base + "/api/v1/dashboard/agents?limit=50") -Method "Get" -Token $token -TimeoutSec 2
                    $commandResponse = Invoke-RmmJson -Url ($base + "/api/v1/dashboard/commands?limit=20") -Method "Get" -Token $token -TimeoutSec 2
                    $snapshot.agents = @($agentResponse.agents)
                    $snapshot.commands = @($commandResponse.commands)
                } catch {
                    $snapshot.error = "RMM API read failed: $($_.Exception.Message)"
                    Write-UiLog $snapshot.error
                }
            } else {
                $snapshot.error = T "RmmAuthMissing"
            }

            $Script:RmmSnapshot = $snapshot
            return $snapshot
        } catch {
            $snapshot.error = "RMM unreachable at ${base}: $($_.Exception.Message)"
            Write-UiLog $snapshot.error
        }
    }

    $Script:RmmSnapshot = $snapshot
    return $snapshot
}

function Get-RmmCommandType {
    param([string]$Action)
    try {
        $catalogPath = Join-Path $Script:Root "config\NeoOptimize.CommandCatalog.json"
        if (Test-Path $catalogPath) {
            $catalog = Get-Content -Path $catalogPath -Raw | ConvertFrom-Json
            $match = @($catalog.capabilities | Where-Object {
                [string]$_.local_action -eq $Action -and
                -not [string]::IsNullOrWhiteSpace([string]$_.rmm_command)
            } | Select-Object -First 1)
            if ($match.Count -gt 0) { return [string]$match[0].rmm_command }
        }
    } catch {
        Write-UiLog "RMM command catalog lookup failed for ${Action}: $($_.Exception.Message)"
    }

    $map = @{
        Cleaner = "CLEAN"
        CleanAll = "CLEAN"
        Performance = "PERFORMANCE"
        SmartOptimize = "OPTIMIZE"
        Privacy = "PRIVACY"
        Network = "NETWORK_TEST"
        Security = "SECURITY_SCAN"
        Services = "SERVICES"
        Updates = "UPDATES"
        Power = "POWER"
        DeepScan = "DEEP_SCAN"
        SystemDiagnostics = "SYSTEM_DIAGNOSTICS"
        SystemRepair = "SYSTEM_REPAIR"
        DiskStatus = "COLLECT"
        DiskScan = "SYSTEM_DIAGNOSTICS"
        DiskRepair = "SYSTEM_REPAIR"
        DiskOptimize = "OPTIMIZE"
        HealthRepair = "SYSTEM_REPAIR"
        AgentAudit = "SYSINFO"
        RemoteReadiness = "SYSTEM_DIAGNOSTICS"
        RemoteAccess = "REMOTE_ACCESS_STATUS"
        NeoUpdate = "NEOUPDATE"
    }
    if ($map.ContainsKey($Action)) { return [string]$map[$Action] }
    return ""
}

function Get-RmmUpdateArgs {
    param(
        [object]$Config,
        [string]$ServerUrl,
        [string]$Token
    )

    $silentArgs = "/S"
    $installerUrl = ""
    $installerSha256 = ""
    $packageSha256 = ""
    $updateToken = ""
    $useManifest = $true
    $manifestPath = "/downloads/neooptimize/manifest"

    if ($Config.update) {
        if ($Config.update.PSObject.Properties.Name -contains "silent_args" -and $Config.update.silent_args) { $silentArgs = [string]$Config.update.silent_args }
        if ($Config.update.PSObject.Properties.Name -contains "installer_url" -and $Config.update.installer_url) { $installerUrl = [string]$Config.update.installer_url }
        if ($Config.update.PSObject.Properties.Name -contains "installer_sha256" -and $Config.update.installer_sha256) { $installerSha256 = [string]$Config.update.installer_sha256 }
        if ($Config.update.PSObject.Properties.Name -contains "package_sha256" -and $Config.update.package_sha256) { $packageSha256 = [string]$Config.update.package_sha256 }
        if ($Config.update.PSObject.Properties.Name -contains "use_rmm_manifest") { $useManifest = [bool]$Config.update.use_rmm_manifest }
        if ($Config.update.PSObject.Properties.Name -contains "manifest_path" -and $Config.update.manifest_path) { $manifestPath = [string]$Config.update.manifest_path }
    }

    if ($useManifest) {
        $manifestUrl = if ($manifestPath -match "^https?://") { $manifestPath } else { $ServerUrl.TrimEnd("/") + "/" + $manifestPath.TrimStart("/") }
        $manifest = Invoke-RmmJson -Url $manifestUrl -Method "Get" -Token $Token -TimeoutSec 8
        if ($manifest.url) {
            $installerUrl = [string]$manifest.url
            if ($installerUrl -notmatch "^https?://") { $installerUrl = $ServerUrl.TrimEnd("/") + "/" + $installerUrl.TrimStart("/") }
        }
        if ($manifest.installer_url) {
            $installerUrl = [string]$manifest.installer_url
            if ($installerUrl -notmatch "^https?://") { $installerUrl = $ServerUrl.TrimEnd("/") + "/" + $installerUrl.TrimStart("/") }
        }
        if ($manifest.sha256) { $installerSha256 = [string]$manifest.sha256 }
        if ($manifest.installer_sha256) { $installerSha256 = [string]$manifest.installer_sha256 }
        if ($manifest.package_sha256) { $packageSha256 = [string]$manifest.package_sha256 }
        if ($manifest.silent_args) { $silentArgs = [string]$manifest.silent_args }
        if ($manifest.update_token) { $updateToken = [string]$manifest.update_token }
    }

    if ([string]::IsNullOrWhiteSpace($installerUrl)) {
        throw "NeoOptimize update installer URL is not configured."
    }
    if ([string]::IsNullOrWhiteSpace($installerSha256) -and [string]::IsNullOrWhiteSpace($packageSha256)) {
        throw "NeoOptimize update manifest is missing SHA-256."
    }

    return @{
        source = "NeoOptimize.UI"
        local_action = "NeoUpdate"
        installer_url = $installerUrl
        installer_sha256 = $installerSha256
        package_sha256 = $packageSha256
        silent_args = $silentArgs
        update_token = $updateToken
    }
}

function Invoke-RmmOperatorBridgeDispatch {
    param([object]$Snapshot = $null)

    if ($null -eq $Snapshot) { $Snapshot = Get-RmmSnapshot }
    if (-not $Snapshot.connected -or -not $Snapshot.authenticated) { return $false }

    $onlineAgents = @($Snapshot.agents | Where-Object { $_.live_status -eq "online" -or $_.status -eq "online" })
    if ($onlineAgents.Count -eq 0) { return $false }

    $cfg = Read-RmmConfig
    $token = Get-RmmAuthToken -Config $cfg -ServerUrl $Snapshot.server_url
    if ([string]::IsNullOrWhiteSpace($token)) { return $false }

    $bridgeItems = New-Object System.Collections.Generic.List[object]
    foreach ($agent in @($onlineAgents | Select-Object -First 12)) {
        $agentId = [string]$agent.id
        if ([string]::IsNullOrWhiteSpace($agentId)) { continue }

        try {
            $bridge = Invoke-RmmJson -Url ($Snapshot.server_url + "/api/v1/dashboard/agents/$agentId/operator-bridge") -Method "Get" -Token $token -TimeoutSec 10
            $commands = @($bridge.plan.recommended_commands | Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.command) -and
                ([string]$_.safety_level).ToLowerInvariant() -ne "lockdown"
            } | Select-Object -First 2)

            foreach ($cmd in $commands) {
                $priority = 5
                try { $priority = [int]$cmd.priority } catch {}
                $bridgeItems.Add([PSCustomObject]@{
                    AgentId = $agentId
                    Hostname = [string]$agent.hostname
                    Command = [string]$cmd.command
                    Reason = [string]$cmd.reason
                    Priority = $priority
                    Source = [string]$cmd.source
                    Confidence = [double]$cmd.confidence
                }) | Out-Null
            }
        } catch {
            Write-UiLog "Operator bridge read failed for $($agent.hostname): $($_.Exception.Message)"
        }
    }

    if ($bridgeItems.Count -eq 0) { return $false }

    $summary = (@($bridgeItems | Select-Object -First 10 | ForEach-Object {
        "- $($_.Hostname): $($_.Command) ($([int]([double]$_.Confidence * 100))%)"
    }) -join [Environment]::NewLine)
    if ($bridgeItems.Count -gt 10) {
        $summary += [Environment]::NewLine + ("- ... {0} command lain" -f ($bridgeItems.Count - 10))
    }

    $answer = [System.Windows.MessageBox]::Show(
        "NEO Operator Bridge siap mengirim command ke endpoint RMM via OpenFang/NullClaw/NeoCortex.`n`n$summary`n`nLanjut dispatch?",
        "NEO Operator Bridge",
        "YesNo",
        "Question"
    )
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return $false }

    $issued = 0
    foreach ($item in $bridgeItems) {
        try {
            $body = @{
                command = $item.Command
                reason = $item.Reason
                priority = $item.Priority
                args = @{
                    source = "NeoOptimize.UI"
                    bridge = "openfang-nullclaw-neocortex"
                    hostname = $item.Hostname
                    confidence = $item.Confidence
                    reason = $item.Reason
                }
            }
            $result = Invoke-RmmJson -Url ($Snapshot.server_url + "/api/v1/dashboard/agents/$($item.AgentId)/operator-bridge/dispatch") -Method "Post" -Body $body -Token $token -TimeoutSec 8
            if ($result.cmd_id) { $issued++ }
        } catch {
            Write-UiLog "Operator bridge dispatch failed for $($item.Hostname)/$($item.Command): $($_.Exception.Message)"
        }
    }

    if ($issued -gt 0) {
        Set-Status ("NEO Operator Bridge dispatched: {0} command(s)" -f $issued)
        Write-UiLog "NEO Operator Bridge dispatched $issued command(s) via RMM."
        return $true
    }

    return $false
}

function Invoke-RmmAiPlanDispatch {
    $snapshot = Get-RmmSnapshot
    if (-not $snapshot.connected -or -not $snapshot.authenticated) { return $false }

    $onlineAgents = @($snapshot.agents | Where-Object { $_.live_status -eq "online" -or $_.status -eq "online" })
    if ($onlineAgents.Count -eq 0) { return $false }

    if (Invoke-RmmOperatorBridgeDispatch -Snapshot $snapshot) { return $true }

    $aiScript = Join-Path $Script:Root "NeoOptimize.AIAgent.ps1"
    if (-not (Test-Path $aiScript)) { return $false }

    try {
        & $aiScript -Mode Plan -NoOpen | Out-Null
    } catch {
        Write-UiLog "AI plan generation failed before RMM dispatch: $($_.Exception.Message)"
        return $false
    }

    $latest = Get-ChildItem -Path (Join-Path $Script:Root "reports\ai") -Filter "NeoOptimize_AI_Agent_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) { return $false }

    try {
        $planJson = Get-Content -Path $latest.FullName -Raw | ConvertFrom-Json
        $recommendations = @($planJson.neocore_plan.recommendations | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.rmm_command) -and
            @("read-only", "low", "medium") -contains ([string]$_.risk).ToLowerInvariant()
        } | Select-Object -First 3)
        if ($recommendations.Count -eq 0) { return $false }

        $summary = ($recommendations | ForEach-Object { "- $($_.display) -> $($_.rmm_command) ($($_.confidence_pct)%)" }) -join [Environment]::NewLine
        $answer = [System.Windows.MessageBox]::Show(
            "NeoCore AI plan is ready. Dispatch these mapped commands to $($onlineAgents.Count) online RMM endpoint(s)?`n`n$summary",
            "Dispatch AI Plan to RMM",
            "YesNo",
            "Question"
        )
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return $false }

        $cfg = Read-RmmConfig
        $token = Get-RmmAuthToken -Config $cfg -ServerUrl $snapshot.server_url
        if ([string]::IsNullOrWhiteSpace($token)) { return $false }
        $agentIds = @($onlineAgents | ForEach-Object { [string]$_.id })

        $issued = 0
        foreach ($rec in $recommendations) {
            $body = @{
                agent_ids = $agentIds
                type = [string]$rec.rmm_command
                args = @{
                    source = "NeoOptimize.NeoCore"
                    local_action = [string]$rec.local_action
                    ai_module = [string]$rec.module
                    confidence_pct = [int]$rec.confidence_pct
                    reason = [string]$rec.reason
                    plan_report = [string]$latest.FullName
                }
                priority = 4
            }
            $result = Invoke-RmmJson -Url ($snapshot.server_url + "/api/v1/dashboard/commands/bulk") -Method "Post" -Body $body -Token $token -TimeoutSec 8
            if ($result.issued) { $issued += [int]$result.issued }
        }

        Set-Status ("NeoCore AI plan dispatched: {0} command(s)" -f $issued)
        Write-UiLog "NeoCore AI plan dispatched to RMM from $($latest.FullName): $issued command(s)."
        return ($issued -gt 0)
    } catch {
        Set-Status ("AI plan dispatch failed: {0}" -f $_.Exception.Message)
        Write-UiLog "AI plan dispatch failed: $($_.Exception.Message)"
        return $false
    }
}

function Invoke-RmmDispatch {
    param([string]$Action)

    $cmdType = Get-RmmCommandType $Action
    if ([string]::IsNullOrWhiteSpace($cmdType)) { return $false }

    $snapshot = Get-RmmSnapshot
    if (-not $snapshot.connected -or -not $snapshot.authenticated) { return $false }

    $onlineAgents = @($snapshot.agents | Where-Object { $_.live_status -eq "online" -or $_.status -eq "online" })
    if ($onlineAgents.Count -eq 0) { return $false }

    $answer = [System.Windows.MessageBox]::Show((T "RmmDispatchQuestion"), (T "RmmDispatch"), "YesNo", "Question")
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return $false }

    $cfg = Read-RmmConfig
    $token = Get-RmmAuthToken -Config $cfg -ServerUrl $snapshot.server_url
    if ([string]::IsNullOrWhiteSpace($token)) { return $false }

    try {
        $agentIds = @($onlineAgents | ForEach-Object { [string]$_.id })
        $commandArgs = @{ source = "NeoOptimize.UI"; local_action = $Action }
        if ($cmdType -eq "NEOUPDATE") {
            $commandArgs = Get-RmmUpdateArgs -Config $cfg -ServerUrl $snapshot.server_url -Token $token
        }
        $body = @{
            agent_ids = $agentIds
            type = $cmdType
            args = $commandArgs
            priority = 5
        }
        $result = Invoke-RmmJson -Url ($snapshot.server_url + "/api/v1/dashboard/commands/bulk") -Method "Post" -Body $body -Token $token -TimeoutSec 8
        Set-Status ("{0}: {1} endpoint(s)" -f (T "RmmDispatchQueued"), $result.issued)
        Write-UiLog "RMM dispatch queued: $Action -> $cmdType for $($agentIds.Count) agents."
        return $true
    } catch {
        Set-Status ("{0}: {1}" -f (T "RmmDispatchFailed"), $_.Exception.Message)
        Write-UiLog "RMM dispatch failed for ${Action}: $($_.Exception.Message)"
        return $false
    }
}

function Update-AiProviderStatus {
    $statusText = Find-Control "AiStatusText"
    if (-not $statusText) { return }
    $cfg = Read-ModelAgentConfig
    $environmentPath = Join-Path $Script:Root "config\NeoOptimize.AIEnvironment.json"
    $environmentName = "NeoOptimize AI-Empowered Environment"
    $skillCount = 0
    $connectorCount = 0
    try {
        if (Test-Path $environmentPath) {
            $environment = Get-Content -Path $environmentPath -Raw | ConvertFrom-Json
            if ($environment.environment_name) { $environmentName = [string]$environment.environment_name }
            $skillCount = @($environment.skills).Count
            $connectorCount = @($environment.mcp_connectors).Count
        }
    } catch {}

    $neoCorePath = Join-Path $Script:Root "models\NeoCore.Policy.json"
    if ($cfg.neocore.policy_path) {
        $candidate = [string]$cfg.neocore.policy_path
        if ([System.IO.Path]::IsPathRooted($candidate)) { $neoCorePath = $candidate } else { $neoCorePath = Join-Path $Script:Root $candidate }
    }
    $neoCoreStatus = if (Test-Path $neoCorePath) { "$(T "NeoCoreReady"): $neoCorePath" } else { T "NeoCoreMissing" }

    $nullclawCommand = if ($cfg.nullclaw.command) { [string]$cfg.nullclaw.command } else { "nullclaw" }
    $nullclaw = Get-Command $nullclawCommand -ErrorAction SilentlyContinue
    $nullclawStatus = if ($nullclaw) { "$(T "NullClawReady"): $($nullclaw.Source)" } else { "$(T "NullClawMissing"). $(T "NullClawInstall")" }

    $ollamaStatus = T "OllamaMissing"
    try {
        $tagsEndpoint = if ($cfg.ollama.tags_endpoint) { [string]$cfg.ollama.tags_endpoint } else { "http://127.0.0.1:11434/api/tags" }
        $tags = Invoke-RestMethod -Uri $tagsEndpoint -Method Get -TimeoutSec 2
        $models = @($tags.models | ForEach-Object { $_.name })
        if ($models.Count -gt 0) {
            $ollamaStatus = "$(T "OllamaReady"): $($models[0])"
        }
    } catch {}

    $remoteLines = New-Object System.Collections.Generic.List[string]
    if (Get-NeoConfigBool $cfg.openai_compatible "enabled" $false) {
        $remoteLines.Add(("OpenAI-compatible: {0}" -f (Get-NeoConfigString $cfg.openai_compatible "model" "configured"))) | Out-Null
    }
    if (Get-NeoConfigBool $cfg.huggingface "enabled" $false) {
        $remoteLines.Add(("Hugging Face: {0}" -f (Get-NeoConfigString $cfg.huggingface "model" "configured"))) | Out-Null
    }
    if (Get-NeoConfigBool $cfg.gemini "enabled" $false) {
        $remoteLines.Add(("Gemini: {0}" -f (Get-NeoConfigString $cfg.gemini "model" "configured"))) | Out-Null
    }
    if (Get-NeoConfigBool $cfg.voice "enabled" $false) {
        $remoteLines.Add(("Voice command: {0}, wake '{1}'" -f (Get-NeoConfigString $cfg.voice "language" "id-ID"), (Get-NeoConfigString $cfg.voice "wake_phrase" "neo optimize"))) | Out-Null
    }

    $corpusStatus = Get-NeoCorpusUiStatus
    $extra = if ($remoteLines.Count -gt 0) { "`r`n" + (@($remoteLines) -join "`r`n") } else { "" }
    $statusText.Text = "$environmentName`r`nInteractive operator: enabled`r`nSkills: $skillCount | MCP connectors: $connectorCount`r`n$neoCoreStatus`r`n$corpusStatus`r`n$ollamaStatus`r`n$nullclawStatus$extra`r`n$(T "AiRuleReady")."
}

function Get-NeoCorpusUiStatus {
    $corpusPath = Join-Path $Script:Root "knowledge\neo-ai-corpus.jsonl"
    $manifestPath = Join-Path $Script:Root "knowledge\neo-ai-corpus.manifest.json"
    if (-not (Test-Path $corpusPath) -or -not (Test-Path $manifestPath)) {
        return "NEO corpus: missing"
    }

    try {
        $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
        $actualHash = (Get-FileHash -Path $corpusPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedHash = ([string]$manifest.corpus_sha256).ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            return "NEO corpus: integrity mismatch"
        }
        $records = [int]$manifest.record_count
        return "NEO corpus: ready, $records records"
    } catch {
        Write-UiLog "NEO corpus status failed: $($_.Exception.Message)"
        return "NEO corpus: unreadable"
    }
}

function Get-NeoConfigString {
    param($Object, [string]$Name, [string]$Default = "")
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            return [string]$Object.$Name
        }
    } catch {}
    return $Default
}

function Get-NeoConfigBool {
    param($Object, [string]$Name, [bool]$Default = $false)
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            return [bool]$Object.$Name
        }
    } catch {}
    return $Default
}

function Show-AiModelSettings {
    $cfg = Read-ModelAgentConfig

    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "NeoOptimize AI Model Agent"
    $dialog.Width = 760
    $dialog.Height = 720
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner = $Window
    $dialog.Background = $Window.Resources["PageBrush"]
    $dialog.Foreground = $Window.Resources["TextBrush"]
    $dialog.FontFamily = $Window.Resources["MainFontFamily"]

    $scroll = [System.Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility = "Auto"
    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Margin = [System.Windows.Thickness]::new(22)
    $scroll.Content = $panel
    $dialog.Content = $scroll

    function Add-DialogText {
        param([string]$Text, [int]$Size = 12, [string]$Color = "MutedBrush", [switch]$Bold)
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text = $Text
        $tb.FontSize = $Size
        $tb.Foreground = $Window.Resources[$Color]
        $tb.TextWrapping = "Wrap"
        $tb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        if ($Bold) { $tb.FontWeight = "SemiBold" }
        $panel.Children.Add($tb) | Out-Null
        return $tb
    }

    function Add-DialogField {
        param([string]$Label, [string]$Value = "", [switch]$Secret)
        Add-DialogText $Label 11 "MutedBrush" | Out-Null
        if ($Secret) {
            $box = [System.Windows.Controls.PasswordBox]::new()
            $box.Password = $Value
        } else {
            $box = [System.Windows.Controls.TextBox]::new()
            $box.Text = $Value
        }
        $box.Height = 32
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
        $box.Padding = [System.Windows.Thickness]::new(8, 5, 8, 5)
        $box.Background = $Window.Resources["PanelAltBrush"]
        $box.Foreground = $Window.Resources["TextBrush"]
        $box.BorderBrush = $Window.Resources["LineBrush"]
        $panel.Children.Add($box) | Out-Null
        return $box
    }

    Add-DialogText "AI Model Agent" 22 "TextBrush" -Bold | Out-Null
    Add-DialogText "Choose the primary model provider and fill API settings used by NeoCore Doctor. Local providers can run without paid API keys." 12 "MutedBrush" | Out-Null

    Add-DialogText "Primary Provider" 11 "MutedBrush" | Out-Null
    $providerCombo = [System.Windows.Controls.ComboBox]::new()
    $providerCombo.Height = 34
    $providerCombo.Margin = [System.Windows.Thickness]::new(0, 0, 0, 14)
    foreach ($provider in @("neocore", "ollama", "openai_compatible", "huggingface", "gemini", "nullclaw", "rule_based")) {
        [void]$providerCombo.Items.Add($provider)
    }
    $primaryProvider = if (@($cfg.provider_order).Count -gt 0) { [string]@($cfg.provider_order)[0] } else { "neocore" }
    $providerCombo.SelectedItem = $primaryProvider
    $panel.Children.Add($providerCombo) | Out-Null

    Add-DialogText "Local AI" 15 "TextBrush" -Bold | Out-Null
    $ollamaEndpoint = Add-DialogField "Ollama generate endpoint" (Get-NeoConfigString $cfg.ollama "endpoint" "http://127.0.0.1:11434/api/generate")
    $ollamaTags = Add-DialogField "Ollama tags endpoint" (Get-NeoConfigString $cfg.ollama "tags_endpoint" "http://127.0.0.1:11434/api/tags")
    $ollamaModels = Add-DialogField "Preferred local models, comma-separated" ((@($cfg.ollama.preferred_models) -join ", "))

    Add-DialogText "OpenAI-Compatible API" 15 "TextBrush" -Bold | Out-Null
    $openAiEndpoint = Add-DialogField "Chat completions endpoint" (Get-NeoConfigString $cfg.openai_compatible "endpoint" "https://api.openai.com/v1/chat/completions")
    $openAiModel = Add-DialogField "Model name" (Get-NeoConfigString $cfg.openai_compatible "model" "gpt-4.1-mini")
    $openAiKey = Add-DialogField "API key" (Get-NeoConfigString $cfg.openai_compatible "api_key" "") -Secret

    Add-DialogText "Hugging Face / Gemini / NullClaw" 15 "TextBrush" -Bold | Out-Null
    $hfModel = Add-DialogField "Hugging Face model or endpoint" (Get-NeoConfigString $cfg.huggingface "model" "")
    $hfKey = Add-DialogField "Hugging Face token" (Get-NeoConfigString $cfg.huggingface "api_key" "") -Secret
    $geminiModel = Add-DialogField "Gemini model" (Get-NeoConfigString $cfg.gemini "model" "gemini-1.5-flash")
    $geminiKey = Add-DialogField "Gemini API key" (Get-NeoConfigString $cfg.gemini "api_key" "") -Secret
    $nullClawCommand = Add-DialogField "NullClaw command" (Get-NeoConfigString $cfg.nullclaw "command" "nullclaw")

    Add-DialogText "Voice Command" 15 "TextBrush" -Bold | Out-Null
    $voiceEnabled = [System.Windows.Controls.CheckBox]::new()
    $voiceEnabled.Content = "Enable voice command profile"
    $voiceEnabled.IsChecked = Get-NeoConfigBool $cfg.voice "enabled" $false
    $voiceEnabled.Foreground = $Window.Resources["TextBrush"]
    $voiceEnabled.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
    $panel.Children.Add($voiceEnabled) | Out-Null
    $voiceLanguage = Add-DialogField "Voice language" (Get-NeoConfigString $cfg.voice "language" "id-ID")
    $voiceWake = Add-DialogField "Wake phrase" (Get-NeoConfigString $cfg.voice "wake_phrase" "neo optimize")

    $buttons = [System.Windows.Controls.StackPanel]::new()
    $buttons.Orientation = "Horizontal"
    $buttons.HorizontalAlignment = "Right"
    $buttons.Margin = [System.Windows.Thickness]::new(0, 8, 0, 0)

    $save = [System.Windows.Controls.Button]::new()
    $save.Content = "Save AI Model"
    $save.MinWidth = 130
    $save.Height = 36
    $save.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
    $save.Background = $Window.Resources["AccentBrush"]
    $save.Foreground = $Window.Resources["AccentTextBrush"]

    $cancel = [System.Windows.Controls.Button]::new()
    $cancel.Content = "Cancel"
    $cancel.MinWidth = 90
    $cancel.Height = 36

    $buttons.Children.Add($save) | Out-Null
    $buttons.Children.Add($cancel) | Out-Null
    $panel.Children.Add($buttons) | Out-Null

    $cancel.Add_Click({ $dialog.Close() })
    $save.Add_Click({
        $primary = [string]$providerCombo.SelectedItem
        $order = New-Object System.Collections.Generic.List[string]
        foreach ($provider in @($primary, "neocore", "ollama", "openai_compatible", "huggingface", "gemini", "nullclaw", "rule_based")) {
            if (-not [string]::IsNullOrWhiteSpace($provider) -and -not $order.Contains($provider)) { $order.Add($provider) | Out-Null }
        }

        $modelConfig = [ordered]@{
            schema_version = "1.1"
            enabled = $true
            mode = "advisory_only"
            provider_order = @($order)
            neocore = [ordered]@{
                enabled = $true
                policy_path = "models\NeoCore.Policy.json"
                min_confidence = 0.25
                trainer = "tools\Train-NeoCore.ps1"
            }
            ollama = [ordered]@{
                enabled = $true
                endpoint = $ollamaEndpoint.Text
                tags_endpoint = $ollamaTags.Text
                preferred_models = @($ollamaModels.Text -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                temperature = 0.2
                num_predict = 900
                timeout_seconds = 45
            }
            openai_compatible = [ordered]@{
                enabled = (-not [string]::IsNullOrWhiteSpace($openAiEndpoint.Text) -and -not [string]::IsNullOrWhiteSpace($openAiModel.Text))
                endpoint = $openAiEndpoint.Text
                model = $openAiModel.Text
                api_key = $openAiKey.Password
                timeout_seconds = 60
            }
            huggingface = [ordered]@{
                enabled = (-not [string]::IsNullOrWhiteSpace($hfModel.Text))
                model = $hfModel.Text
                api_key = $hfKey.Password
                timeout_seconds = 60
            }
            gemini = [ordered]@{
                enabled = (-not [string]::IsNullOrWhiteSpace($geminiKey.Password))
                model = $geminiModel.Text
                api_key = $geminiKey.Password
                timeout_seconds = 60
            }
            nullclaw = [ordered]@{
                enabled = $true
                command = $nullClawCommand.Text
                arguments = @("agent", "-m")
                status_arguments = @("status")
                doctor_arguments = @("doctor")
                docs_url = "https://nullclaw.io/nullclaw/docs/getting-started"
                repo_url = "https://github.com/nullclaw/nullclaw"
                timeout_seconds = 75
                max_prompt_chars = 6000
            }
            voice = [ordered]@{
                enabled = [bool]$voiceEnabled.IsChecked
                language = $voiceLanguage.Text
                wake_phrase = $voiceWake.Text
                mode = "push_to_talk"
            }
            interactive = [ordered]@{
                enabled = $true
                default_mode = "operator"
                allow_confirmed_local_actions = $true
                require_confirmation_for_all_actions = $true
                transcript_enabled = $true
                max_turns = 80
            }
            rule_based = [ordered]@{ enabled = $true }
            policy = [ordered]@{
                allow_remote_execution = $false
                allow_secret_collection = $false
                allow_camera_capture = $false
                allow_microphone_capture = $false
                allow_biometric_collection = $false
                require_human_confirmation_for_remediation = $true
            }
        }

        $modelConfig | ConvertTo-Json -Depth 8 | Set-Content -Path $Script:ModelConfigPath -Encoding UTF8
        Update-AiProviderStatus
        Set-Status "AI model agent settings saved."
        $dialog.Close()
    })

    [void]$dialog.ShowDialog()
}

function Show-NeoUpdateManagerDialog {
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "NeoOptimize Update Manager"
    $dialog.Width = 780
    $dialog.Height = 520
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner = $Window
    $dialog.Background = $Window.Resources["PageBrush"]
    $dialog.Foreground = $Window.Resources["TextBrush"]
    $dialog.FontFamily = $Window.Resources["MainFontFamily"]

    $root = [System.Windows.Controls.Grid]::new()
    $root.Margin = [System.Windows.Thickness]::new(22)
    foreach ($height in @("Auto", "*", "Auto")) {
        $row = [System.Windows.Controls.RowDefinition]::new()
        $row.Height = $height
        $root.RowDefinitions.Add($row) | Out-Null
    }
    $dialog.Content = $root

    $header = [System.Windows.Controls.StackPanel]::new()
    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = "Update Manager"
    $title.FontSize = 26
    $title.FontWeight = "SemiBold"
    $title.Foreground = $Window.Resources["TextBrush"]
    $subtitle = [System.Windows.Controls.TextBlock]::new()
    $subtitle.Text = "Linux Mint style update flow: check, review, verify SHA-256, then update or repair NeoOptimize."
    $subtitle.FontSize = 12
    $subtitle.Foreground = $Window.Resources["MutedBrush"]
    $subtitle.TextWrapping = "Wrap"
    $subtitle.Margin = [System.Windows.Thickness]::new(0, 4, 0, 16)
    $header.Children.Add($title) | Out-Null
    $header.Children.Add($subtitle) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($header, 0)
    $root.Children.Add($header) | Out-Null

    $grid = [System.Windows.Controls.Grid]::new()
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new()) | Out-Null
    $grid.ColumnDefinitions.Add([System.Windows.Controls.ColumnDefinition]::new()) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($grid, 1)
    $root.Children.Add($grid) | Out-Null

    function New-UpdateInfoCard {
        param([string]$Title, [string]$Value, [string]$Note, [string]$Accent = "AccentBrush")
        $border = [System.Windows.Controls.Border]::new()
        $border.Background = $Window.Resources["PanelAltBrush"]
        $border.BorderBrush = $Window.Resources["LineBrush"]
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $border.Padding = [System.Windows.Thickness]::new(14)
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)

        $stack = [System.Windows.Controls.StackPanel]::new()
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $Title
        $label.Foreground = $Window.Resources["MutedBrush"]
        $label.FontSize = 11
        $valueText = [System.Windows.Controls.TextBlock]::new()
        $valueText.Text = $Value
        $valueText.Foreground = $Window.Resources[$Accent]
        $valueText.FontWeight = "SemiBold"
        $valueText.FontSize = 15
        $valueText.Margin = [System.Windows.Thickness]::new(0, 4, 0, 4)
        $noteText = [System.Windows.Controls.TextBlock]::new()
        $noteText.Text = $Note
        $noteText.Foreground = $Window.Resources["TextBrush"]
        $noteText.FontSize = 12
        $noteText.TextWrapping = "Wrap"
        $stack.Children.Add($label) | Out-Null
        $stack.Children.Add($valueText) | Out-Null
        $stack.Children.Add($noteText) | Out-Null
        $border.Child = $stack
        return $border
    }

    $left = [System.Windows.Controls.StackPanel]::new()
    $left.Children.Add((New-UpdateInfoCard "Installed Version" $Global:PRODUCT_VERSION "Public release metadata is synchronized with GitHub Releases." "AccentBrush")) | Out-Null
    $left.Children.Add((New-UpdateInfoCard "Integrity" "SHA-256 Required" "Every update package is verified before repair or installation." "GoodBrush")) | Out-Null
    $left.Children.Add((New-UpdateInfoCard "Policy" "Credential-Gated" "Update checks and repair actions require authorized update credentials." "WarnBrush")) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($left, 0)
    $grid.Children.Add($left) | Out-Null

    $right = [System.Windows.Controls.StackPanel]::new()
    $right.Children.Add((New-UpdateInfoCard "Recommended Flow" "Check First" "Review manifest metadata, version, channel, size, and checksum before applying updates." "AccentBrush")) | Out-Null
    $right.Children.Add((New-UpdateInfoCard "Repair Mode" "Automatic Repair" "If integrity scan finds missing or changed files, the verified installer can repair NeoOptimize." "GoodBrush")) | Out-Null
    $right.Children.Add((New-UpdateInfoCard "Distribution" "Release Channel" "Public downloads are distributed through GitHub Releases; WinGet, Chocolatey, and Scoop can be added later." "AccentBrush")) | Out-Null
    [System.Windows.Controls.Grid]::SetColumn($right, 1)
    $grid.Children.Add($right) | Out-Null

    function Invoke-UpdateManagerTask {
        param([string]$Label, [string]$Mode, [switch]$ForceRepair)
        if (-not (Try-BeginNeoUiTask $Label)) { return }
        $dialog.Close()
        $script = Join-Path $Script:Root "NeoOptimize.UpdateManager.ps1"
        $force = if ($ForceRepair) { " -ForceRepair" } else { "" }
        $command = "& $(Quote-Arg $script) -Mode $Mode$force"
        if (-not (Start-NeoProcess -Label $Label -CommandText $command)) {
            End-NeoUiTask -Message ("Ready after: {0}" -f $Label)
        }
    }

    function New-UpdateButton {
        param([string]$Label, [scriptblock]$Click, [switch]$Primary)
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = $Label
        $button.MinWidth = 132
        $button.Height = 36
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $button.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
        $button.Background = if ($Primary) { $Window.Resources["AccentBrush"] } else { $Window.Resources["PanelAltBrush"] }
        $button.Foreground = if ($Primary) { $Window.Resources["AccentTextBrush"] } else { $Window.Resources["TextBrush"] }
        $button.BorderBrush = if ($Primary) { $Window.Resources["AccentBrush"] } else { $Window.Resources["LineBrush"] }
        $button.Add_Click($Click.GetNewClosure())
        return $button
    }

    $buttons = [System.Windows.Controls.WrapPanel]::new()
    $buttons.HorizontalAlignment = "Right"
    $buttons.Margin = [System.Windows.Thickness]::new(0, 18, 0, 0)
    $buttons.Children.Add((New-UpdateButton "Check Updates" { Invoke-UpdateManagerTask "Check Updates" "Check" } -Primary)) | Out-Null
    $buttons.Children.Add((New-UpdateButton "Install Verified" { Invoke-UpdateManagerTask "Install Verified Update" "Update" })) | Out-Null
    $buttons.Children.Add((New-UpdateButton "Repair" { Invoke-UpdateManagerTask "Repair NeoOptimize" "Repair" -ForceRepair })) | Out-Null
    $buttons.Children.Add((New-UpdateButton "Integrity Scan" { Invoke-UpdateManagerTask "Integrity Scan" "Scan" })) | Out-Null
    $buttons.Children.Add((New-UpdateButton "Release Page" { Open-NeoExternalLink "https://github.com/NeoOptimize/NeoOptimize/releases/latest" })) | Out-Null
    $buttons.Children.Add((New-UpdateButton "Close" { $dialog.Close() })) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($buttons, 2)
    $root.Children.Add($buttons) | Out-Null

    [void]$dialog.ShowDialog()
}

function Show-AboutDialog {
    $dialog = [System.Windows.Window]::new()
    $dialog.Title = "About NeoOptimize"
    $dialog.Width = 860
    $dialog.Height = 560
    $dialog.WindowStartupLocation = "CenterOwner"
    $dialog.Owner = $Window
    $dialog.Background = $Window.Resources["PageBrush"]
    $dialog.Foreground = $Window.Resources["TextBrush"]
    $dialog.FontFamily = $Window.Resources["MainFontFamily"]

    $scroll = [System.Windows.Controls.ScrollViewer]::new()
    $scroll.VerticalScrollBarVisibility = "Auto"
    $panel = [System.Windows.Controls.StackPanel]::new()
    $panel.Margin = [System.Windows.Thickness]::new(24)
    $scroll.Content = $panel
    $dialog.Content = $scroll

    function Add-AboutText {
        param([string]$Text, [int]$Size = 12, [string]$Color = "MutedBrush", [switch]$Bold)
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text = $Text
        $tb.FontSize = $Size
        $tb.Foreground = $Window.Resources[$Color]
        $tb.TextWrapping = "Wrap"
        $tb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        if ($Bold) { $tb.FontWeight = "SemiBold" }
        $panel.Children.Add($tb) | Out-Null
        return $tb
    }

    function Add-AboutBox {
        param([string]$Title, [string]$Body, [string]$Accent = "AccentBrush")
        $box = [System.Windows.Controls.Border]::new()
        $box.Background = $Window.Resources["PanelAltBrush"]
        $box.BorderBrush = $Window.Resources["LineBrush"]
        $box.BorderThickness = [System.Windows.Thickness]::new(1)
        $box.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $box.Padding = [System.Windows.Thickness]::new(14)
        $box.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)

        $stack = [System.Windows.Controls.StackPanel]::new()
        $titleText = [System.Windows.Controls.TextBlock]::new()
        $titleText.Text = $Title
        $titleText.Foreground = $Window.Resources[$Accent]
        $titleText.FontWeight = "SemiBold"
        $titleText.FontSize = 13
        $titleText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $bodyText = [System.Windows.Controls.TextBlock]::new()
        $bodyText.Text = $Body
        $bodyText.Foreground = $Window.Resources["TextBrush"]
        $bodyText.FontSize = 12
        $bodyText.TextWrapping = "Wrap"
        $stack.Children.Add($titleText) | Out-Null
        $stack.Children.Add($bodyText) | Out-Null
        $box.Child = $stack
        $panel.Children.Add($box) | Out-Null
    }

    function New-AboutButton {
        param([string]$Label, [scriptblock]$Click, [switch]$Primary)
        $button = [System.Windows.Controls.Button]::new()
        $button.Content = $Label
        $button.MinWidth = 128
        $button.Height = 36
        $button.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $button.Padding = [System.Windows.Thickness]::new(12, 6, 12, 6)
        $button.Background = if ($Primary) { $Window.Resources["AccentBrush"] } else { $Window.Resources["PanelAltBrush"] }
        $button.Foreground = if ($Primary) { $Window.Resources["AccentTextBrush"] } else { $Window.Resources["TextBrush"] }
        $button.BorderBrush = if ($Primary) { $Window.Resources["AccentBrush"] } else { $Window.Resources["LineBrush"] }
        $button.Add_Click($Click.GetNewClosure())
        return $button
    }

    Add-AboutText "NeoOptimize" 26 "TextBrush" -Bold | Out-Null
    Add-AboutText "AI-powered Windows optimization and maintenance platform." 13 "MutedBrush" | Out-Null
    Add-AboutText "Made with love at Zenthralix-Lab with Codex." 13 "AccentBrush" -Bold | Out-Null
    Add-AboutText "Email: neooptimizeofficial@gmail.com" 12 "TextBrush" | Out-Null

    Add-AboutText "Product Focus" 16 "TextBrush" -Bold | Out-Null
    Add-AboutBox "Community Free" "Local optimizer, basic health checks, local-first AI guidance, safe cleanup, diagnostics, and transparent safety documentation." "GoodBrush"
    Add-AboutBox "Pro Personal" "AI Doctor, scheduled maintenance, update assistant, richer reports, before/after benchmark analysis, and safer one-click workflows." "AccentBrush"
    Add-AboutBox "Self-Hosted / Team Ready" "Private deployment options, controlled maintenance policy, signed update flow, audit reports, and advanced security guardrails." "WarnBrush"

    Add-AboutText "Support" 16 "TextBrush" -Bold | Out-Null
    Add-AboutText "Support helps keep NeoOptimize maintained, tested, documented, and available for the community." 12 "MutedBrush" | Out-Null
    Add-AboutText "Email: neooptimizeofficial@gmail.com" 12 "TextBrush" | Out-Null

    $linkPanel = [System.Windows.Controls.WrapPanel]::new()
    $linkPanel.Margin = [System.Windows.Thickness]::new(0, 4, 0, 12)
    $linkPanel.Children.Add((New-AboutButton "Buy Me a Coffee" { Open-NeoExternalLink "https://buymeacoffee.com/nol.eight" })) | Out-Null
    $linkPanel.Children.Add((New-AboutButton "Saweria" { Open-NeoExternalLink "https://saweria.co/dtechtive" })) | Out-Null
    $linkPanel.Children.Add((New-AboutButton "Dana" { Open-NeoExternalLink "https://ik.imagekit.io/dtechtive/Dana" })) | Out-Null
    $linkPanel.Children.Add((New-AboutButton "Email" { Open-NeoExternalLink "mailto:neooptimizeofficial@gmail.com" })) | Out-Null
    $panel.Children.Add($linkPanel) | Out-Null

    $buttonPanel = [System.Windows.Controls.WrapPanel]::new()
    $buttonPanel.HorizontalAlignment = "Right"
    $buttonPanel.Margin = [System.Windows.Thickness]::new(0, 10, 0, 0)
    $buttonPanel.Children.Add((New-AboutButton "Update NeoOptimize" {
        $dialog.Close()
        Start-NeoAction "NeoUpdate"
    } -Primary)) | Out-Null
    $buttonPanel.Children.Add((New-AboutButton "Close" { $dialog.Close() })) | Out-Null
    $panel.Children.Add($buttonPanel) | Out-Null

    [void]$dialog.ShowDialog()
}

function Apply-Localization {
    Set-ControlText "AppTaglineText" (T "AppTagline")
    Set-ControlText "MainTitleText" (T "MainTitle")
    Set-ControlText "SubtitleText" (T "Subtitle")
    Set-ControlText "HealthLabelText" (T "Health")
    Set-ControlText "RmmLabelText" (T "Rmm")
    Set-ControlText "CpuLabel" "CPU"
    Set-ControlText "GpuLabel" "GPU"
    Set-ControlText "MemoryLabel" (T "Memory")
    Set-ControlText "DiskLabel" (T "Disk")
    Set-ControlText "WindowsLabel" "NETWORK"
    Set-ControlContent "BtnOverview" (T "Overview")
    Set-ControlContent "BtnAdvisor" (T "Advisor")
    Set-ControlContent "BtnProviders" (T "Providers")
    Set-ControlContent "BtnAudit" (T "Audit")
    Set-ControlContent "BtnRestore" (T "Restore")
    Set-ControlContent "BtnReports" (T "Reports")
    Set-ControlContent "BtnConsole" (T "Console")
    Set-ControlContent "BtnUsers" (T "Users")
    Set-ControlContent "BtnSettings" (T "Settings")
    Set-ControlContent "BtnAbout" (T "About")
    Set-ControlContent "BtnRefresh" ("↻ " + (T "Refresh"))
    Set-ControlContent "BtnFullAuto" (T "FullAuto")
    Set-ControlText "CpuDetailText" "Processor load"
    Set-ControlText "GpuDetailText" "Graphics load"
    Set-ControlText "RamDetailText" "Memory pressure"
    Set-ControlText "DiskDetailText" "Disk I/O + free space"
    Set-ControlText "UptimeText" "Network throughput"
    Set-ActiveNav "BtnOverview"
    Set-ControlText "ModulesTitleText" (("{0} — {1} AVAILABLE" -f (T "Modules"), $Script:OverviewModules.Count).ToUpper())
    Set-ControlText "ModulesNoteText" (T "ModulesNote")
    Set-ControlText "TaskQueueTitleText" (T "TaskQueueTitle")
    Set-ControlText "TaskQueueEmptyText" (T "TaskQueueEmpty")
    Set-ControlText "AiPanelText" (T "AiPanel")
    Set-ControlText "AiNoteText" (T "AiNote")
    Set-ControlText "AiStatusText" (T "AiChecking")
    Set-ControlContent "BtnAiAdvisor2" (T "Advisor")
    Set-ControlContent "BtnAiOperator2" "Ask NEO"
    Set-ControlContent "BtnAiProviders2" "AI Model Settings"
    Set-ControlContent "BtnStartMiniTray" "Start Mini Tray"
    Set-ControlContent "BtnNullClawDocs" (T "NullClawDocs")
    Set-ControlText "CloudTitleText" (T "Cloud")
    Set-ControlText "CloudNoteText" (T "CloudNote")
    Set-ControlContent "BtnCloudStatus" (T "CloudStatus")
    Set-ControlContent "BtnCloudOpen" (T "CloudOpen")
    Render-Operations
    Render-Connectors
    Update-AiProviderStatus
}

function Update-SystemDashboard {
    param([switch]$ForceRmm)

    Initialize-OverviewSeries

    $scoreText = Find-Control "ScoreText"
    $healthText = Find-Control "HealthText"
    $cpuLabel = Find-Control "CpuLabel"
    $cpuText = Find-Control "CpuText"
    $cpuDetail = Find-Control "CpuDetailText"
    $gpuLabel = Find-Control "GpuLabel"
    $gpuText = Find-Control "GpuText"
    $gpuDetail = Find-Control "GpuDetailText"
    $ramLabel = Find-Control "MemoryLabel"
    $ramText = Find-Control "RamText"
    $ramDetail = Find-Control "RamDetailText"
    $diskLabel = Find-Control "DiskLabel"
    $diskText = Find-Control "DiskText"
    $diskDetail = Find-Control "DiskDetailText"
    $osLabel = Find-Control "WindowsLabel"
    $osText = Find-Control "OsText"
    $uptimeText = Find-Control "UptimeText"
    $overviewScore = Find-Control "OverviewScoreText"
    $overviewHealth = Find-Control "OverviewHealthText"
    $healthRing = Find-Control "HealthRingBorder"
    $modulesTitle = Find-Control "ModulesTitleText"
    $modulesNote = Find-Control "ModulesNoteText"
    $cpuCanvas = Find-Control "CpuChartCanvas"
    $ramCanvas = Find-Control "RamChartCanvas"
    $netCanvas = Find-Control "NetworkChartCanvas"
    $tasksPanel = Find-Control "TasksBarsPanel"
    $rmmStatus = Find-Control "RmmStatusText"
    $rmmDetail = Find-Control "RmmDetailText"

    $managedSystems = 0
    $onlineNow = 0
    $offlineCount = 0
    $tasksToday = 0
    $rmmSnapshot = $Script:RmmSnapshot
    $rmmAgents = @()

    $shouldRefreshRmm = $ForceRmm -or $null -eq $rmmSnapshot -or ((Get-Date) - $Script:LastRmmRefresh).TotalSeconds -ge 10
    if ($shouldRefreshRmm) {
        if ((-not $ForceRmm) -and (Get-Date) -lt $Script:RmmStartupDeferUntil) {
            $rmmSnapshot = [PSCustomObject]@{
                connected = $false
                authenticated = $false
                server_url = ""
                health = $null
                stats = $null
                agents = @()
                commands = @()
                error = "Local mode"
            }
            $Script:RmmSnapshot = $rmmSnapshot
        } else {
            $rmmSnapshot = Get-RmmSnapshot
            $Script:LastRmmRefresh = Get-Date
        }
    }

    if ($rmmSnapshot -and $rmmSnapshot.authenticated) {
        $rmmAgents = @($rmmSnapshot.agents)
        $managedSystems = $rmmAgents.Count
        $onlineNow = @($rmmAgents | Where-Object { $_.live_status -eq "online" -or $_.status -eq "online" }).Count
        $offlineCount = [math]::Max(0, $managedSystems - $onlineNow)
        $tasksToday = @($rmmSnapshot.commands).Count

        $commandGroups = @($rmmSnapshot.commands | Group-Object -Property type)
        if ($commandGroups.Count -gt 0) {
            $Script:TaskBreakdown = @($commandGroups | Select-Object -First 6 | ForEach-Object {
                @{ Name = ([string]$_.Name).Substring(0, [math]::Min(8, ([string]$_.Name).Length)); Count = $_.Count }
            })
        }
    }

    try {
        $snapshot = Get-NeoSystemSnapshot -Force:$ForceRmm
        if (-not $snapshot) { throw "System snapshot unavailable" }

        $os = $snapshot.OperatingSystem
        $cpu = $snapshot.Processor
        $cs = $snapshot.ComputerSystem
        $disk = $snapshot.DiskC

        $cpuLoads = @()
        if ($cpu -and $null -ne $cpu.LoadPercentage) { $cpuLoads = @($cpu.LoadPercentage) }
        $cpuLoad = [math]::Round((Get-NeoCounterValue "\Processor(_Total)\% Processor Time"), 1)
        if ($cpuLoad -le 0 -and $cpuLoads.Count -gt 0) { $cpuLoad = [math]::Round((($cpuLoads | Measure-Object -Average).Average), 1) }
        $gpuLoad = Get-NeoGpuUsage
        $gpu = $snapshot.Gpu
        $diskBytes = Get-NeoCounterValue "\LogicalDisk(_Total)\Disk Bytes/sec" -Sum
        $netBytes = Get-NeoCounterValue "\Network Interface(*)\Bytes Total/sec" -Sum

        $ramTotal = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
        $ramFree = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $ramUsedPct = if ($ramTotal -gt 0) { [math]::Round((($ramTotal - $ramFree) / $ramTotal) * 100) } else { 0 }
        $diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskSize = [math]::Round($disk.Size / 1GB, 1)
        $diskFreePct = if ($diskSize -gt 0) { [math]::Round(($diskFree / $diskSize) * 100) } else { 0 }
        $uptime = (Get-Date) - $os.LastBootUpTime

        $score = 82
        if ($diskFreePct -lt 10) { $score -= 25 } elseif ($diskFreePct -lt 18) { $score -= 12 }
        if ($ramUsedPct -gt 90) { $score -= 18 } elseif ($ramUsedPct -gt 80) { $score -= 8 }
        if ($uptime.TotalDays -gt 14) { $score -= 8 }
        if ($score -lt 0) { $score = 0 }

        $scoreBrush = if ($score -ge 90) { "GoodBrush" } elseif ($score -ge 75) { "WarnBrush" } else { "DangerBrush" }
        $scoreGrade = if ($score -ge 90) { "EXCELLENT" } elseif ($score -ge 75) { "GOOD" } elseif ($score -ge 60) { "FAIR" } else { "NEEDS WORK" }

        if ($scoreText) { $scoreText.Text = [string]$score; $scoreText.Foreground = $Window.Resources[$scoreBrush] }
        if ($healthText) { $healthText.Text = if ($score -ge 85) { T "Healthy" } elseif ($score -ge 65) { T "NeedsAttention" } else { T "HighRisk" }; $healthText.Foreground = $Window.Resources[$scoreBrush] }

        if ($overviewScore) { $overviewScore.Text = [string]$score; $overviewScore.Foreground = $Window.Resources[$scoreBrush] }
        if ($overviewHealth) { $overviewHealth.Text = $scoreGrade; $overviewHealth.Foreground = $Window.Resources[$scoreBrush] }
        if ($healthRing) { $healthRing.BorderBrush = $Window.Resources[$scoreBrush] }

        if ($cpuLabel) { $cpuLabel.Text = "CPU" }
        if ($cpuText) { $cpuText.Text = ("{0:N0}%" -f $cpuLoad); $cpuText.Foreground = if ($cpuLoad -ge 85) { $Window.Resources["DangerBrush"] } elseif ($cpuLoad -ge 65) { $Window.Resources["WarnBrush"] } else { $Window.Resources["AccentBrush"] } }
        if ($cpuDetail) { $cpuDetail.Text = ([string]$cpu.Name).Substring(0, [math]::Min(38, ([string]$cpu.Name).Length)) }

        if ($gpuLabel) { $gpuLabel.Text = "GPU" }
        if ($gpuText) { $gpuText.Text = ("{0:N0}%" -f $gpuLoad); $gpuText.Foreground = if ($gpuLoad -ge 85) { $Window.Resources["DangerBrush"] } elseif ($gpuLoad -ge 65) { $Window.Resources["WarnBrush"] } else { $Window.Resources["GoodBrush"] } }
        if ($gpuDetail) { $gpuDetail.Text = if ($gpu -and $gpu.Name) { ([string]$gpu.Name).Substring(0, [math]::Min(38, ([string]$gpu.Name).Length)) } else { "GPU counter unavailable" } }

        if ($ramLabel) { $ramLabel.Text = (T "Memory").ToUpper() }
        if ($ramText) { $ramText.Text = ("{0:N0}%" -f $ramUsedPct); $ramText.Foreground = if ($ramUsedPct -ge 90) { $Window.Resources["DangerBrush"] } elseif ($ramUsedPct -ge 80) { $Window.Resources["WarnBrush"] } else { $Window.Resources["GoodBrush"] } }
        if ($ramDetail) { $ramDetail.Text = ("{0:N1} GB free / {1:N1} GB total" -f $ramFree, $ramTotal) }

        if ($diskLabel) { $diskLabel.Text = (T "Disk").ToUpper() }
        if ($diskText) { $diskText.Text = Format-NeoRate $diskBytes; $diskText.Foreground = if ($diskFreePct -lt 10) { $Window.Resources["DangerBrush"] } elseif ($diskFreePct -lt 18) { $Window.Resources["WarnBrush"] } else { $Window.Resources["AccentBrush"] } }
        if ($diskDetail) { $diskDetail.Text = ("C: {0:N1} GB free ({1:N0}%)" -f $diskFree, $diskFreePct) }

        if ($osLabel) { $osLabel.Text = "NETWORK" }
        if ($osText) { $osText.Text = Format-NeoRate $netBytes; $osText.Foreground = $Window.Resources["WarnBrush"] }
        if ($uptimeText) { $uptimeText.Text = ("Uptime {0:N1} days | {1} online endpoints" -f $uptime.TotalDays, $onlineNow) }

        Push-OverviewSeriesSample -Series $Script:CpuSeries -Value ([math]::Max(0, [math]::Min(100, $cpuLoad)))
        Push-OverviewSeriesSample -Series $Script:GpuSeries -Value ([math]::Max(0, [math]::Min(100, $gpuLoad)))
        Push-OverviewSeriesSample -Series $Script:RamSeries -Value ([math]::Max(0, [math]::Min(100, $ramUsedPct)))
        Push-OverviewSeriesSample -Series $Script:DiskSeries -Value ([math]::Max(0, [math]::Min(100, $diskBytes / 1MB)))
        Push-OverviewSeriesSample -Series $Script:NetSeries -Value ([math]::Max(0, [math]::Min(100, $netBytes / 1MB)))

        if ($cpuCanvas) { Draw-LineChart -Canvas $cpuCanvas -Series $Script:CpuSeries -StrokeColor "#00F0FF" -FillColor "#2000F0FF" }
        if ($ramCanvas) { Draw-LineChart -Canvas $ramCanvas -Series $Script:RamSeries -StrokeColor "#A855F7" -FillColor "#20A855F7" }
        if ($netCanvas) { Draw-LineChart -Canvas $netCanvas -Series $Script:NetSeries -StrokeColor "#00FF9D" -FillColor "#2000FF9D" }
        if ($tasksPanel) { Draw-TaskBars -Panel $tasksPanel -Items $Script:TaskBreakdown -BarColor "#A855F7" }

        if ($rmmDetail) { $rmmDetail.Text = "Fleet monitor: $onlineNow online / $managedSystems managed" }
        if ($rmmStatus) {
            $rmmStatus.Text = if ($score -ge 85) { "Running" } elseif ($score -ge 65) { "Stable" } else { "Attention" }
            $rmmStatus.Foreground = $Window.Resources[$scoreBrush]
        }
    } catch {
        if ($scoreText) { $scoreText.Text = "--"; $scoreText.Foreground = $Window.Resources["MutedBrush"] }
        if ($healthText) { $healthText.Text = T "NoTelemetry"; $healthText.Foreground = $Window.Resources["MutedBrush"] }
        if ($overviewScore) { $overviewScore.Text = "--"; $overviewScore.Foreground = $Window.Resources["MutedBrush"] }
        if ($overviewHealth) { $overviewHealth.Text = "NO DATA"; $overviewHealth.Foreground = $Window.Resources["MutedBrush"] }
        if ($cpuText) { $cpuText.Text = "0"; $cpuText.Foreground = $Window.Resources["AccentBrush"] }
        if ($ramText) { $ramText.Text = "0"; $ramText.Foreground = $Window.Resources["GoodBrush"] }
        if ($diskText) { $diskText.Text = "0"; $diskText.Foreground = $Window.Resources["DangerBrush"] }
        if ($osText) { $osText.Text = "0"; $osText.Foreground = $Window.Resources["WarnBrush"] }
    }

    if ($rmmStatus) {
        if ($rmmSnapshot.connected -and $rmmSnapshot.authenticated) {
            $rmmStatus.Text = "Fleet sync active"
            $rmmStatus.Foreground = $Window.Resources["GoodBrush"]
        } elseif ($rmmSnapshot.connected) {
            $rmmStatus.Text = "Fleet monitor ready"
            $rmmStatus.Foreground = $Window.Resources["GoodBrush"]
        } else {
            $rmmStatus.Text = "Local monitor"
            $rmmStatus.Foreground = $Window.Resources["MutedBrush"]
        }
    }
    if ($rmmDetail) {
        $rmmDetail.Text = if ($managedSystems -gt 0) { "$onlineNow online / $managedSystems endpoints" } else { "Local dashboard mode" }
    }

    Render-ManagedSystems $rmmAgents
    if ($modulesTitle) {
        $modulesTitle.Text = if ([string]::IsNullOrWhiteSpace($Script:ModulePageTitle)) {
            ("{0} — {1} {2}" -f (T "Modules"), @($Script:L[$Script:UiLanguage].Operations).Count, (T "Available")).ToUpper()
        } else {
            $Script:ModulePageTitle.ToUpper()
        }
    }
    if ($modulesNote) { $modulesNote.Text = $Script:ModulePageNote }
    if (-not $Script:UiTaskRunning) {
        Set-Status ("{0}: {1}" -f (T "Refreshed"), (Get-Date -Format "HH:mm:ss"))
    }
}

$languageCombo = Find-Control "LanguageCombo"
$themeCombo = Find-Control "ThemeCombo"
$Script:UiInitializing = $true
Set-ComboSelectionByTag -Combo $languageCombo -Tag $Script:UiLanguage
Set-ComboSelectionByTag -Combo $themeCombo -Tag $Script:UiTheme
$Script:UiInitializing = $false

$languageCombo.Add_SelectionChanged({
    if ($Script:UiInitializing) { return }
    $item = $languageCombo.SelectedItem
    if ($item -and $item.Tag) {
        $Script:UiLanguage = [string]$item.Tag
        Save-UiConfig
        Apply-Localization
        Update-SystemDashboard
        Set-Status (T "Saved")
    }
})
$themeCombo.Add_SelectionChanged({
    if ($Script:UiInitializing) { return }
    $item = $themeCombo.SelectedItem
    if ($item -and $item.Tag) {
        $Script:UiTheme = [string]$item.Tag
        Save-UiConfig
        Apply-Theme
        Render-Operations
        Render-Connectors
        Set-Status (T "Saved")
    }
})

Add-ControlClick "BtnOverview" { Show-NeoDashboardPage; Update-SystemDashboard }
Add-ControlClick "BtnAdvisor" { Show-NeoModulesPage -Group "Diagnostics" -NavName "BtnAdvisor" -Title (T "Advisor") -Subtitle "AI Doctor, deep scan, diagnostics, disk scan, and endpoint audit." }
Add-ControlClick "BtnProviders" { Show-NeoModulesPage -Group "Security" -NavName "BtnProviders" -Title (T "Providers") -Subtitle "Security hardening, privacy, network safety, and service profiles." }
Add-ControlClick "BtnAudit" { Show-NeoAiPage -NavName "BtnAudit" }
Add-ControlClick "BtnRestore" { Show-NeoModulesPage -Group "Optimize" -NavName "BtnRestore" -Title (T "Restore") -Subtitle "Safe maintenance, cleanup, performance, power, updates, and signed app update." }
Add-ControlClick "BtnReports" { Show-NeoReportsPage -NavName "BtnReports" }
Add-ControlClick "BtnConsole" {
    Show-NeoModulesPage -Group "Disk" -NavName "BtnConsole" -Title (T "Console") -Subtitle "Disk status, scan, repair, TRIM, and Windows health repair tools."
}
Add-ControlClick "BtnRefresh" { Invoke-NeoUiTask -Label "Dashboard refresh" -Work { Update-SystemDashboard -ForceRmm } }
Add-ControlClick "BtnFullAuto" { Start-NeoFullAuto }
Add-ControlClick "BtnOverviewDoctor" { Invoke-AiDoctor }
Add-ControlClick "BtnOverviewSafeCare" { Start-NeoFullAuto }
Add-ControlClick "BtnOverviewOptimize" { Show-NeoModulesPage -Group "Optimize" -NavName "BtnRestore" -Title (T "Restore") -Subtitle "Safe maintenance, cleanup, performance, power, updates, and signed app update." }
Add-ControlClick "BtnOverviewReports" { Show-NeoReportsPage -NavName "BtnReports" }
Add-ControlClick "BtnAiAdvisor2" { Start-NeoAction "AIPlan" }
Add-ControlClick "BtnAiOperator2" { Start-NeoAction "AIInteractive" }
Add-ControlClick "BtnAiProviders2" { Invoke-NeoUiTask -Label "AI Model Settings" -Work { Show-AiModelSettings } }
Add-ControlClick "BtnStartMiniTray" { Start-NeoMiniTray }
Add-ControlClick "BtnNullClawDocs" { Start-NeoAction "NullClawDocs" }
Add-ControlClick "BtnCloudStatus" { Start-NeoAction "CloudStatus" }
Add-ControlClick "BtnCloudOpen" { Start-NeoAction "CloudOpen" }
Add-ControlClick "BtnOpenReports" { Invoke-NeoUiTask -Label "Reports" -Work { Open-ReportsFolder } }
Add-ControlClick "BtnClearWorker" { Clear-NeoWorkerOutput }
Add-ControlClick "BtnOpenWorkerLog" { Open-NeoWorkerLog }
Add-ControlClick "BtnDiskStatusPage" { Start-NeoAction "DiskStatus" }
Add-ControlClick "BtnProfilePage" { Show-NeoProfileLoginDialog -Force | Out-Null }
Add-ControlClick "BtnModelSettingsPage" { Invoke-NeoUiTask -Label "AI Model Settings" -Work { Show-AiModelSettings } }
Add-ControlClick "BtnUsers" { Show-NeoProfileLoginDialog -Force | Out-Null }
Add-ControlClick "BtnSettings" { Show-NeoAiPage -NavName "BtnSettings" }
Add-ControlClick "BtnAbout" { Show-AboutDialog }

$healthRingClickTarget = Find-Control "HealthRingBorder"
if ($healthRingClickTarget) {
    $healthRingClickTarget.Cursor = [System.Windows.Input.Cursors]::Hand
    $healthRingClickTarget.Add_MouseLeftButtonUp({ Invoke-AiDoctor })
}

$Window.Add_Loaded({
    try {
        Apply-BrandAssets
        Apply-Theme
        Apply-Fonts
        Apply-Localization
        Show-NeoDashboardPage
        Set-Status (T "Ready")
        Update-SystemDashboard
        $Script:RefreshTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $Script:RefreshTimer.Interval = [TimeSpan]::FromSeconds($Script:LightRefreshSeconds)
        $Script:RefreshTimer.Add_Tick({ Update-SystemDashboard })
        $Script:RefreshTimer.Start()
        # Keep startup focused on monitoring. The local profile dialog remains
        # available from Profile/Users, but should not block every app launch.
    } catch {
        Write-UiLog "Loaded handler failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("NeoOptimize UI initialization failed: $($_.Exception.Message)", "NeoOptimize", "OK", "Error") | Out-Null
    }

    Write-UiLog "UI Loaded."
    # Full Auto stays manual so startup stays stable and visible.
})
$Window.Add_Closed({
    if ($Script:RefreshTimer) {
        try { $Script:RefreshTimer.Stop() } catch {}
    }
})
try {
    [void]$Window.ShowDialog()
} catch {
    Write-UiLog "ShowDialog failed: $($_.Exception.Message)"
    [System.Windows.MessageBox]::Show("NeoOptimize UI runtime error: $($_.Exception.Message)", "NeoOptimize", "OK", "Error") | Out-Null
    exit 1
}
