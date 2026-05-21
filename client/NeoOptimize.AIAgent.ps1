#Requires -Version 5.1
<#
.SYNOPSIS
    NeoCore AI advisor for NeoOptimize.

.DESCRIPTION
    Advisory-only local model layer. NeoCore is the built-in optimization
    policy model for NeoOptimize. Ollama and NullClaw are optional assistants,
    and the deterministic rule engine remains as a safety fallback.
#>

param(
    [ValidateSet("Analyze", "Plan", "Interactive", "Environment", "Providers", "OpenNullClawDocs", "TrainNeoCore", "ScriptForge")]
    [string]$Mode = "Analyze",
    [string]$Question = "",
    [switch]$NoOpen
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:ConfigPath = Join-Path $Script:Root "config\NeoOptimize.ModelAgent.json"
$Script:EnvironmentPath = Join-Path $Script:Root "config\NeoOptimize.AIEnvironment.json"
$Script:NeoCorePolicyPath = Join-Path $Script:Root "models\NeoCore.Policy.json"
$Script:SkillsPath = Join-Path $Script:Root "skills"
$Script:McpPath = Join-Path $Script:Root "mcp"
$Script:ReportDir = Join-Path $Script:Root "reports\ai"
if (-not (Test-Path $Script:ReportDir)) {
    New-Item -Path $Script:ReportDir -ItemType Directory -Force | Out-Null
}

function Read-AgentConfig {
    $fallback = [PSCustomObject]@{
        enabled = $true
        mode = "advisory_only"
        provider_order = @("neocore", "ollama", "openai_compatible", "huggingface", "gemini", "nullclaw", "rule_based")
        neocore = [PSCustomObject]@{
            enabled = $true
            policy_path = "models\NeoCore.Policy.json"
            min_confidence = 0.25
        }
        ollama = [PSCustomObject]@{
            enabled = $true
            endpoint = "http://127.0.0.1:11434/api/generate"
            tags_endpoint = "http://127.0.0.1:11434/api/tags"
            preferred_models = @("neo-light", "neo-light:latest", "neo", "neo:latest", "qwen2.5:3b-instruct", "llama3.2:3b", "phi3:mini", "gemma2:2b")
            temperature = 0.2
            num_predict = 900
            timeout_seconds = 30
        }
        nullclaw = [PSCustomObject]@{
            enabled = $false
            command = "tools\nullclaw.ps1"
            arguments = @("agent", "-m")
            status_arguments = @("status")
            doctor_arguments = @("doctor")
            docs_url = "https://nullclaw.io/nullclaw/docs/getting-started"
            repo_url = "https://github.com/nullclaw/nullclaw"
            timeout_seconds = 75
            max_prompt_chars = 6000
        }
        provider_activation = [PSCustomObject]@{
            auto_enable_from_env = $true
            allow_public_huggingface = $false
            never_persist_env_keys = $true
        }
        openai_compatible = [PSCustomObject]@{
            enabled = $false
            endpoint = "https://api.openai.com/v1/chat/completions"
            model = "gpt-4.1-mini"
            api_key = ""
            timeout_seconds = 60
            max_tokens = 1200
            temperature = 0.2
        }
        huggingface = [PSCustomObject]@{
            enabled = $false
            model = ""
            api_key = ""
            timeout_seconds = 60
            max_new_tokens = 900
            temperature = 0.2
        }
        gemini = [PSCustomObject]@{
            enabled = $false
            model = "gemini-1.5-flash"
            api_key = ""
            timeout_seconds = 60
            temperature = 0.2
            max_output_tokens = 1200
        }
        voice = [PSCustomObject]@{
            enabled = $false
            language = "id-ID"
            wake_phrase = "neo optimize"
            mode = "push_to_talk"
        }
        interactive = [PSCustomObject]@{
            enabled = $true
            default_mode = "operator"
            allow_confirmed_local_actions = $true
            require_confirmation_for_all_actions = $true
            transcript_enabled = $true
            max_turns = 80
        }
        script_forge = [PSCustomObject]@{
            enabled = $true
            default_shell = "powershell"
            output_dir = "reports\ai\scripts"
            read_only_by_default = $true
            require_apply_switch_for_changes = $true
            max_goal_chars = 500
        }
        rmm_telemetry = [PSCustomObject]@{
            enabled = $true
            sample_kind = "neo_ai_audit"
            send_on_plan = $true
            send_on_interactive_turn = $false
            send_on_interactive_close = $true
            include_verbose = $true
            include_snapshot = $true
            include_neocore_plan = $true
            max_recommendations = 8
            max_transcript_chars = 4000
        }
        rule_based = [PSCustomObject]@{ enabled = $true }
        policy = [PSCustomObject]@{
            allow_remote_execution = $false
            allow_secret_collection = $false
            allow_camera_capture = $false
            allow_microphone_capture = $false
            allow_biometric_collection = $false
            require_human_confirmation_for_remediation = $true
        }
    }

    if (-not (Test-Path $Script:ConfigPath)) { return $fallback }
    try {
        $cfg = Get-Content -Path $Script:ConfigPath -Raw | ConvertFrom-Json
        foreach ($name in @($fallback.PSObject.Properties.Name)) {
            if ($cfg.PSObject.Properties.Name -notcontains $name) {
                $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $fallback.$name -Force
            }
        }
        foreach ($name in @("neocore", "ollama", "nullclaw", "provider_activation", "openai_compatible", "huggingface", "gemini", "voice", "interactive", "script_forge", "rmm_telemetry", "rule_based", "policy")) {
            if ($null -eq $cfg.$name) {
                $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $fallback.$name -Force
            }
        }
        Initialize-AiProviderActivation -Config $cfg
        return $cfg
    } catch {
        Write-Warning "Model agent config invalid. Using built-in defaults."
        return $fallback
    }
}

function Get-AgentConfigString {
    param($Object, [string]$Name, [string]$Default = "")
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            $value = [string]$Object.$Name
            if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        }
    } catch { Write-Verbose $_.Exception.Message }
    return $Default
}

function Get-AgentConfigBool {
    param($Object, [string]$Name, [bool]$Default = $false)
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            return [bool]$Object.$Name
        }
    } catch { Write-Verbose $_.Exception.Message }
    return $Default
}

function Get-AgentConfigInt {
    param($Object, [string]$Name, [int]$Default = 0)
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            return [int]$Object.$Name
        }
    } catch { Write-Verbose $_.Exception.Message }
    return $Default
}

function Get-AgentConfigDouble {
    param($Object, [string]$Name, [double]$Default = 0.0)
    try {
        if ($Object -and $Object.PSObject.Properties.Name -contains $Name -and $null -ne $Object.$Name) {
            return [double]$Object.$Name
        }
    } catch { Write-Verbose $_.Exception.Message }
    return $Default
}

function Get-NeoBiosUuid {
    try {
        $csProduct = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction Stop | Select-Object -First 1
        if ($csProduct.UUID) { return [string]$csProduct.UUID }
    } catch { Write-Verbose $_.Exception.Message }
    return ""
}

function Read-NeoAgentAppSettings {
    $candidates = @(
        (Join-Path $Script:Root "..\agent\appsettings.json"),
        (Join-Path $Script:Root "appsettings.json"),
        (Join-Path $env:ProgramFiles "NeoOptimize\agent\appsettings.json"),
        (Join-Path $env:ProgramData "NeoOptimize\agent\appsettings.json")
    )

    foreach ($path in $candidates) {
        try {
            $resolved = [System.IO.Path]::GetFullPath($path)
            if (-not (Test-Path $resolved)) { continue }
            $json = Get-Content -Path $resolved -Raw | ConvertFrom-Json
            $serverUrl = ""
            $apiKey = ""
            if ($json.ServerUrl) { $serverUrl = [string]$json.ServerUrl }
            if ($json.ApiKey) { $apiKey = [string]$json.ApiKey }
            if ($json.Agent -and $json.Agent.ServerUrl) { $serverUrl = [string]$json.Agent.ServerUrl }
            if ($json.Agent -and $json.Agent.ApiKey) { $apiKey = [string]$json.Agent.ApiKey }
            if (-not [string]::IsNullOrWhiteSpace($serverUrl) -and -not [string]::IsNullOrWhiteSpace($apiKey)) {
                return [PSCustomObject]@{
                    server_url = $serverUrl.TrimEnd("/")
                    api_key = $apiKey
                    path = $resolved
                }
            }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return $null
}

function Get-NeoAiSeverity {
    param(
        [int]$HealthScore = 100,
        [object]$Snapshot = $null
    )

    if ($Snapshot) {
        if ($Snapshot.defender_realtime -eq $false) { return "high" }
        if (@($Snapshot.firewall_disabled_profiles).Count -gt 0) { return "high" }
        if ($Snapshot.disk_c_free_pct -le 5) { return "critical" }
    }
    if ($HealthScore -lt 45) { return "critical" }
    if ($HealthScore -lt 65) { return "high" }
    if ($HealthScore -lt 80) { return "medium" }
    return "info"
}

function Get-NeoPrimaryRmmCommand {
    param($Plan)

    try {
        foreach ($rec in @($Plan.recommendations)) {
            if ($rec.rmm_command) { return [string]$rec.rmm_command }
        }
    } catch { Write-Verbose $_.Exception.Message }
    return "SYSTEM_DIAGNOSTICS"
}

function New-NeoHostBaselinePayload {
    param([object]$Snapshot)

    if (-not $Snapshot) { return @{} }
    return [ordered]@{
        os = [ordered]@{
            name = $Snapshot.os
            version = $Snapshot.os_version
            build = $Snapshot.build
            architecture = $Snapshot.architecture
        }
        hardware = [ordered]@{
            manufacturer = $Snapshot.manufacturer
            model = $Snapshot.model
            cpu = $Snapshot.cpu
            cpu_cores = $Snapshot.cores
            cpu_threads = $Snapshot.threads
            ram_gb = $Snapshot.ram_total_gb
        }
        security = [ordered]@{
            defender_realtime = $Snapshot.defender_realtime
            defender_signature_age_days = $Snapshot.defender_signature_age_days
            firewall_disabled_profiles = @($Snapshot.firewall_disabled_profiles)
            pending_reboot = $Snapshot.pending_reboot
        }
        environment = [ordered]@{
            active_power_plan = $Snapshot.active_power_plan
            rmm_agent_status = $Snapshot.rmm_agent_status
            prior_ai_reports = $Snapshot.prior_ai_reports
        }
    }
}

function Send-NeoAiTelemetryToRmm {
    param(
        $Config,
        [object]$Snapshot,
        [string]$Provider,
        [string]$Analysis,
        [string]$ReportPath = "",
        [string]$JsonPath = "",
        [string]$TelemetryEvent = "plan",
        [string]$Question = "",
        [string[]]$Transcript = @(),
        [string[]]$ProviderErrors = @(),
        [object]$ScriptForge = $null
    )

    if (-not (Get-AgentConfigBool $Config.rmm_telemetry "enabled" $true)) { return $false }
    if ([Environment]::GetEnvironmentVariable("NEOOPTIMIZE_AI_TELEMETRY") -eq "0") { return $false }

    $agentConfig = Read-NeoAgentAppSettings
    if (-not $agentConfig) { return $false }
    $uuid = Get-NeoBiosUuid
    if ([string]::IsNullOrWhiteSpace($uuid)) { return $false }

    $plan = $Script:LastNeoCorePlan
    $healthScore = 100
    try {
        if ($plan -and $null -ne $plan.health_score) { $healthScore = [int]$plan.health_score }
        elseif ($Snapshot -and $Snapshot.disk_c_free_pct -lt 10) { $healthScore = 72 }
    } catch { Write-Verbose $_.Exception.Message }
    $severity = Get-NeoAiSeverity -HealthScore $healthScore -Snapshot $Snapshot
    $maxRecommendations = Get-AgentConfigInt $Config.rmm_telemetry "max_recommendations" 8
    if ($maxRecommendations -le 0) { $maxRecommendations = 8 }
    $recommendations = @()
    if ($plan -and $plan.recommendations) {
        $recommendations = @($plan.recommendations | Select-Object -First $maxRecommendations)
    }
    $summary = "NEO AI audit completed on $($env:COMPUTERNAME). Health score $healthScore/100."
    if ($ScriptForge) {
        $summary = "NEO Script Forge generated $($ScriptForge.shell) script: $($ScriptForge.goal)"
    }

    $transcriptText = ""
    if ($Transcript -and @($Transcript).Count -gt 0) {
        $maxChars = Get-AgentConfigInt $Config.rmm_telemetry "max_transcript_chars" 4000
        if ($maxChars -le 0) { $maxChars = 4000 }
        $transcriptText = (@($Transcript) -join "`r`n")
        if ($transcriptText.Length -gt $maxChars) {
            $transcriptText = $transcriptText.Substring($transcriptText.Length - $maxChars)
        }
    }

    $neoEnvelope = [ordered]@{
        source = "neo_ai"
        event = $TelemetryEvent
        provider = $Provider
        model = if ($plan -and $plan.model) { $plan.model } else { "NEO" }
        severity = $severity
        confidence = 0.78
        health_score = $healthScore
        summary = $summary
        recommended_command = Get-NeoPrimaryRmmCommand -Plan $plan
        recommendations = @($recommendations)
        provider_errors = @($ProviderErrors)
        question = $Question
        report = $ReportPath
        json_path = $JsonPath
        script_forge = $ScriptForge
        transcript_tail = $transcriptText
        features = if ($plan -and $plan.features) { $plan.features } else { @{} }
    }

    $metrics = [ordered]@{
        neo_ai = $neoEnvelope
        memory = [ordered]@{
            used_percent = if ($Snapshot) { $Snapshot.ram_used_pct } else { $null }
            available_bytes = if ($Snapshot) { [int64]([double]$Snapshot.ram_free_gb * 1GB) } else { $null }
        }
        disk = [ordered]@{
            free_gb = if ($Snapshot) { $Snapshot.disk_c_free_gb } else { $null }
            free_percent = if ($Snapshot) { $Snapshot.disk_c_free_pct } else { $null }
        }
        system = [ordered]@{
            process_count = if ($Snapshot) { $Snapshot.process_count } else { $null }
            service_count = if ($Snapshot) { $Snapshot.service_count } else { $null }
            startup_count = if ($Snapshot) { $Snapshot.startup_count } else { $null }
        }
    }

    $payload = [ordered]@{
        uuid = $uuid
        hostname = $env:COMPUTERNAME
        ts = (Get-Date).ToUniversalTime().ToString("o")
        schema_version = 2
        sample_kind = (Get-AgentConfigString $Config.rmm_telemetry "sample_kind" "neo_ai_audit")
        metrics = $metrics
        host_baseline = if (Get-AgentConfigBool $Config.rmm_telemetry "include_snapshot" $true) { New-NeoHostBaselinePayload -Snapshot $Snapshot } else { @{} }
        security_state = if ($Snapshot) {
            [ordered]@{
                defender_realtime = $Snapshot.defender_realtime
                firewall_disabled_profiles = @($Snapshot.firewall_disabled_profiles)
                pending_reboot = $Snapshot.pending_reboot
            }
        } else { @{} }
        verbose_info = if (Get-AgentConfigBool $Config.rmm_telemetry "include_verbose" $true) { [ordered]@{ neo_ai = $neoEnvelope } } else { @{} }
        bugs = [ordered]@{ neo_ai_provider_errors = @($ProviderErrors) }
        device_info = [ordered]@{
            computer_name = $env:COMPUTERNAME
            user_context = $env:USERNAME
        }
    }

    try {
        $body = $payload | ConvertTo-Json -Depth 12
        Invoke-RestMethod `
            -Uri ($agentConfig.server_url + "/api/v1/agent/telemetry") `
            -Method Post `
            -ContentType "application/json" `
            -Headers @{ "x-api-key" = $agentConfig.api_key } `
            -Body $body `
            -TimeoutSec 10 | Out-Null
        return $true
    } catch {
        Write-Warning "NEO telemetry was not delivered to RMM: $($_.Exception.Message)"
        return $false
    }
}

function Get-AgentSecret {
    param(
        $Object,
        [string]$Name,
        [string]$EnvironmentName,
        [string]$Default = ""
    )

    $value = Get-AgentConfigString $Object $Name ""
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        $envValue = [Environment]::GetEnvironmentVariable($EnvironmentName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) { return $envValue }
    }
    return $Default
}

function Initialize-AiProviderActivation {
    param($Config)

    if (-not (Get-AgentConfigBool $Config.provider_activation "auto_enable_from_env" $true)) { return }

    $openAiKey = Get-AgentSecret $Config.openai_compatible "api_key" "NEOOPTIMIZE_OPENAI_API_KEY"
    if (-not [string]::IsNullOrWhiteSpace($openAiKey)) {
        $Config.openai_compatible.enabled = $true
    }

    $hfModel = Get-AgentConfigString $Config.huggingface "model" ""
    $hfKey = Get-AgentSecret $Config.huggingface "api_key" "NEOOPTIMIZE_HF_TOKEN"
    $allowPublicHf = Get-AgentConfigBool $Config.provider_activation "allow_public_huggingface" $false
    if (-not [string]::IsNullOrWhiteSpace($hfModel) -and ($allowPublicHf -or -not [string]::IsNullOrWhiteSpace($hfKey))) {
        $Config.huggingface.enabled = $true
    }

    $geminiKey = Get-AgentSecret $Config.gemini "api_key" "NEOOPTIMIZE_GEMINI_API_KEY"
    if (-not [string]::IsNullOrWhiteSpace($geminiKey)) {
        $Config.gemini.enabled = $true
    }
}

function Add-NeoUniqueCatalogItems {
    param(
        [object[]]$Existing = @(),
        [object[]]$Incoming = @()
    )

    $map = [ordered]@{}
    foreach ($item in @($Existing) + @($Incoming)) {
        if (-not $item) { continue }
        $id = ""
        try {
            if ($item.PSObject.Properties.Name -contains "id") { $id = [string]$item.id }
            elseif ($item.PSObject.Properties.Name -contains "name") { $id = ([string]$item.name).ToLowerInvariant().Replace(" ", "_") }
        } catch { Write-Verbose $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $map[$id] = $item
    }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($value in $map.Values) { $result.Add($value) | Out-Null }
    return $result.ToArray()
}

function Read-NeoCatalogItems {
    param(
        [string]$Directory,
        [string]$ArrayProperty
    )

    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path $Directory)) { return @() }

    foreach ($file in @(Get-ChildItem -Path $Directory -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $json = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            if ($json.PSObject.Properties.Name -contains $ArrayProperty) {
                foreach ($item in @($json.$ArrayProperty)) { if ($item) { $items.Add($item) | Out-Null } }
            } elseif ($json.PSObject.Properties.Name -contains "id") {
                $items.Add($json) | Out-Null
            }
        } catch {
            Write-Warning "Catalog file ignored: $($file.Name) - $($_.Exception.Message)"
        }
    }
    return $items.ToArray()
}

function Import-NeoAiEnvironmentBundle {
    param($Environment)

    $skillItems = Read-NeoCatalogItems -Directory $Script:SkillsPath -ArrayProperty "skills"
    if ($skillItems.Count -gt 0) {
        $mergedSkills = Add-NeoUniqueCatalogItems -Existing @($Environment.skills) -Incoming @($skillItems)
        $Environment | Add-Member -NotePropertyName "skills" -NotePropertyValue $mergedSkills -Force
    }

    $mcpItems = Read-NeoCatalogItems -Directory $Script:McpPath -ArrayProperty "mcp_connectors"
    if ($mcpItems.Count -gt 0) {
        $mergedMcp = Add-NeoUniqueCatalogItems -Existing @($Environment.mcp_connectors) -Incoming @($mcpItems)
        $Environment | Add-Member -NotePropertyName "mcp_connectors" -NotePropertyValue $mergedMcp -Force
    }

    return $Environment
}

function Read-AiEnvironmentConfig {
    $fallback = [PSCustomObject]@{
        schema_version = "1.0"
        environment_name = "NeoOptimize AI-Empowered Environment"
        default_operator = "NEO - Neural Execution Operator"
        safety_mode = "human_confirmed"
        skills = @(
            [PSCustomObject]@{ id = "ai_doctor"; name = "AI Doctor"; action = "AIPlan"; type = "diagnostic"; risk = "read_only"; description = "Diagnose endpoint health and propose a safe module order." },
            [PSCustomObject]@{ id = "script_forge"; name = "NEO Script Forge"; action = "AIScriptForge"; type = "computer_use"; risk = "read_only_default"; description = "Generate safe PowerShell/CMD audit and maintenance scripts with SHA-256 metadata." },
            [PSCustomObject]@{ id = "safe_care"; name = "Safe Care"; action = "SmartOptimize"; type = "optimization"; risk = "medium"; description = "Balanced cleanup and performance maintenance." },
            [PSCustomObject]@{ id = "integrity"; name = "Integrity Scan"; action = "AgentAudit"; type = "security"; risk = "read_only"; description = "Audit endpoint policy, files, and safety posture." },
            [PSCustomObject]@{ id = "secure_update"; name = "Secure Update"; action = "NeoUpdate"; type = "update"; risk = "critical"; description = "Credential-gated update with SHA-256 verification and auto-repair." }
        )
        mcp_connectors = @(
            [PSCustomObject]@{ id = "rmm"; name = "RMM Control Plane"; enabled = $true; access = "server"; secret_policy = "server_only"; description = "Dispatch signed safety manifests and receive endpoint telemetry." },
            [PSCustomObject]@{ id = "supabase"; name = "Supabase Mirror"; enabled = $true; access = "server"; secret_policy = "service_role_never_frontend"; description = "Mirror safety and action logs for realtime analytics." },
            [PSCustomObject]@{ id = "huggingface_spaces"; name = "Hugging Face Spaces"; enabled = $true; access = "cloud"; secret_policy = "environment_variable"; description = "Optional model registry and cloud inference endpoint." },
            [PSCustomObject]@{ id = "e2b"; name = "E2B Sandbox"; enabled = $true; access = "server"; secret_policy = "environment_variable"; description = "Preflight script simulation before risky rollout." },
            [PSCustomObject]@{ id = "nullclaw"; name = "NullClaw"; enabled = $true; access = "local"; secret_policy = "local_cli"; description = "Local low-level assistant used only through explicit operator actions." },
            [PSCustomObject]@{ id = "local_model"; name = "Ollama / Local Model"; enabled = $true; access = "local"; secret_policy = "no_secret_required"; description = "Offline local AI model for interactive diagnosis." }
        )
    }

    if (-not (Test-Path $Script:EnvironmentPath)) { return (Import-NeoAiEnvironmentBundle $fallback) }
    try {
        $cfg = Get-Content -Path $Script:EnvironmentPath -Raw | ConvertFrom-Json
        foreach ($name in @($fallback.PSObject.Properties.Name)) {
            if ($cfg.PSObject.Properties.Name -notcontains $name) {
                $cfg | Add-Member -NotePropertyName $name -NotePropertyValue $fallback.$name -Force
            }
        }
        return (Import-NeoAiEnvironmentBundle $cfg)
    } catch {
        Write-Warning "AI environment config invalid. Using built-in defaults. $($_.Exception.Message)"
        return (Import-NeoAiEnvironmentBundle $fallback)
    }
}

function Get-NeoSupportedLocalActions {
    @(
        "Dashboard", "Cleaner", "Performance", "Privacy", "Network", "Security",
        "Services", "Updates", "Power", "Maintenance", "CleanAll", "ScheduleClean",
        "SmartOptimize", "DeepScan", "SystemDiagnostics", "WindowsDoctor", "WindowsErrorFix", "SystemRepair",
        "DiskStatus", "DiskScan", "DiskRepair", "DiskOptimize", "HealthRepair",
        "RestorePoint", "RollbackLast", "VoiceCommand", "CloudStatus", "AgentAudit",
        "AgentRemediate", "AgentStatus", "NeoUpdate", "AIScriptForge", "Profile"
    )
}

function Format-AiEnvironmentSummary {
    param($Environment)

    $skillLines = @($Environment.skills | ForEach-Object {
        "- $($_.name) [$($_.risk)] -> $($_.action): $($_.description)"
    }) -join "`r`n"
    $mcpLines = @($Environment.mcp_connectors | ForEach-Object {
        $state = if ($_.enabled) { "enabled" } else { "disabled" }
        "- $($_.name) ($state, $($_.access), secret: $($_.secret_policy)): $($_.description)"
    }) -join "`r`n"

@"
Environment: $($Environment.environment_name)
Operator: $($Environment.default_operator)
Safety mode: $($Environment.safety_mode)

Skills:
$skillLines

MCP / Connectors:
$mcpLines
"@
}

function Test-NeoPendingReboot {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    foreach ($path in $paths) {
        try {
            if ($path -like "*Session Manager") {
                $props = Get-ItemProperty -Path $path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
                if ($props.PendingFileRenameOperations) { return $true }
            } elseif (Test-Path $path) {
                return $true
            }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return $false
}

function Get-NeoServiceState {
    param([string]$Name)
    $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $svc) {
        return [PSCustomObject]@{ name = $Name; exists = $false; status = "Missing"; start_mode = "Missing" }
    }
    return [PSCustomObject]@{ name = $Name; exists = $true; status = $svc.State; start_mode = $svc.StartMode }
}

function Get-NeoPowerPlanName {
    try {
        $text = (& powercfg /GETACTIVESCHEME 2>$null) -join " "
        if ($text -match '\(([^\)]+)\)') { return $Matches[1] }
        if ($text) { return $text.Trim() }
    } catch { Write-Verbose $_.Exception.Message }
    return "Unknown"
}

function Get-NeoPrivacySignalCount {
    $signals = 0
    $checks = @(
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Bad = 1 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"; Name = "TailoredExperiencesWithDiagnosticDataEnabled"; Bad = 1 },
        @{ Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name = "AllowTelemetry"; BadGreaterThan = 1 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SubscribedContent-338388Enabled"; Bad = 1 },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name = "SystemPaneSuggestionsEnabled"; Bad = 1 }
    )

    foreach ($check in $checks) {
        try {
            $path = [string]$check["Path"]
            $name = [string]$check["Name"]
            $value = (Get-ItemProperty -Path $path -Name $name -ErrorAction Stop).$name
            if ($check.ContainsKey("BadGreaterThan")) {
                if ([int]$value -gt [int]$check.BadGreaterThan) { $signals++ }
            } elseif ([int]$value -eq [int]$check.Bad) {
                $signals++
            }
        } catch { Write-Verbose $_.Exception.Message }
    }
    return $signals
}

function Get-NeoBenchmarkEvidence {
    $benchmarkDir = Join-Path $Script:Root "reports\benchmarks"
    if (-not (Test-Path $benchmarkDir)) { return @() }

    $items = Get-ChildItem -Path $benchmarkDir -Filter "local_*.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 8

    $history = New-Object System.Collections.Generic.List[object]
    foreach ($item in $items) {
        try {
            $data = Get-Content -Path $item.FullName -Raw | ConvertFrom-Json
            $history.Add([PSCustomObject]@{
                action = $data.action
                status = $data.status
                risk_level = $data.risk_level
                completed_at = $data.completed_at
                health_score_delta = $data.delta.health_score_delta
                ram_free_gb_delta = $data.delta.ram_free_gb_delta
                ram_used_pct_delta = $data.delta.ram_used_pct_delta
                disk_free_gb_delta = $data.delta.disk_free_gb_delta
                stopped_auto_services_delta = $data.delta.stopped_auto_services_delta
                report = $item.FullName
            }) | Out-Null
        } catch { Write-Verbose $_.Exception.Message }
    }
    return @($history)
}

function Get-NeoSnapshot {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $net = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Address } | Select-Object -First 3
    $def = Get-MpComputerStatus -ErrorAction SilentlyContinue
    $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    $svcCount = @(Get-Service -ErrorAction SilentlyContinue).Count
    $procCount = @(Get-Process -ErrorAction SilentlyContinue).Count
    $startupCount = 0
    $pendingReboot = Test-NeoPendingReboot
    $criticalServiceNames = @("wuauserv", "bits", "cryptsvc", "mpssvc", "BFE", "WinDefend", "Winmgmt", "EventLog", "Schedule")
    $criticalServices = @($criticalServiceNames | ForEach-Object { Get-NeoServiceState $_ })
    $criticalStopped = @($criticalServices | Where-Object { $_.exists -and $_.status -ne "Running" -and $_.name -notin @("wuauserv", "bits") })
    $allCimServices = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
    $autoStopped = @($allCimServices | Where-Object { $_.StartMode -eq "Auto" -and $_.State -ne "Running" }).Count
    $networkIssueCount = 0
    $net | ForEach-Object {
        if (-not $_.IPv4DefaultGateway) { $networkIssueCount++ }
        if (-not $_.DNSServer -or -not $_.DNSServer.ServerAddresses) { $networkIssueCount++ }
    }
    $rmmSvc = Get-Service -Name "NeoOptimize RMM Agent" -ErrorAction SilentlyContinue
    $priorAiReports = 0
    if (Test-Path $Script:ReportDir) {
        $priorAiReports = @(Get-ChildItem -Path $Script:ReportDir -Filter "NeoOptimize_AI_Agent_*.json" -ErrorAction SilentlyContinue).Count
    }

    foreach ($path in @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )) {
        if (Test-Path $path) {
            $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            $startupCount += @($props.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }).Count
        }
    }

    $ramTotalGb = if ($cs.TotalPhysicalMemory) { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { 0 }
    $ramFreeGb = if ($os.FreePhysicalMemory) { [math]::Round($os.FreePhysicalMemory / 1MB, 2) } else { 0 }
    $ramUsedPct = if ($ramTotalGb -gt 0) { [math]::Round((($ramTotalGb - $ramFreeGb) / $ramTotalGb) * 100, 1) } else { 0 }
    $diskSizeGb = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { 0 }
    $diskFreeGb = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 0 }
    $diskFreePct = if ($diskSizeGb -gt 0) { [math]::Round(($diskFreeGb / $diskSizeGb) * 100, 1) } else { 0 }
    $uptimeDays = if ($os.LastBootUpTime) { [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalDays, 2) } else { 0 }

    [PSCustomObject]@{
        timestamp = (Get-Date).ToString("s")
        computer_name = $env:COMPUTERNAME
        user = $env:USERNAME
        os = $os.Caption
        os_version = $os.Version
        build = $os.BuildNumber
        architecture = $os.OSArchitecture
        manufacturer = $cs.Manufacturer
        model = $cs.Model
        bios = $bios.SMBIOSBIOSVersion
        cpu = $cpu.Name
        cores = $cpu.NumberOfCores
        threads = $cpu.NumberOfLogicalProcessors
        ram_total_gb = $ramTotalGb
        ram_free_gb = $ramFreeGb
        ram_used_pct = $ramUsedPct
        disk_c_size_gb = $diskSizeGb
        disk_c_free_gb = $diskFreeGb
        disk_c_free_pct = $diskFreePct
        uptime_days = $uptimeDays
        process_count = $procCount
        service_count = $svcCount
        startup_count = $startupCount
        firewall_disabled_profiles = @($fw | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
        defender_realtime = $def.RealTimeProtectionEnabled
        defender_signature_age_days = $def.AntivirusSignatureAge
        pending_reboot = [bool]$pendingReboot
        active_power_plan = Get-NeoPowerPlanName
        is_laptop = [bool]$battery
        on_battery = [bool]($battery -and $battery.BatteryStatus -eq 1)
        privacy_signal_count = Get-NeoPrivacySignalCount
        network_issue_count = [int]$networkIssueCount
        critical_services = @($criticalServices)
        critical_services_stopped = @($criticalStopped | ForEach-Object { $_.name })
        auto_services_stopped = [int]$autoStopped
        windows_update_service_status = (@($criticalServices | Where-Object { $_.name -eq "wuauserv" })[0]).status
        bits_service_status = (@($criticalServices | Where-Object { $_.name -eq "bits" })[0]).status
        rmm_agent_installed = [bool]$rmmSvc
        rmm_agent_status = if ($rmmSvc) { [string]$rmmSvc.Status } else { "Missing" }
        prior_ai_reports = [int]$priorAiReports
        benchmark_history = @(Get-NeoBenchmarkEvidence)
        network = @($net | ForEach-Object {
            [PSCustomObject]@{
                interface = $_.InterfaceAlias
                ipv4 = ($_.IPv4Address.IPAddress -join ",")
                gateway = ($_.IPv4DefaultGateway.NextHop -join ",")
                dns = ($_.DNSServer.ServerAddresses -join ",")
            }
        })
    }
}

function New-AgentPrompt {
    param([object]$Snapshot)

    $json = $Snapshot | ConvertTo-Json -Depth 6
    @"
You are NeoCore, the built-in NeoOptimize AI advisor. Analyze this authorized Windows endpoint snapshot.

Rules:
- Advisory only. Do not execute tools or shell commands.
- Do not request secrets, passwords, tokens, biometrics, camera capture, or microphone capture.
- Prefer safe changes with restore point first.
- Map every recommendation to an existing NeoOptimize module when possible:
  Dashboard, Cleaner, CleanAll, DeepScan, SystemDiagnostics, SystemRepair,
  SmartOptimize, ScheduleClean, DiskStatus, DiskScan, DiskRepair, DiskOptimize,
  HealthRepair, Performance, Privacy, Network, Security, Services, Updates,
  Power, Profile, AgentAudit, AgentStatus, AgentInstall, AgentRemediate,
  CloudStatus, Maintenance.
- Return concise Markdown with: Health score, top risks, recommended module order, and cautions.
- Use benchmark_history as empirical evidence. If a past action reduced health score
  or increased risk, lower confidence for repeating that action and explain why.

Snapshot JSON:
$json
"@
}

function New-InteractivePrompt {
    param(
        [object]$Snapshot,
        [string]$UserQuestion,
        $Environment
    )

    $snapshotJson = $Snapshot | ConvertTo-Json -Depth 6
    $environmentText = Format-AiEnvironmentSummary -Environment $Environment
    $actions = (Get-NeoSupportedLocalActions) -join ", "

@"
You are NEO, the Neural Execution Operator inside NeoOptimize.

Mission:
- Be active and helpful: ask one useful follow-up only when needed, otherwise make a clear recommendation.
- Map advice to existing NeoOptimize actions when possible.
- Use the local Windows snapshot, benchmark history, AI skill catalog, and MCP connector status.
- Do not request or reveal secrets, passwords, API keys, tokens, biometrics, camera, or microphone data.
- Do not claim an action has executed. Execution requires the operator to type: run <Action>.
- Keep risky actions behind restore point + explicit confirmation.

Allowed local actions:
$actions

AI environment:
$environmentText

Current Windows endpoint snapshot:
$snapshotJson

Operator question:
$UserQuestion

Return concise Markdown with:
1. Direct answer
2. Best next action
3. Optional command suggestion using: run <Action>
4. Safety cautions
"@
}

function Invoke-InteractiveAdvisor {
    param(
        $Config,
        [object]$Snapshot,
        [string]$UserQuestion
    )

    $environment = Read-AiEnvironmentConfig
    $prompt = New-InteractivePrompt -Snapshot $Snapshot -UserQuestion $UserQuestion -Environment $environment
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @($Config.provider_order)) {
        try {
            switch ($candidate) {
                "ollama" { return [PSCustomObject]@{ provider = "ollama"; text = (Invoke-OllamaAdvisor -Config $Config -Prompt $prompt); errors = @($errors) } }
                "openai_compatible" { return [PSCustomObject]@{ provider = "openai_compatible"; text = (Invoke-OpenAiCompatibleAdvisor -Config $Config -Prompt $prompt); errors = @($errors) } }
                "huggingface" { return [PSCustomObject]@{ provider = "huggingface"; text = (Invoke-HuggingFaceAdvisor -Config $Config -Prompt $prompt); errors = @($errors) } }
                "gemini" { return [PSCustomObject]@{ provider = "gemini"; text = (Invoke-GeminiAdvisor -Config $Config -Prompt $prompt); errors = @($errors) } }
                "nullclaw" { return [PSCustomObject]@{ provider = "nullclaw"; text = (Invoke-NullClawAdvisor -Config $Config -Prompt $prompt); errors = @($errors) } }
            }
        } catch {
            $errors.Add("${candidate}: $($_.Exception.Message)") | Out-Null
        }
    }

    $plan = Invoke-NeoCoreAdvisor -Config $Config -Snapshot $Snapshot
    $fallback = @"
Provider: NeoCore interactive fallback

$plan

## Operator response
NEO is running in local deterministic mode. I can still guide you interactively from snapshot data, skills, and MCP status.

Question: $UserQuestion

Best next move:
- Type `plan` to refresh the ranked AI module plan.
- Type `skills` to view available AI-powered skills.
- Type `mcp` to view connector readiness.
- Type `run <Action>` to execute one local action after confirmation.
"@
    return [PSCustomObject]@{ provider = "neocore"; text = $fallback; errors = @($errors) }
}

function Save-InteractiveTurn {
    param(
        [System.Collections.Generic.List[string]]$Transcript,
        [string]$Role,
        [string]$Text
    )

    $stamp = Get-Date -Format "HH:mm:ss"
    $Transcript.Add("## $Role $stamp`r`n`r`n$Text`r`n") | Out-Null
}

function Resolve-NeoCorePolicyPath {
    param($Config)

    $path = $Script:NeoCorePolicyPath
    if ($Config -and $Config.neocore -and $Config.neocore.policy_path) {
        $candidate = [string]$Config.neocore.policy_path
        if ([System.IO.Path]::IsPathRooted($candidate)) {
            $path = $candidate
        } else {
            $path = Join-Path $Script:Root $candidate
        }
    }
    return $path
}

function Read-NeoCorePolicy {
    param($Config)

    $path = Resolve-NeoCorePolicyPath $Config
    if (-not (Test-Path $path)) {
        throw "NeoCore policy model not found: $path"
    }
    try {
        return Get-Content -Path $path -Raw | ConvertFrom-Json
    } catch {
        throw "NeoCore policy model is invalid JSON: $($_.Exception.Message)"
    }
}

function Get-NeoCoreFeatureMap {
    param([object]$Snapshot)

    $diskPressure = if ($Snapshot.disk_c_free_pct -le 0) { 1.0 } else { [math]::Max(0, [math]::Min(1, (25 - [double]$Snapshot.disk_c_free_pct) / 25)) }
    $memoryPressure = [math]::Max(0, [math]::Min(1, ([double]$Snapshot.ram_used_pct - 55) / 45))
    $startupLoad = [math]::Max(0, [math]::Min(1, [double]$Snapshot.startup_count / 45))
    $processLoad = [math]::Max(0, [math]::Min(1, ([double]$Snapshot.process_count - 120) / 220))
    $uptimePressure = [math]::Max(0, [math]::Min(1, [double]$Snapshot.uptime_days / 21))
    $firewallRisk = if (@($Snapshot.firewall_disabled_profiles).Count -gt 0) { 1.0 } else { 0.0 }
    $defenderRisk = if ($Snapshot.defender_realtime -eq $false) { 1.0 } else { 0.0 }
    $signatureAge = 0
    try { $signatureAge = [double]$Snapshot.defender_signature_age_days } catch { Write-Verbose $_.Exception.Message }
    $signatureRisk = [math]::Max(0, [math]::Min(1, $signatureAge / 21))
    $updateServiceRisk = if ($Snapshot.windows_update_service_status -and $Snapshot.windows_update_service_status -ne "Running") { 0.65 } else { 0.0 }
    $pendingRebootRisk = if ($Snapshot.pending_reboot) { 0.75 } else { 0.0 }
    $updateRisk = [math]::Max($signatureRisk, [math]::Max($updateServiceRisk, $pendingRebootRisk))
    $criticalStoppedCount = @($Snapshot.critical_services_stopped).Count
    $serviceRisk = [math]::Max(0, [math]::Min(1, ([double]$Snapshot.auto_services_stopped / 18) + ([double]$criticalStoppedCount / 6)))
    $networkRisk = [math]::Max(0, [math]::Min(1, ([double]$Snapshot.network_issue_count / 3) + ($uptimePressure * 0.12)))
    $powerPlan = [string]$Snapshot.active_power_plan
    $powerRisk = 0.0
    if ($powerPlan -match "power saver|balanced|penghemat") { $powerRisk = [math]::Max($powerRisk, 0.45) }
    if ($Snapshot.on_battery) { $powerRisk = [math]::Max($powerRisk, 0.35) }
    $powerRisk = [math]::Max($powerRisk, [math]::Min(1, ($memoryPressure * 0.25) + ($processLoad * 0.2)))
    $privacyRisk = [math]::Max(0, [math]::Min(1, ([double]$Snapshot.privacy_signal_count / 5) + ($startupLoad * 0.15) + ($processLoad * 0.10)))
    $repairRisk = [math]::Max($pendingRebootRisk * 0.7, [math]::Max($updateRisk * 0.55, [math]::Max($serviceRisk * 0.45, $diskPressure * 0.3)))
    $inventoryGap = if (-not $Snapshot.rmm_agent_installed) {
        1.0
    } elseif ($Snapshot.rmm_agent_status -ne "Running") {
        0.65
    } elseif ([int]$Snapshot.prior_ai_reports -le 0) {
        0.35
    } else {
        0.15
    }
    $baselineNeed = if ([int]$Snapshot.prior_ai_reports -le 0) { 0.70 } else { 0.25 }

    return [ordered]@{
        disk_pressure = [math]::Round($diskPressure, 4)
        memory_pressure = [math]::Round($memoryPressure, 4)
        startup_load = [math]::Round($startupLoad, 4)
        process_load = [math]::Round($processLoad, 4)
        uptime_pressure = [math]::Round($uptimePressure, 4)
        firewall_risk = [math]::Round($firewallRisk, 4)
        defender_risk = [math]::Round($defenderRisk, 4)
        update_risk = [math]::Round($updateRisk, 4)
        service_risk = [math]::Round($serviceRisk, 4)
        network_risk = [math]::Round($networkRisk, 4)
        power_risk = [math]::Round($powerRisk, 4)
        privacy_risk = [math]::Round($privacyRisk, 4)
        repair_risk = [math]::Round($repairRisk, 4)
        inventory_gap = [math]::Round($inventoryGap, 4)
        baseline_need = [math]::Round($baselineNeed, 4)
    }
}

function Get-PolicyNumber {
    param($Value, [double]$Default = 0)
    try {
        if ($null -eq $Value) { return $Default }
        return [double]$Value
    } catch {
        return $Default
    }
}

function Invoke-NeoCoreAdvisor {
    param($Config, [object]$Snapshot)

    if ($Config.neocore -and $Config.neocore.enabled -eq $false) { throw "NeoCore provider disabled" }
    $policy = Read-NeoCorePolicy $Config
    $features = Get-NeoCoreFeatureMap -Snapshot $Snapshot
    $score = 100.0
    $evidence = New-Object System.Collections.Generic.List[string]
    $featureNames = @($policy.weights.PSObject.Properties.Name)

    foreach ($name in $featureNames) {
        $weight = Get-PolicyNumber $policy.weights.$name 0
        $value = if ($features.Contains($name)) { [double]$features[$name] } else { 0.0 }
        $score -= ($value * $weight)
    }
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    $score = [math]::Round($score)

    $recommendations = New-Object System.Collections.Generic.List[object]
    foreach ($module in $policy.modules.PSObject.Properties.Name) {
        $entry = $policy.modules.$module
        if ($entry.enabled -eq $false) { continue }

        $moduleScore = Get-PolicyNumber $entry.bias 0
        foreach ($featureName in $featureNames) {
            $featureWeight = 0.0
            if ($entry.features -and $entry.features.PSObject.Properties.Name -contains $featureName) {
                $featureWeight = Get-PolicyNumber $entry.features.$featureName 0
            }
            $featureValue = if ($features.Contains($featureName)) { [double]$features[$featureName] } else { 0.0 }
            $moduleScore += ($featureValue * $featureWeight)
        }

        $confidence = 1 - [math]::Exp(-1.2 * [math]::Max(0, $moduleScore))
        if ($confidence -gt 0.99) { $confidence = 0.99 }
        $recommendations.Add([PSCustomObject]@{
            module = $module
            display = if ($entry.display) { [string]$entry.display } else { $module }
            confidence = [math]::Round($confidence, 4)
            confidence_pct = [math]::Round($confidence * 100)
            raw_score = [math]::Round($moduleScore, 4)
            risk = if ($entry.risk) { [string]$entry.risk } else { "medium" }
            automation = if ($entry.automation) { [string]$entry.automation } else { "confirm" }
            local_action = if ($entry.local_action) { [string]$entry.local_action } else { $module }
            rmm_command = if ($entry.rmm_command) { [string]$entry.rmm_command } else { "" }
            reason = if ($entry.reason) { [string]$entry.reason } else { "Ranked by NeoCore telemetry policy." }
        }) | Out-Null
    }

    $minConfidence = 0.25
    if ($policy.settings.min_confidence) { $minConfidence = [double]$policy.settings.min_confidence }
    if ($Config.neocore.min_confidence) { $minConfidence = [double]$Config.neocore.min_confidence }

    $limit = 8
    if ($policy.settings.recommendation_limit) { $limit = [int]$policy.settings.recommendation_limit }

    $rankedModules = @(
        $recommendations |
            Sort-Object confidence, raw_score -Descending |
            Where-Object { $_.confidence -ge $minConfidence } |
            Select-Object -First $limit
    )
    if ($rankedModules.Count -eq 0) {
        $rankedModules = @($recommendations | Where-Object { $_.module -eq "AgentAudit" } | Select-Object -First 1)
    }

    foreach ($always in @($policy.settings.always_include)) {
        if ($always -and @($rankedModules.module) -notcontains $always) {
            $candidate = $recommendations | Where-Object { $_.module -eq $always } | Select-Object -First 1
            if ($candidate) { $rankedModules += $candidate }
        }
    }

    if ([double]$features.disk_pressure -gt 0.60) {
        $evidence.Add("Disk pressure detected: C: free space $($Snapshot.disk_c_free_pct)% ($($Snapshot.disk_c_free_gb) GB).")
    }
    if ([double]$features.memory_pressure -gt 0.55) {
        $evidence.Add("Memory pressure detected: $($Snapshot.ram_used_pct)% used, $($Snapshot.ram_free_gb) GB free.")
    }
    if ([double]$features.startup_load -gt 0.45 -or [double]$features.process_load -gt 0.45) {
        $evidence.Add("Background load is elevated: $($Snapshot.process_count) processes, $($Snapshot.startup_count) startup entries.")
    }
    if ([double]$features.uptime_pressure -gt 0.60) {
        $evidence.Add("Long uptime detected: $($Snapshot.uptime_days) days.")
    }
    if ([double]$features.firewall_risk -gt 0) {
        $evidence.Add("Firewall disabled profiles: $($Snapshot.firewall_disabled_profiles -join ', ').")
    }
    if ([double]$features.defender_risk -gt 0) {
        $evidence.Add("Microsoft Defender realtime protection appears disabled.")
    }
    if ([double]$features.update_risk -gt 0.55) {
        $evidence.Add("Update or reboot risk detected: pending reboot=$($Snapshot.pending_reboot), Defender signature age=$($Snapshot.defender_signature_age_days), Windows Update service=$($Snapshot.windows_update_service_status).")
    }
    if ([double]$features.service_risk -gt 0.45) {
        $evidence.Add("Service posture needs attention: stopped auto services=$($Snapshot.auto_services_stopped), stopped critical=$(@($Snapshot.critical_services_stopped) -join ', ').")
    }
    if ([double]$features.network_risk -gt 0.45) {
        $evidence.Add("Network baseline has gaps: issue count=$($Snapshot.network_issue_count).")
    }
    if ([double]$features.inventory_gap -gt 0.60) {
        $evidence.Add("RMM/AI inventory gap detected: RMM agent status=$($Snapshot.rmm_agent_status), prior AI reports=$($Snapshot.prior_ai_reports).")
    }
    $recentBenchmarks = @($Snapshot.benchmark_history)
    if ($recentBenchmarks.Count -gt 0) {
        $latest = $recentBenchmarks[0]
        if ($latest.health_score_delta -lt 0) {
            $evidence.Add("Latest benchmark warning: $($latest.action) reduced local health score by $([math]::Abs([int]$latest.health_score_delta)) points.")
        } elseif ($latest.health_score_delta -gt 0) {
            $evidence.Add("Latest benchmark improvement: $($latest.action) improved local health score by $($latest.health_score_delta) points.")
        } else {
            $evidence.Add("Latest benchmark neutral: $($latest.action) completed without health score delta.")
        }
    }
    if ($evidence.Count -eq 0) {
        $evidence.Add("No critical issue detected from the local snapshot.")
    }

    $i = 0
    $moduleLines = @($rankedModules | ForEach-Object {
        $i++
        $rmm = if ($_.rmm_command) { $_.rmm_command } else { "local-only" }
        "$i. $($_.display) - confidence $($_.confidence_pct)% - risk $($_.risk) - action $($_.local_action) - RMM $rmm`r`n   Reason: $($_.reason)"
    }) -join "`r`n"
    $evidenceLines = @($evidence | ForEach-Object { "- $_" }) -join "`r`n"
    $featureLines = @($features.GetEnumerator() | ForEach-Object { "- $($_.Key): $($_.Value)" }) -join "`r`n"
    $modelVersion = if ($policy.model.version) { [string]$policy.model.version } else { "1.0" }
    $trainedAt = if ($policy.model.trained_at) { [string]$policy.model.trained_at } else { "unknown" }
    $Script:LastNeoCorePlan = [PSCustomObject]@{
        model = if ($policy.model.name) { [string]$policy.model.name } else { "NeoCore.Policy" }
        model_version = $modelVersion
        health_score = $score
        features = [PSCustomObject]$features
        evidence = @($evidence)
        recommendations = @($rankedModules)
        safety = $policy.safety
    }

@"
Provider: NeoCore local model
Model: NeoCore.Policy $modelVersion
Trained: $trainedAt

# NeoOptimize AI Advisor

Health score: $score/100

## Top evidence
$evidenceLines

## AI module plan
$moduleLines

## Model features
$featureLines

## Cautions
- Create a restore point before remediation.
- Review latest benchmark deltas before repeating aggressive modules.
- Medium/high risk modules require human confirmation.
- Review Security, Services, Repair, and Disk Repair changes on production endpoints.
- RMM dispatch is limited to mapped safe command types; local-only actions stay local.
- NeoCore does not collect secrets, camera, microphone, or biometric data.
"@
}

function Invoke-ProcessCapture {
    param(
        [string]$FileName,
        [string]$Arguments,
        [int]$TimeoutSeconds = 60
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to start $FileName" }

    if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch { Write-Verbose $_.Exception.Message }
        throw "$FileName timed out after $TimeoutSeconds seconds"
    }

    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    if ($proc.ExitCode -ne 0 -and $stderr) {
        throw $stderr.Trim()
    }
    return $stdout.Trim()
}

function Quote-NativeArgument {
    param([string]$Value)
    $escaped = $Value -replace '"', '\"'
    return '"' + $escaped + '"'
}

function Resolve-NeoToolCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($Command)
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add($expanded) | Out-Null
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $candidates.Add((Join-Path $Script:Root $expanded)) | Out-Null
        $candidates.Add((Join-Path $Script:Root ($expanded -replace '/', '\'))) | Out-Null
    }

    foreach ($candidate in $candidates) {
        try {
            $path = [System.IO.Path]::GetFullPath($candidate)
            if (Test-Path $path) { return [PSCustomObject]@{ Source = $path; Kind = "path" } }
        } catch { Write-Verbose $_.Exception.Message }
    }

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($cmd) { return [PSCustomObject]@{ Source = $cmd.Source; Kind = "command" } }
    return $null
}

function Get-NeoPowerShellExecutable {
    try {
        $current = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($current -and (Test-Path $current)) { return $current }
    } catch { Write-Verbose $_.Exception.Message }
    foreach ($candidate in @("pwsh", "powershell.exe", "powershell")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "PowerShell executable not found for local tool bridge."
}

function Invoke-NeoToolCapture {
    param(
        [string]$FileName,
        [string]$Arguments,
        [int]$TimeoutSeconds = 60
    )

    if ($FileName -match '\.ps1$') {
        $psExe = Get-NeoPowerShellExecutable
        $toolArgs = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File $(Quote-NativeArgument $FileName)"
        if (-not [string]::IsNullOrWhiteSpace($Arguments)) { $toolArgs = "$toolArgs $Arguments" }
        return Invoke-ProcessCapture -FileName $psExe -Arguments $toolArgs -TimeoutSeconds $TimeoutSeconds
    }
    return Invoke-ProcessCapture -FileName $FileName -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
}

function Invoke-NullClawAdvisor {
    param($Config, [string]$Prompt)

    if (-not $Config.nullclaw.enabled) { throw "NullClaw provider disabled" }
    $cmd = Resolve-NeoToolCommand ([string]$Config.nullclaw.command)
    if (-not $cmd) { throw "NullClaw CLI not found in PATH" }

    $maxChars = [int]($Config.nullclaw.max_prompt_chars | ForEach-Object { if ($_ -gt 0) { $_ } else { 6000 } })
    if ($Prompt.Length -gt $maxChars) {
        $Prompt = $Prompt.Substring(0, $maxChars)
    }

    $prefix = @($Config.nullclaw.arguments) -join " "
    $nativeArguments = "$prefix $(Quote-NativeArgument $Prompt)"
    $timeout = [int]($Config.nullclaw.timeout_seconds | ForEach-Object { if ($_ -gt 0) { $_ } else { 75 } })
    $output = Invoke-NeoToolCapture -FileName $cmd.Source -Arguments $nativeArguments -TimeoutSeconds $timeout
    if (-not $output) { throw "NullClaw returned empty output" }
    return $output
}

function Resolve-OllamaModel {
    param($Config)

    try {
        $tags = Invoke-RestMethod -Uri $Config.ollama.tags_endpoint -Method Get -TimeoutSec 4
        $installed = @($tags.models | ForEach-Object { $_.name })
        foreach ($preferred in @($Config.ollama.preferred_models)) {
            if ($installed -contains $preferred) { return $preferred }
        }
        if ($installed.Count -gt 0) { return $installed[0] }
    } catch { Write-Verbose $_.Exception.Message }
    return $null
}

function Invoke-OllamaAdvisor {
    param($Config, [string]$Prompt)

    if (-not $Config.ollama.enabled) { throw "Ollama provider disabled" }
    $model = Resolve-OllamaModel $Config
    if (-not $model) { throw "Ollama is not running or no local model is installed" }

    $body = @{
        model = $model
        prompt = $Prompt
        stream = $false
        options = @{
            temperature = [double]$Config.ollama.temperature
            num_predict = [int]$Config.ollama.num_predict
        }
    } | ConvertTo-Json -Depth 8

    $timeout = [int]($Config.ollama.timeout_seconds | ForEach-Object { if ($_ -gt 0) { $_ } else { 30 } })
    $response = Invoke-RestMethod -Uri $Config.ollama.endpoint -Method Post -ContentType "application/json" -Body $body -TimeoutSec $timeout
    if (-not $response.response) { throw "Ollama returned empty output" }
    return "Provider: Ollama ($model)`r`n`r`n$($response.response)"
}

function Invoke-OpenAiCompatibleAdvisor {
    param($Config, [string]$Prompt)

    if (-not (Get-AgentConfigBool $Config.openai_compatible "enabled" $false)) { throw "OpenAI-compatible provider disabled" }
    $endpoint = Get-AgentConfigString $Config.openai_compatible "endpoint" "https://api.openai.com/v1/chat/completions"
    $model = Get-AgentConfigString $Config.openai_compatible "model" "gpt-4.1-mini"
    if ([string]::IsNullOrWhiteSpace($endpoint) -or [string]::IsNullOrWhiteSpace($model)) {
        throw "OpenAI-compatible endpoint or model is empty"
    }

    $apiKey = Get-AgentSecret $Config.openai_compatible "api_key" "NEOOPTIMIZE_OPENAI_API_KEY"
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $headers["Authorization"] = "Bearer $apiKey"
    }

    $system = "You are NeoOptimize AI Doctor. Produce concise endpoint health analysis. Advisory only. Do not request or expose secrets. Map actions to NeoOptimize/RMM modules when possible."
    $body = @{
        model = $model
        messages = @(
            @{ role = "system"; content = $system },
            @{ role = "user"; content = $Prompt }
        )
        temperature = (Get-AgentConfigDouble $Config.openai_compatible "temperature" 0.2)
        max_tokens = (Get-AgentConfigInt $Config.openai_compatible "max_tokens" 1200)
    } | ConvertTo-Json -Depth 8

    $timeout = Get-AgentConfigInt $Config.openai_compatible "timeout_seconds" 60
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec $timeout
    $text = ""
    try { $text = [string]$response.choices[0].message.content } catch { Write-Verbose $_.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($text)) {
        try { $text = [string]$response.choices[0].text } catch { Write-Verbose $_.Exception.Message }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw "OpenAI-compatible provider returned empty output" }
    return "Provider: OpenAI-compatible ($model)`r`n`r`n$text"
}

function Invoke-HuggingFaceAdvisor {
    param($Config, [string]$Prompt)

    if (-not (Get-AgentConfigBool $Config.huggingface "enabled" $false)) { throw "Hugging Face provider disabled" }
    $modelOrEndpoint = Get-AgentConfigString $Config.huggingface "model" ""
    if ([string]::IsNullOrWhiteSpace($modelOrEndpoint)) { throw "Hugging Face model or endpoint is empty" }

    $endpoint = $modelOrEndpoint
    if ($endpoint -notmatch "^https?://") {
        $endpoint = "https://api-inference.huggingface.co/models/$modelOrEndpoint"
    }

    $apiKey = Get-AgentSecret $Config.huggingface "api_key" "NEOOPTIMIZE_HF_TOKEN"
    $headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($apiKey)) {
        $headers["Authorization"] = "Bearer $apiKey"
    }

    $body = @{
        inputs = $Prompt
        parameters = @{
            max_new_tokens = (Get-AgentConfigInt $Config.huggingface "max_new_tokens" 900)
            temperature = (Get-AgentConfigDouble $Config.huggingface "temperature" 0.2)
            return_full_text = $false
        }
        options = @{
            wait_for_model = $true
        }
    } | ConvertTo-Json -Depth 8

    $timeout = Get-AgentConfigInt $Config.huggingface "timeout_seconds" 60
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec $timeout

    $text = ""
    if ($response -is [string]) {
        $text = $response
    } elseif ($response -is [array] -and $response.Count -gt 0) {
        try { $text = [string]$response[0].generated_text } catch { Write-Verbose $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($text)) {
            try { $text = [string]$response[0].summary_text } catch { Write-Verbose $_.Exception.Message }
        }
    } else {
        try { $text = [string]$response.generated_text } catch { Write-Verbose $_.Exception.Message }
        if ([string]::IsNullOrWhiteSpace($text)) {
            try { $text = [string]$response.choices[0].message.content } catch { Write-Verbose $_.Exception.Message }
        }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Hugging Face provider returned empty output" }
    return "Provider: Hugging Face ($modelOrEndpoint)`r`n`r`n$text"
}

function Invoke-GeminiAdvisor {
    param($Config, [string]$Prompt)

    if (-not (Get-AgentConfigBool $Config.gemini "enabled" $false)) { throw "Gemini provider disabled" }
    $apiKey = Get-AgentSecret $Config.gemini "api_key" "NEOOPTIMIZE_GEMINI_API_KEY"
    if ([string]::IsNullOrWhiteSpace($apiKey)) { throw "Gemini API key is empty" }
    $model = Get-AgentConfigString $Config.gemini "model" "gemini-1.5-flash"
    $modelName = $model -replace '^models/', ''
    $escapedModel = [System.Uri]::EscapeDataString($modelName)
    $endpoint = "https://generativelanguage.googleapis.com/v1beta/models/${escapedModel}:generateContent?key=$apiKey"

    $system = "You are NeoOptimize AI Doctor. Advisory only. Do not request secrets. Return Markdown with health score, risks, module order, and cautions."
    $body = @{
        contents = @(
            @{
                role = "user"
                parts = @(@{ text = "$system`r`n`r`n$Prompt" })
            }
        )
        generationConfig = @{
            temperature = (Get-AgentConfigDouble $Config.gemini "temperature" 0.2)
            maxOutputTokens = (Get-AgentConfigInt $Config.gemini "max_output_tokens" 1200)
        }
    } | ConvertTo-Json -Depth 8

    $timeout = Get-AgentConfigInt $Config.gemini "timeout_seconds" 60
    $response = Invoke-RestMethod -Uri $endpoint -Method Post -ContentType "application/json" -Body $body -TimeoutSec $timeout
    $text = ""
    try { $text = [string]$response.candidates[0].content.parts[0].text } catch { Write-Verbose $_.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Gemini provider returned empty output" }
    return "Provider: Gemini ($model)`r`n`r`n$text"
}

function Invoke-RuleBasedAdvisor {
    param([object]$Snapshot)

    $score = 100
    $risks = New-Object System.Collections.Generic.List[string]
    $order = New-Object System.Collections.Generic.List[string]

    if ($Snapshot.disk_c_free_pct -lt 10) {
        $score -= 25
        $risks.Add("Critical disk pressure: C: free space is $($Snapshot.disk_c_free_pct)% ($($Snapshot.disk_c_free_gb) GB).")
        $order.Add("Cleaner")
    } elseif ($Snapshot.disk_c_free_pct -lt 18) {
        $score -= 12
        $risks.Add("Low disk headroom: C: free space is $($Snapshot.disk_c_free_pct)%.")
        $order.Add("Cleaner")
    }

    if ($Snapshot.ram_used_pct -gt 90) {
        $score -= 18
        $risks.Add("Memory pressure is high at $($Snapshot.ram_used_pct)% used.")
        $order.Add("Performance")
    } elseif ($Snapshot.ram_used_pct -gt 80) {
        $score -= 8
        $risks.Add("Memory usage is elevated at $($Snapshot.ram_used_pct)% used.")
        $order.Add("Performance")
    }

    if ($Snapshot.process_count -gt 250 -or $Snapshot.startup_count -gt 35) {
        $score -= 8
        $risks.Add("Background load is high: $($Snapshot.process_count) processes, $($Snapshot.startup_count) startup entries.")
        $order.Add("Services")
    }

    if ($Snapshot.uptime_days -gt 14) {
        $score -= 6
        $risks.Add("Long uptime: $($Snapshot.uptime_days) days. Pending updates or driver state may need reboot.")
        $order.Add("Updates")
    }

    if (@($Snapshot.firewall_disabled_profiles).Count -gt 0) {
        $score -= 15
        $risks.Add("Firewall disabled profiles: $($Snapshot.firewall_disabled_profiles -join ', ').")
        $order.Add("Security")
    }

    if ($Snapshot.defender_realtime -eq $false) {
        $score -= 20
        $risks.Add("Microsoft Defender realtime protection appears disabled.")
        $order.Add("Security")
    }

    $benchmarks = @($Snapshot.benchmark_history)
    if ($benchmarks.Count -gt 0) {
        $latest = $benchmarks[0]
        if ($latest.health_score_delta -lt 0) {
            $score -= 5
            $risks.Add("Latest optimization benchmark regressed health score: $($latest.action) delta $($latest.health_score_delta). Review rollback report before repeating it.")
        } elseif ($latest.health_score_delta -gt 0) {
            $risks.Add("Latest optimization benchmark improved health score: $($latest.action) delta +$($latest.health_score_delta).")
        }
    }

    if ($score -lt 0) { $score = 0 }
    if ($risks.Count -eq 0) { $risks.Add("No critical issue detected from the local snapshot.") }
    $order.Add("AgentAudit")
    $moduleOrder = @($order | Select-Object -Unique)

    @"
Provider: NeoOptimize safety rule engine

# NeoOptimize AI Advisor

Health score: $score/100

## Top risks
$(@($risks | ForEach-Object { "- $_" }) -join "`r`n")

## Recommended module order
$(@($moduleOrder | ForEach-Object { "- $_" }) -join "`r`n")

## Cautions
- Create a restore point before remediation.
- Review Security and Services changes on production endpoints.
- This advisor does not collect secrets, camera, microphone, or biometric data.
"@
}

function Get-NeoScriptForgeOutputDir {
    param($Config)

    $relative = Get-AgentConfigString $Config.script_forge "output_dir" "reports\ai\scripts"
    if ([System.IO.Path]::IsPathRooted($relative)) { return $relative }
    return Join-Path $Script:Root $relative
}

function Normalize-NeoScriptShell {
    param([string]$Shell, $Config)

    if ([string]::IsNullOrWhiteSpace($Shell)) {
        $Shell = Get-AgentConfigString $Config.script_forge "default_shell" "powershell"
    }
    $normalized = $Shell.Trim().ToLowerInvariant()
    if ($normalized -in @("cmd", "bat", "batch")) { return "cmd" }
    return "powershell"
}

function New-NeoPowerShellMaintenanceScript {
    param([string]$Goal, [object]$Snapshot)

    $safeGoal = $Goal -replace '\r|\n', ' '
    $generated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = @"
# NeoOptimize NEO Script Forge
# Goal: $safeGoal
# Generated: $generated
# Mode: read-only audit by default. Use -Apply only for explicitly safe maintenance.
# Safety: no secrets, no credential dumping, no destructive registry edits.

"@
    $body = @'
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

$ReportRoot = Join-Path $env:ProgramData "NeoOptimize\Reports"
New-Item -Path $ReportRoot -ItemType Directory -Force | Out-Null
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportPath = Join-Path $ReportRoot "neo_script_forge_audit_$Stamp.json"

function Get-SafeServiceState {
    param([string[]]$Names)
    foreach ($Name in $Names) {
        $svc = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        if ($svc) {
            [PSCustomObject]@{ name = $svc.Name; state = $svc.State; start_mode = $svc.StartMode; path = $svc.PathName }
        } else {
            [PSCustomObject]@{ name = $Name; state = "Missing"; start_mode = "Missing"; path = "" }
        }
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$defender = Get-MpComputerStatus
$firewall = Get-NetFirewallProfile
$events = Get-WinEvent -FilterHashtable @{ LogName = "System"; Level = 1,2; StartTime = (Get-Date).AddDays(-3) } -MaxEvents 25
$topProcesses = Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 Name,Id,CPU,WorkingSet64,Handles
$services = Get-SafeServiceState -Names @("WinDefend", "MpsSvc", "wuauserv", "bits", "cryptsvc", "Winmgmt", "EventLog", "Schedule")

$report = [ordered]@{
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    computer = $env:COMPUTERNAME
    mode = if ($Apply) { "apply_safe_maintenance" } else { "dry_run_audit" }
    os = [ordered]@{
        caption = $os.Caption
        version = $os.Version
        build = $os.BuildNumber
        architecture = $os.OSArchitecture
        last_boot = $os.LastBootUpTime
    }
    hardware = [ordered]@{
        manufacturer = $cs.Manufacturer
        model = $cs.Model
        cpu = $cpu.Name
        ram_gb = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
    }
    disk = [ordered]@{
        c_size_gb = [math]::Round($disk.Size / 1GB, 2)
        c_free_gb = [math]::Round($disk.FreeSpace / 1GB, 2)
        c_free_percent = if ($disk.Size) { [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1) } else { 0 }
    }
    security = [ordered]@{
        defender_realtime = $defender.RealTimeProtectionEnabled
        defender_signature_age_days = $defender.AntivirusSignatureAge
        firewall_disabled_profiles = @($firewall | Where-Object { -not $_.Enabled } | ForEach-Object { $_.Name })
    }
    services = @($services)
    top_processes = @($topProcesses)
    recent_critical_events = @($events | Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message)
    safe_apply_actions = @()
}

if ($Apply) {
    Clear-DnsClientCache
    $report.safe_apply_actions += "Clear-DnsClientCache"
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding UTF8
Write-Host "NEO Script Forge report: $ReportPath"
if (-not $Apply) {
    Write-Host "Dry-run audit complete. Re-run with -Apply only if the operator approves safe maintenance."
}
'@
    return $header + $body
}

function New-NeoCmdMaintenanceScript {
    param([string]$Goal)

    $safeGoal = $Goal -replace '\r|\n', ' '
    return @"
@echo off
setlocal enabledelayedexpansion
REM NeoOptimize NEO Script Forge
REM Goal: $safeGoal
REM Mode: read-only audit. This CMD script does not modify Windows.

set REPORT_DIR=%ProgramData%\NeoOptimize\Reports
if not exist "%REPORT_DIR%" mkdir "%REPORT_DIR%"
set REPORT=%REPORT_DIR%\neo_script_forge_cmd_audit_%DATE:/=-%_%TIME::=-%.txt

echo NeoOptimize NEO Script Forge Audit > "%REPORT%"
echo Computer: %COMPUTERNAME% >> "%REPORT%"
echo Generated: %DATE% %TIME% >> "%REPORT%"
echo. >> "%REPORT%"

echo === SYSTEMINFO === >> "%REPORT%"
systeminfo >> "%REPORT%" 2>&1
echo. >> "%REPORT%"

echo === IP CONFIGURATION === >> "%REPORT%"
ipconfig /all >> "%REPORT%" 2>&1
echo. >> "%REPORT%"

echo === IMPORTANT SERVICES === >> "%REPORT%"
sc query WinDefend >> "%REPORT%" 2>&1
sc query MpsSvc >> "%REPORT%" 2>&1
sc query wuauserv >> "%REPORT%" 2>&1
sc query bits >> "%REPORT%" 2>&1
sc query cryptsvc >> "%REPORT%" 2>&1
echo. >> "%REPORT%"

echo === RECENT SYSTEM ERRORS === >> "%REPORT%"
wevtutil qe System /c:25 /rd:true /f:text /q:"*[System[(Level=1 or Level=2)]]" >> "%REPORT%" 2>&1
echo. >> "%REPORT%"

echo Report: "%REPORT%"
endlocal
"@
}

function Invoke-NeoScriptForge {
    param(
        [string]$Goal,
        [string]$Shell = ""
    )

    $config = Read-AgentConfig
    if (-not (Get-AgentConfigBool $config.script_forge "enabled" $true)) {
        throw "NEO Script Forge is disabled in config."
    }
    if ([string]::IsNullOrWhiteSpace($Goal)) {
        $Goal = "audit system windows and prepare safe maintenance plan"
    }
    $maxGoalChars = Get-AgentConfigInt $config.script_forge "max_goal_chars" 500
    if ($maxGoalChars -le 0) { $maxGoalChars = 500 }
    if ($Goal.Length -gt $maxGoalChars) { $Goal = $Goal.Substring(0, $maxGoalChars) }

    $shellName = Normalize-NeoScriptShell -Shell $Shell -Config $config
    $snapshot = Get-NeoSnapshot
    $outputDir = Get-NeoScriptForgeOutputDir -Config $config
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeName = (($Goal -replace '[^A-Za-z0-9]+', '_').Trim('_'))
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "maintenance" }
    if ($safeName.Length -gt 48) { $safeName = $safeName.Substring(0, 48) }
    $extension = if ($shellName -eq "cmd") { "cmd" } else { "ps1" }
    $scriptPath = Join-Path $outputDir "NEO_${safeName}_$stamp.$extension"

    $script = if ($shellName -eq "cmd") {
        New-NeoCmdMaintenanceScript -Goal $Goal
    } else {
        New-NeoPowerShellMaintenanceScript -Goal $Goal -Snapshot $snapshot
    }
    Set-Content -Path $scriptPath -Value $script -Encoding UTF8
    $hash = (Get-FileHash -Path $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $metadata = [PSCustomObject]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        goal = $Goal
        shell = $shellName
        script_path = $scriptPath
        sha256 = $hash
        risk = "read_only_default"
        requires_confirmation = $true
        apply_mode = if ($shellName -eq "powershell") { "Use -Apply for safe maintenance only." } else { "CMD template is read-only." }
        recommended_rmm_command = "SYSTEM_DIAGNOSTICS"
        endpoint = $snapshot.computer_name
    }
    $metadataPath = [System.IO.Path]::ChangeExtension($scriptPath, ".json")
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -Path $metadataPath -Encoding UTF8

    Send-NeoAiTelemetryToRmm `
        -Config $config `
        -Snapshot $snapshot `
        -Provider "neo_script_forge" `
        -Analysis "Generated $shellName script for: $Goal" `
        -ReportPath $scriptPath `
        -JsonPath $metadataPath `
        -TelemetryEvent "script_forge" `
        -ScriptForge $metadata | Out-Null

    Write-Host ""
    Write-Host "NEO Script Forge"
    Write-Host "================"
    Write-Host "Script : $scriptPath"
    Write-Host "SHA256 : $hash"
    Write-Host "Meta   : $metadataPath"
    Write-Host "Safety : read-only by default; operator approval required before Apply mode."
    Write-Host ""

    if (-not $NoOpen) {
        Start-Process notepad.exe -ArgumentList "`"$scriptPath`""
    }
}

function Join-NativeArguments {
    param([object[]]$Arguments)
    return (@($Arguments | ForEach-Object { Quote-NativeArgument ([string]$_) }) -join " ")
}

function Test-NullClawRuntime {
    param($Config)

    $cmdName = if ($Config.nullclaw.command) { [string]$Config.nullclaw.command } else { "nullclaw" }
    $cmd = Resolve-NeoToolCommand $cmdName
    if (-not $cmd) {
        return [PSCustomObject]@{
            connected = $false
            cli = "not found"
            status = "not connected: CLI not found in PATH"
            doctor = "not run"
            source = ""
        }
    }

    $statusText = "not run"
    $doctorText = "not run"
    try {
        $statusArgs = if ($Config.nullclaw.status_arguments) { Join-NativeArguments @($Config.nullclaw.status_arguments) } else { "status" }
        $statusText = Invoke-NeoToolCapture -FileName $cmd.Source -Arguments $statusArgs -TimeoutSeconds 15
        if (-not $statusText) { $statusText = "empty status output" }
    } catch {
        $statusText = "status failed: $($_.Exception.Message)"
    }

    try {
        $doctorArgs = if ($Config.nullclaw.doctor_arguments) { Join-NativeArguments @($Config.nullclaw.doctor_arguments) } else { "doctor" }
        $doctorText = Invoke-NeoToolCapture -FileName $cmd.Source -Arguments $doctorArgs -TimeoutSeconds 20
        if (-not $doctorText) { $doctorText = "empty doctor output" }
    } catch {
        $doctorText = "doctor failed: $($_.Exception.Message)"
    }

    $healthy = ($statusText -notmatch "failed|error|No config|not found" -and $doctorText -notmatch "failed|error|No config|not found")
    return [PSCustomObject]@{
        connected = [bool]$healthy
        cli = "found"
        status = $statusText
        doctor = $doctorText
        source = $cmd.Source
    }
}

function Open-NullClawDocs {
    $config = Read-AgentConfig
    $url = if ($config.nullclaw.docs_url) { [string]$config.nullclaw.docs_url } else { "https://nullclaw.io/nullclaw/docs/getting-started" }
    Start-Process $url
    Write-Host ""
    Write-Host "NullClaw documentation opened in browser."
    Write-Host "After installing NullClaw, run: nullclaw onboard --interactive"
    Write-Host "Then click AI Providers again."
    Write-Host ""
}

function Show-AiEnvironment {
    $environment = Read-AiEnvironmentConfig
    Write-Host ""
    Write-Host "NeoOptimize AI-Empowered Environment"
    Write-Host "===================================="
    Write-Host (Format-AiEnvironmentSummary -Environment $environment)
    Write-Host ""
}

function Show-Providers {
    $config = Read-AgentConfig
    $environment = Read-AiEnvironmentConfig
    Write-Host ""
    Write-Host "NeoOptimize NeoCore AI Providers"
    Write-Host "================================"
    Write-Host "Environment    : $($environment.environment_name) / $($environment.default_operator)"
    Write-Host "Interactive    : $((Get-AgentConfigBool $config.interactive "enabled" $true))"
    Write-Host "Provider order : $(@($config.provider_order) -join ', ')"

    try {
        $policy = Read-NeoCorePolicy $config
        $policyPath = Resolve-NeoCorePolicyPath $config
        Write-Host "NeoCore       : ready ($policyPath)"
        if ($policy.model.version) { Write-Host "NeoCore Model : $($policy.model.name) $($policy.model.version)" }
        Write-Host "Module brain  : $(@($policy.modules.PSObject.Properties.Name).Count) modules, $(@($policy.weights.PSObject.Properties.Name).Count) features"
    } catch {
        Write-Host "NeoCore       : not ready - $($_.Exception.Message)"
    }

    $ollamaModel = Resolve-OllamaModel $config
    if ($ollamaModel) {
        Write-Host "Ollama        : ready ($ollamaModel)"
    } else {
        Write-Host "Ollama        : not ready"
    }

    if (Get-AgentConfigBool $config.openai_compatible "enabled" $false) {
        $openAiModel = Get-AgentConfigString $config.openai_compatible "model" "gpt-4.1-mini"
        $openAiEndpoint = Get-AgentConfigString $config.openai_compatible "endpoint" ""
        $openAiKey = Get-AgentSecret $config.openai_compatible "api_key" "NEOOPTIMIZE_OPENAI_API_KEY"
        $keyState = if ([string]::IsNullOrWhiteSpace($openAiKey)) { "no API key" } else { "API key configured" }
        Write-Host "OpenAI API    : configured ($openAiModel, $keyState, $openAiEndpoint)"
    } else {
        Write-Host "OpenAI API    : disabled"
    }

    if (Get-AgentConfigBool $config.huggingface "enabled" $false) {
        $hfModel = Get-AgentConfigString $config.huggingface "model" ""
        $hfKey = Get-AgentSecret $config.huggingface "api_key" "NEOOPTIMIZE_HF_TOKEN"
        $keyState = if ([string]::IsNullOrWhiteSpace($hfKey)) { "public/no token" } else { "token configured" }
        Write-Host "Hugging Face  : configured ($hfModel, $keyState)"
    } else {
        Write-Host "Hugging Face  : disabled"
    }

    if (Get-AgentConfigBool $config.gemini "enabled" $false) {
        $geminiModel = Get-AgentConfigString $config.gemini "model" "gemini-1.5-flash"
        $geminiKey = Get-AgentSecret $config.gemini "api_key" "NEOOPTIMIZE_GEMINI_API_KEY"
        $keyState = if ([string]::IsNullOrWhiteSpace($geminiKey)) { "no API key" } else { "API key configured" }
        Write-Host "Gemini        : configured ($geminiModel, $keyState)"
    } else {
        Write-Host "Gemini        : disabled"
    }

    $nullclaw = Test-NullClawRuntime $config
    if ($nullclaw.connected) {
        Write-Host "NullClaw      : connected ($($nullclaw.source))"
    } else {
        Write-Host "NullClaw      : not connected"
        Write-Host "NullClaw CLI  : $($nullclaw.cli)"
        if ($nullclaw.source) { Write-Host "NullClaw Path : $($nullclaw.source)" }
        Write-Host "Status        : $($nullclaw.status -replace '\r?\n', ' | ')"
        Write-Host "Doctor        : $($nullclaw.doctor -replace '\r?\n', ' | ')"
        Write-Host "Fix           : install NullClaw CLI, run 'nullclaw onboard --interactive', then refresh providers."
        Write-Host "Docs          : $($config.nullclaw.docs_url)"
    }

    Write-Host "Rule engine   : ready"
    Write-Host "Skills        : $(@($environment.skills).Count) registered"
    Write-Host "MCP connectors: $(@($environment.mcp_connectors).Count) registered"
    Write-Host "RMM telemetry : $((Get-AgentConfigBool $config.rmm_telemetry "enabled" $true)) (NEO -> RMM -> OpenFang)"
    Write-Host "Script Forge  : $((Get-AgentConfigBool $config.script_forge "enabled" $true)) (PowerShell/CMD, read-only default)"
    Write-Host ""
}

function Start-NeoCoreTraining {
    $trainer = Join-Path $Script:Root "tools\Train-NeoCore.ps1"
    if (-not (Test-Path $trainer)) {
        throw "NeoCore trainer not found: $trainer"
    }
    & $trainer
}

function Invoke-NeoLocalActionFromInteractive {
    param(
        [string]$Action,
        $Config
    )

    $normalized = ($Action -replace '[^A-Za-z0-9]', '').Trim()
    $match = Get-NeoSupportedLocalActions | Where-Object { ($_ -replace '[^A-Za-z0-9]', '') -ieq $normalized } | Select-Object -First 1
    if (-not $match) {
        Write-Host "Unknown action: $Action"
        Write-Host "Type skills to see supported actions."
        return
    }

    if (-not (Get-AgentConfigBool $Config.interactive "allow_confirmed_local_actions" $true)) {
        Write-Host "Interactive local actions are disabled by policy."
        return
    }

    $answer = Read-Host "Confirm run '$match' on this computer? Type YES"
    if ($answer -ne "YES") {
        Write-Host "Cancelled."
        return
    }

    $engine = Join-Path $Script:Root "NeoOptimize.ps1"
    if (-not (Test-Path $engine)) {
        Write-Host "NeoOptimize engine not found: $engine"
        return
    }

    Write-Host "Running $match..."
    & $engine -Action $match
}

function Start-InteractiveNeoAiOperator {
    $config = Read-AgentConfig
    if (-not $config.enabled) { throw "Model agent is disabled in config." }
    if (-not (Get-AgentConfigBool $config.interactive "enabled" $true)) { throw "NEO interactive mode is disabled in config." }

    $snapshot = Get-NeoSnapshot
    $environment = Read-AiEnvironmentConfig
    $transcript = [System.Collections.Generic.List[string]]::new()
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $Script:ReportDir "NeoOptimize_AI_Interactive_$stamp.md"
    $turn = 0
    $maxTurns = Get-AgentConfigInt $config.interactive "max_turns" 80
    if ($maxTurns -le 0) { $maxTurns = 80 }

    Save-InteractiveTurn -Transcript $transcript -Role "System" -Text ("NEO interactive session started.`r`n`r`n" + (Format-AiEnvironmentSummary -Environment $environment))

    Write-Host ""
    Write-Host "NeoOptimize NEO"
    Write-Host "==============="
    Write-Host "Neural Execution Operator"
    Write-Host "Mode    : interactive, human-confirmed"
    Write-Host "Endpoint: $($snapshot.computer_name) / $($snapshot.os) build $($snapshot.build)"
    Write-Host "Type help, plan, skills, mcp, providers, refresh, run <Action>, or exit."
    Write-Host ""

    if (-not [string]::IsNullOrWhiteSpace($Question)) {
        $result = Invoke-InteractiveAdvisor -Config $config -Snapshot $snapshot -UserQuestion $Question
        Write-Host $result.text
        Save-InteractiveTurn -Transcript $transcript -Role "Operator" -Text $Question
        Save-InteractiveTurn -Transcript $transcript -Role "NEO ($($result.provider))" -Text $result.text
        $transcript | Set-Content -Path $reportPath -Encoding UTF8
        Send-NeoAiTelemetryToRmm `
            -Config $config `
            -Snapshot $snapshot `
            -Provider $result.provider `
            -Analysis $result.text `
            -ReportPath $reportPath `
            -TelemetryEvent "interactive_question" `
            -Question $Question `
            -Transcript @($transcript) `
            -ProviderErrors @($result.errors) | Out-Null
        if (-not $NoOpen) { Start-Process notepad.exe -ArgumentList "`"$reportPath`"" }
        return
    }

    while ($turn -lt $maxTurns) {
        $line = Read-Host "neo-ai"
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $turn++
        Save-InteractiveTurn -Transcript $transcript -Role "Operator" -Text $line

        $trimmed = $line.Trim()
        if ($trimmed -match '^(exit|quit|q)$') { break }
        if ($trimmed -match '^help$') {
            $help = @"
Commands:
- ask any question in plain language
- plan: refresh NeoCore AI Doctor plan
- skills: show action skill catalog
- mcp: show MCP/connector map
- providers: show model/provider status
- refresh: collect a fresh Windows snapshot
- run <Action>: execute one local NeoOptimize action after typing YES
- exit: close session
"@
            Write-Host $help
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text $help
            continue
        }
        if ($trimmed -match '^refresh$') {
            $snapshot = Get-NeoSnapshot
            $msg = "Snapshot refreshed: health inputs from $($snapshot.computer_name), RAM used $($snapshot.ram_used_pct)%, disk free $($snapshot.disk_c_free_pct)%."
            Write-Host $msg
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text $msg
            continue
        }
        if ($trimmed -match '^skills$') {
            $environment = Read-AiEnvironmentConfig
            $text = Format-AiEnvironmentSummary -Environment $environment
            Write-Host $text
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text $text
            continue
        }
        if ($trimmed -match '^mcp$') {
            $environment = Read-AiEnvironmentConfig
            $text = "MCP / connector status:`r`n" + ((@($environment.mcp_connectors) | ForEach-Object {
                $state = if ($_.enabled) { "enabled" } else { "disabled" }
                "- $($_.name): $state, $($_.access), secret policy $($_.secret_policy)"
            }) -join "`r`n")
            Write-Host $text
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text $text
            continue
        }
        if ($trimmed -match '^providers$') {
            Show-Providers
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text "Provider status displayed in console."
            continue
        }
        if ($trimmed -match '^plan$') {
            $text = Invoke-NeoCoreAdvisor -Config $config -Snapshot $snapshot
            Write-Host $text
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text $text
            if (Get-AgentConfigBool $config.rmm_telemetry "send_on_interactive_turn" $false) {
                Send-NeoAiTelemetryToRmm `
                    -Config $config `
                    -Snapshot $snapshot `
                    -Provider "neocore" `
                    -Analysis $text `
                    -ReportPath $reportPath `
                    -TelemetryEvent "interactive_plan" `
                    -Transcript @($transcript) | Out-Null
            }
            continue
        }
        if ($trimmed -match '^run\s+(.+)$') {
            Invoke-NeoLocalActionFromInteractive -Action $Matches[1] -Config $config
            Save-InteractiveTurn -Transcript $transcript -Role "NEO" -Text "Run command processed for action: $($Matches[1])."
            continue
        }

        $result = Invoke-InteractiveAdvisor -Config $config -Snapshot $snapshot -UserQuestion $trimmed
        Write-Host ""
        Write-Host $result.text
        if ($result.errors -and @($result.errors).Count -gt 0) {
            Write-Host ""
            Write-Host "Provider fallback: $(@($result.errors) -join ' | ')"
        }
        Write-Host ""
        Save-InteractiveTurn -Transcript $transcript -Role "NEO ($($result.provider))" -Text $result.text
        if (Get-AgentConfigBool $config.rmm_telemetry "send_on_interactive_turn" $false) {
            Send-NeoAiTelemetryToRmm `
                -Config $config `
                -Snapshot $snapshot `
                -Provider $result.provider `
                -Analysis $result.text `
                -ReportPath $reportPath `
                -TelemetryEvent "interactive_turn" `
                -Question $trimmed `
                -Transcript @($transcript) `
                -ProviderErrors @($result.errors) | Out-Null
        }
    }

    $transcript | Set-Content -Path $reportPath -Encoding UTF8
    if (Get-AgentConfigBool $config.rmm_telemetry "send_on_interactive_close" $true) {
        Send-NeoAiTelemetryToRmm `
            -Config $config `
            -Snapshot $snapshot `
            -Provider "neo_interactive" `
            -Analysis "NEO interactive session closed." `
            -ReportPath $reportPath `
            -TelemetryEvent "interactive_session" `
            -Transcript @($transcript) | Out-Null
    }
    Write-Host ""
    Write-Host "Interactive report: $reportPath"
    if (-not $NoOpen) {
        Start-Process notepad.exe -ArgumentList "`"$reportPath`""
    }
}

function Invoke-FreeModelAgent {
    $config = Read-AgentConfig
    if (-not $config.enabled) { throw "Model agent is disabled in config." }

    $snapshot = Get-NeoSnapshot
    $prompt = New-AgentPrompt -Snapshot $snapshot
    $provider = "rule_based"
    $analysis = $null
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @($config.provider_order)) {
        try {
            switch ($candidate) {
                "neocore" {
                    $analysis = Invoke-NeoCoreAdvisor -Config $config -Snapshot $snapshot
                    $provider = "neocore"
                }
                "ollama" {
                    $analysis = Invoke-OllamaAdvisor -Config $config -Prompt $prompt
                    $provider = "ollama"
                }
                "openai_compatible" {
                    $analysis = Invoke-OpenAiCompatibleAdvisor -Config $config -Prompt $prompt
                    $provider = "openai_compatible"
                }
                "huggingface" {
                    $analysis = Invoke-HuggingFaceAdvisor -Config $config -Prompt $prompt
                    $provider = "huggingface"
                }
                "gemini" {
                    $analysis = Invoke-GeminiAdvisor -Config $config -Prompt $prompt
                    $provider = "gemini"
                }
                "nullclaw" {
                    $analysis = Invoke-NullClawAdvisor -Config $config -Prompt $prompt
                    $provider = "nullclaw"
                }
                "rule_based" {
                    $analysis = Invoke-RuleBasedAdvisor -Snapshot $snapshot
                    $provider = "rule_based"
                }
            }
            if ($analysis) { break }
        } catch {
            $errors.Add("${candidate}: $($_.Exception.Message)")
        }
    }

    if (-not $analysis) {
        $analysis = Invoke-RuleBasedAdvisor -Snapshot $snapshot
        $provider = "rule_based"
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $Script:ReportDir "NeoOptimize_AI_Agent_$stamp.md"
    $jsonPath = Join-Path $Script:ReportDir "NeoOptimize_AI_Agent_$stamp.json"

    $header = @"
# NeoOptimize NeoCore AI Report

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Provider selected: $provider
Mode: advisory_only

"@

    Set-Content -Path $reportPath -Value ($header + $analysis) -Encoding UTF8
    [PSCustomObject]@{
        timestamp = (Get-Date).ToString("s")
        provider = $provider
        provider_errors = @($errors)
        snapshot = $snapshot
        neocore_plan = $Script:LastNeoCorePlan
        report = $reportPath
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    if (Get-AgentConfigBool $config.rmm_telemetry "send_on_plan" $true) {
        $sent = Send-NeoAiTelemetryToRmm `
            -Config $config `
            -Snapshot $snapshot `
            -Provider $provider `
            -Analysis $analysis `
            -ReportPath $reportPath `
            -JsonPath $jsonPath `
            -TelemetryEvent "plan" `
            -ProviderErrors @($errors)
    } else {
        $sent = $false
    }

    Write-Host ""
    Write-Host "NeoOptimize NeoCore AI"
    Write-Host "======================"
    Write-Host "Provider : $provider"
    if ($errors.Count -gt 0) {
        Write-Host "Fallback : $($errors -join ' | ')"
    }
    Write-Host "Report   : $reportPath"
    if ($sent) {
        Write-Host "RMM      : telemetry sent to OpenFang context"
    } else {
        Write-Host "RMM      : telemetry not sent (agent config unavailable or disabled)"
    }
    Write-Host ""
    Write-Host $analysis
    Write-Host ""

    if (-not $NoOpen) {
        Start-Process notepad.exe -ArgumentList "`"$reportPath`""
    }
}

switch ($Mode) {
    "Providers" { Show-Providers }
    "Environment" { Show-AiEnvironment }
    "OpenNullClawDocs" { Open-NullClawDocs }
    "TrainNeoCore" { Start-NeoCoreTraining }
    "ScriptForge" { Invoke-NeoScriptForge -Goal $Question }
    "Interactive" { Start-InteractiveNeoAiOperator }
    "Plan" { Invoke-FreeModelAgent }
    default { Invoke-FreeModelAgent }
}
