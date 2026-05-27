#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use sysinfo::{Disks, Networks, System};
use tauri::{
    AppHandle, LogicalSize, Manager, PhysicalPosition, Position, Size, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder, WindowEvent,
};

static SYSTEM_STATE: OnceLock<Mutex<System>> = OnceLock::new();
static NETWORK_STATE: OnceLock<Mutex<Networks>> = OnceLock::new();
static RMM_STATE: OnceLock<Mutex<Option<(Instant, bool)>>> = OnceLock::new();

#[derive(Serialize)]
struct SystemSnapshot {
    cpu: u8,
    ram: u8,
    disk_free: u8,
    network_rx: u64,
    network_tx: u64,
    os: String,
    host: String,
    uptime: String,
    rmm_connected: bool,
}

#[derive(Serialize)]
struct CommandResult {
    ok: bool,
    message: String,
}

#[derive(Serialize)]
struct NeoAnswer {
    answer: String,
}

#[derive(Serialize)]
struct VoiceCommandResult {
    ok: bool,
    message: String,
    transcript: Option<String>,
    action: Option<String>,
}

const MINI_WIDTH: u32 = 380;
const MINI_HEIGHT: u32 = 480;
const MAIN_WIDTH: f64 = 1024.0;
const MAIN_HEIGHT: f64 = 680.0;
#[cfg(windows)]
const SINGLE_INSTANCE_MUTEX_NAME: &str = "Local\\ZenthralixLab.NeoOptimize.SingleInstance";

#[tauri::command]
fn get_system_snapshot() -> Result<SystemSnapshot, String> {
    let (cpu, ram) = {
        let state = SYSTEM_STATE.get_or_init(|| {
            let mut system = System::new_all();
            system.refresh_all();
            Mutex::new(system)
        });
        let mut system = state
            .lock()
            .map_err(|_| "system telemetry lock failed".to_string())?;
        system.refresh_cpu();
        system.refresh_memory();

        let cpu = system
            .global_cpu_info()
            .cpu_usage()
            .round()
            .clamp(0.0, 100.0) as u8;
        let total_memory = system.total_memory();
        let used_memory = system.used_memory();
        let ram = if total_memory == 0 {
            0
        } else {
            ((used_memory as f64 / total_memory as f64) * 100.0)
                .round()
                .clamp(0.0, 100.0) as u8
        };
        (cpu, ram)
    };

    let disks = Disks::new_with_refreshed_list();
    let disk_free = disks
        .iter()
        .find(|disk| {
            disk.mount_point()
                .to_string_lossy()
                .to_uppercase()
                .starts_with("C:")
        })
        .or_else(|| disks.iter().next())
        .map(|disk| {
            let total = disk.total_space();
            if total == 0 {
                0
            } else {
                ((disk.available_space() as f64 / total as f64) * 100.0)
                    .round()
                    .clamp(0.0, 100.0) as u8
            }
        })
        .unwrap_or(0);

    let (network_rx, network_tx) = {
        let state = NETWORK_STATE.get_or_init(|| Mutex::new(Networks::new_with_refreshed_list()));
        let mut networks = state
            .lock()
            .map_err(|_| "network telemetry lock failed".to_string())?;
        networks.refresh();
        (
            networks.values().map(|data| data.received()).sum(),
            networks.values().map(|data| data.transmitted()).sum(),
        )
    };

    Ok(SystemSnapshot {
        cpu,
        ram,
        disk_free,
        network_rx,
        network_tx,
        os: System::long_os_version().unwrap_or_else(|| std::env::consts::OS.to_string()),
        host: System::host_name().unwrap_or_else(|| "localhost".to_string()),
        uptime: format_duration(System::uptime()),
        rmm_connected: detect_rmm_connected(),
    })
}

#[tauri::command]
fn run_action(action: String) -> Result<CommandResult, String> {
    let allowed = [
        "Dashboard",
        "Permissions",
        "Performance",
        "Privacy",
        "Security",
        "Collect",
        "DefenderAuditMode",
        "Services",
        "Updates",
        "Power",
        "Apps",
        "StartupOptimizer",
        "ComponentCleanup",
        "EventLogMaintenance",
        "FeatureOptimizer",
        "NetworkRepair",
        "DeviceSnapshot",
        "BenchmarkReport",
        "PrivacyReview",
        "NetworkDiagnostics",
        "ContainerHyperVTuning",
        "ZeroTrustSecurity",
        "GameModeUltra",
        "AINPUCaching",
        "StorageTiering",
        "RemoteReadiness",
        "UpdateRepair",
        "PowerPlanTuning",
        "SecurityAudit",
        "Maintenance",
        "CleanAll",
        "ScheduleClean",
        "SmartBooster",
        "SmartOptimize",
        "Profile",
        "Backup",
        "ThreatMonitor",
        "Autoimmune",
        "SystemDiagnostics",
        "WindowsDoctor",
        "WindowsErrorFix",
        "DiskStatus",
        "DiskScan",
        "DiskRepair",
        "DiskOptimize",
        "HealthRepair",
        "RestorePoint",
        "RollbackLast",
        "FreeAgent",
        "FreeAgentProviders",
        "NullClawDocs",
        "AIInteractive",
        "NEOAgentic",
        "AIScriptForge",
        "AICatalog",
        "AIProviders",
        "AIEnvironment",
        "AITrain",
        "LocalAISetup",
        "VoiceCommand",
        "CloudStatus",
        "CloudOpen",
        "AgentAudit",
        "AgentRemediate",
        "AgentInstall",
        "AgentStatus",
        "AgentUninstall",
        "RemoteAccess",
        "DeepScan",
        "Cleaner",
        "SystemRepair",
        "Network",
        "IntegrityScan",
        "AIPlan",
        "NeoUpdate",
    ];
    if !allowed
        .iter()
        .any(|item| item.eq_ignore_ascii_case(&action))
    {
        return Err(format!("unsupported action: {action}"));
    }

    let root = resolve_program_root()?;

    #[cfg(not(windows))]
    {
        if let Some(result) = run_linux_action(&root, &action)? {
            return Ok(result);
        }
    }

    let engine = root.join("NeoOptimize.ps1");
    if !engine.exists() {
        return Err(format!("PowerShell engine not found: {}", engine.display()));
    }

    queue_powershell_action(&root, &engine, &action)
}

#[cfg(not(windows))]
fn run_linux_action(root: &PathBuf, action: &str) -> Result<Option<CommandResult>, String> {
    let engine = root.join("modules-linux").join("neo-linux.sh");
    if !engine.exists() {
        return Ok(None);
    }

    let output = Command::new("bash")
        .arg(engine)
        .arg(action)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|err| err.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let message = if !stdout.is_empty() {
        stdout
    } else if !stderr.is_empty() {
        stderr
    } else if output.status.success() {
        format!("{action} completed through Linux supervisor.")
    } else {
        format!("{action} exited with status {}.", output.status)
    };

    Ok(Some(CommandResult {
        ok: output.status.success(),
        message,
    }))
}

#[tauri::command]
fn ask_neo(question: String) -> Result<NeoAnswer, String> {
    let trimmed = question.trim();
    if trimmed.is_empty() {
        return Err("question is empty".to_string());
    }

    if trimmed.eq_ignore_ascii_case("siapa anda") || trimmed.eq_ignore_ascii_case("who are you") {
        return Ok(NeoAnswer {
            answer: "Saya adalah NEO (Neural Execution Operator), artificial intelligence yang dibangun di zenthralix-lab oleh nol_eight.".to_string(),
        });
    }

    let root = resolve_program_root()?;

    #[cfg(not(windows))]
    {
        return Ok(NeoAnswer {
            answer: neo_fallback_answer(trimmed, &root, None),
        });
    }

    #[cfg(windows)]
    {
        let agent = root.join("NeoOptimize.AIAgent.ps1");
        if !agent.exists() {
            return Ok(NeoAnswer {
                answer: neo_fallback_answer(
                    trimmed,
                    &root,
                    Some("NeoOptimize.AIAgent.ps1 is not packaged in this runtime."),
                ),
            });
        }

        let output = match run_powershell_capture(
            &root,
            vec![
                "-NoProfile".to_string(),
                "-ExecutionPolicy".to_string(),
                "Bypass".to_string(),
                "-File".to_string(),
                agent.to_string_lossy().to_string(),
                "-Mode".to_string(),
                "Interactive".to_string(),
                "-Question".to_string(),
                trimmed.to_string(),
                "-NoOpen".to_string(),
            ],
            Duration::from_secs(45),
        ) {
            Ok(output) => output,
            Err(err) => {
                let note = format!("The local provider could not respond: {err}");
                return Ok(NeoAnswer {
                    answer: neo_fallback_answer(trimmed, &root, Some(&note)),
                });
            }
        };

        let trimmed_output = output.trim();
        Ok(NeoAnswer {
            answer: if trimmed_output.is_empty() {
                neo_fallback_answer(
                    trimmed,
                    &root,
                    Some("The local provider returned empty output."),
                )
            } else if looks_like_powershell_policy_error(trimmed_output) {
                neo_fallback_answer(trimmed, &root, Some(trimmed_output))
            } else {
                trimmed_output.to_string()
            },
        })
    }
}

#[cfg(windows)]
fn looks_like_powershell_policy_error(output: &str) -> bool {
    let lower = output.to_lowercase();
    lower.contains("cannot be loaded")
        || lower.contains("is not digitally signed")
        || lower.contains("running scripts is disabled")
        || lower.contains("pssecurityexception")
        || lower.contains("unauthorizedaccess")
}

fn neo_fallback_answer(question: &str, root: &PathBuf, provider_note: Option<&str>) -> String {
    let lower = question.to_lowercase();
    let mut lines = Vec::new();
    let corpus_records = corpus_record_count(root);

    #[cfg(windows)]
    lines.push("Provider: NEO local fallback. NeoCore rule engine is active while Ollama/cloud providers are unavailable or returned no text.".to_string());

    #[cfg(not(windows))]
    lines.push("Provider: NEO local fallback. Linux mode uses Rust UI plus safe Linux modules with write actions gated by approval.".to_string());

    if let Some(note) = provider_note {
        lines.push(format!("Provider note: {note}"));
    }

    if lower.contains("anomali")
        || lower.contains("anomaly")
        || lower.contains("scan")
        || lower.contains("detect")
    {
        lines.push("Best next action: run Device Snapshot, Benchmark Report, then AI Doctor Check. NEO will rank CPU/RAM/disk/update/security anomalies before recommending repair.".to_string());
        lines.push("Notification path: NEO Mini status, local reports, and RMM telemetry/alerts when the endpoint is enrolled.".to_string());
    } else if lower.contains("code")
        || lower.contains("script")
        || lower.contains("bug")
        || lower.contains("fix")
        || lower.contains("perbaikan")
        || lower.contains("powershell")
    {
        lines.push("Best next action: run Script Forge. It drafts PowerShell/CMD repair suggestions with dry-run defaults, rollback notes, timeout/report metadata, and operator approval before apply.".to_string());
        lines.push("For system repair symptoms, prefer Windows Doctor or Update Repair first so the code suggestion is grounded in fresh evidence.".to_string());
    } else if lower.contains("notifikasi")
        || lower.contains("notification")
        || lower.contains("alert")
    {
        lines.push("Best next action: run Security Audit or Windows Doctor to generate an alert-grade report. Local notification surfaces are NEO Mini, tray balloon/status, worker logs, and reports; fleet alerting uses RMM telemetry after enrollment.".to_string());
    } else if lower.contains("network") || lower.contains("networkmanager") || lower.contains("internet") {
        lines.push("Best next action: run Network Diagnose. It checks adapter state, routes, DNS, gateway reachability, and RMM connectivity evidence.".to_string());
    } else if lower.contains("ram")
        || lower.contains("memory")
        || lower.contains("swap")
        || lower.contains("zram")
    {
        lines.push("Best next action: run AI Doctor Check or Benchmark. It captures RAM pressure, top processes, disk pressure, and before/after evidence before treatment.".to_string());
    } else if lower.contains("disk") || lower.contains("ssd") || lower.contains("nvme") {
        lines.push("Best next action: run Deep Scan or Disk Cleaner in dry evidence mode first. Destructive disk/boot/filesystem tuning is blocked by policy.".to_string());
    } else if lower.contains("ollama") || lower.contains("model") || lower.contains("ai") {
        lines.push("Best next action: run Local AI Setup. It verifies Ollama, packaged installer presence, model list, and NullClaw bridge status.".to_string());
    } else {
        lines.push("Best next action: run AI Doctor Check. It creates a safe care plan from telemetry, packaged corpus, and allowlisted modules.".to_string());
    }

    let windows_corpus = root.join("knowledge").join("neo-ai-corpus.manifest.json");
    let linux_corpus = root
        .join("knowledge")
        .join("linux-optimization-corpus.manifest.json");
    if windows_corpus.exists() {
        lines.push(format!(
            "Windows corpus manifest: {}",
            windows_corpus.display()
        ));
    }
    if linux_corpus.exists() {
        lines.push(format!("Linux corpus manifest: {}", linux_corpus.display()));
    }
    if let Some(records) = corpus_records {
        lines.push(format!("Packaged NEO corpus records: {records}."));
    }

    let ollama_helper = root.join("tools").join("Install-NeoOptimizeOllama.ps1");
    let ollama_installer = root.join("tools").join("OllamaSetup.exe");
    if ollama_helper.exists() {
        lines.push(format!(
            "Local AI setup helper: {}",
            ollama_helper.display()
        ));
    }
    if ollama_installer.exists() {
        lines.push(format!(
            "Bundled Ollama installer: {}",
            ollama_installer.display()
        ));
    } else {
        lines.push("Bundled Ollama installer: not present in this build; Local AI Setup can download the official installer when network is available.".to_string());
    }

    lines.push("Policy: evidence first; write actions require operator approval, timeout, report logging, and RMM signed command path when remote.".to_string());
    lines.join("\n")
}

fn corpus_record_count(root: &PathBuf) -> Option<String> {
    let manifest = root.join("knowledge").join("neo-ai-corpus.manifest.json");
    let content = fs::read_to_string(manifest).ok()?;
    let marker = "\"record_count\"";
    let start = content.find(marker)?;
    let after = content[start + marker.len()..].trim_start();
    let after_colon = after.strip_prefix(':')?.trim_start();
    let digits: String = after_colon
        .chars()
        .take_while(|ch| ch.is_ascii_digit())
        .collect();
    if digits.is_empty() {
        None
    } else {
        Some(digits)
    }
}

#[tauri::command]
fn open_voice_command() -> Result<VoiceCommandResult, String> {
    #[cfg(windows)]
    {
        let root = resolve_program_root()?;
        let voice = root.join("NeoOptimize.VoiceCommand.ps1");
        if !voice.exists() {
            return Ok(VoiceCommandResult {
                ok: false,
                message: format!("Voice command script not found: {}", voice.display()),
                transcript: None,
                action: None,
            });
        }

        let output = run_powershell_capture(
            &root,
            vec![
                "-NoProfile".to_string(),
                "-WindowStyle".to_string(),
                "Hidden".to_string(),
                "-ExecutionPolicy".to_string(),
                "Bypass".to_string(),
                "-File".to_string(),
                voice.to_string_lossy().to_string(),
                "-ListenSeconds".to_string(),
                "8".to_string(),
                "-NoExecute".to_string(),
                "-Json".to_string(),
            ],
            Duration::from_secs(15),
        )?;

        let value: serde_json::Value = serde_json::from_str(output.trim()).map_err(|err| {
            format!(
                "Voice command returned non-JSON output: {err}. Output: {}",
                output.trim()
            )
        })?;
        let ok = value
            .get("ok")
            .and_then(|item| item.as_bool())
            .unwrap_or(false);
        let transcript = value
            .get("transcript")
            .and_then(|item| item.as_str())
            .map(|item| item.to_string())
            .filter(|item| !item.trim().is_empty());
        let action = value
            .get("action")
            .and_then(|item| item.as_str())
            .map(|item| item.to_string())
            .filter(|item| !item.trim().is_empty());
        let message = value
            .get("message")
            .and_then(|item| item.as_str())
            .unwrap_or(if ok {
                "Voice command recognized."
            } else {
                "No clear voice command recognized."
            })
            .to_string();

        return Ok(VoiceCommandResult {
            ok,
            message,
            transcript,
            action,
        });
    }

    #[cfg(not(windows))]
    {
        Ok(VoiceCommandResult {
            ok: false,
            message: "Native voice command is available on Windows builds. Use typed NEO Mini chat on this platform.".to_string(),
            transcript: None,
            action: None,
        })
    }
}

#[tauri::command]
fn show_neo_mini(app: AppHandle) -> Result<CommandResult, String> {
    let window = app
        .get_webview_window("neo-mini")
        .ok_or_else(|| "NEO Mini daemon window is not available".to_string())?;
    position_mini_window(&window);
    window.show().map_err(|err| err.to_string())?;
    Ok(CommandResult {
        ok: true,
        message: "NEO Mini is running in the lower-right corner.".to_string(),
    })
}

#[tauri::command]
fn hide_neo_mini(app: AppHandle) -> Result<CommandResult, String> {
    let window = app
        .get_webview_window("neo-mini")
        .ok_or_else(|| "NEO Mini daemon window is not available".to_string())?;
    window.hide().map_err(|err| err.to_string())?;
    Ok(CommandResult {
        ok: true,
        message: "NEO Mini hidden. It will reappear when NeoOptimize is minimized.".to_string(),
    })
}

#[tauri::command]
fn show_main_window(app: AppHandle) -> Result<CommandResult, String> {
    let main = app
        .get_webview_window("main")
        .ok_or_else(|| "NeoOptimize main window is not available".to_string())?;
    main.show().map_err(|err| err.to_string())?;
    main.unminimize().map_err(|err| err.to_string())?;
    main.set_focus().map_err(|err| err.to_string())?;
    if let Some(mini) = app.get_webview_window("neo-mini") {
        let _ = mini.hide();
    }
    Ok(CommandResult {
        ok: true,
        message: "NeoOptimize restored.".to_string(),
    })
}

#[tauri::command]
fn exit_app(app: AppHandle) {
    app.exit(0);
}

#[tauri::command]
fn open_external_url(url: String) -> Result<CommandResult, String> {
    let trimmed = url.trim();
    let allowed = [
        "mailto:neooptimizeofficial@gmail.com",
        "https://buymeacoffee.com/nol.eight",
        "https://saweria.co/dtechtive",
        "https://ik.imagekit.io/dtechtive/Dana",
    ];
    if !allowed
        .iter()
        .any(|item| item.eq_ignore_ascii_case(trimmed))
    {
        return Err("external URL blocked by allowlist".to_string());
    }

    #[cfg(windows)]
    let mut command = {
        let mut cmd = Command::new("rundll32.exe");
        cmd.arg("url.dll,FileProtocolHandler").arg(trimmed);
        cmd
    };

    #[cfg(target_os = "macos")]
    let mut command = {
        let mut cmd = Command::new("open");
        cmd.arg(trimmed);
        cmd
    };

    #[cfg(all(not(windows), not(target_os = "macos")))]
    let mut command = {
        let mut cmd = Command::new("xdg-open");
        cmd.arg(trimmed);
        cmd
    };

    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|err| err.to_string())?;

    Ok(CommandResult {
        ok: true,
        message: format!("Opened in browser: {trimmed}"),
    })
}

fn queue_powershell_action(
    root: &PathBuf,
    engine: &PathBuf,
    action: &str,
) -> Result<CommandResult, String> {
    let report_dir = ui_action_report_dir(root);
    fs::create_dir_all(&report_dir).map_err(|err| err.to_string())?;
    let report_path = report_dir.join(format!("{}_{}.log", epoch_millis(), safe_file_stem(action)));
    fs::write(
        &report_path,
        format!(
            "[{}] QUEUED action={} root={}\n",
            epoch_millis(),
            action,
            root.display()
        ),
    )
    .map_err(|err| err.to_string())?;

    let script = format!(
        "$ErrorActionPreference='Continue'; \
         $ProgressPreference='SilentlyContinue'; \
         $report={report}; \
         $engine={engine}; \
         $action={action}; \
         New-Item -ItemType Directory -Path (Split-Path -Parent $report) -Force | Out-Null; \
         Add-Content -Path $report -Value ('[{{0}}] START {{1}}' -f (Get-Date -Format o), $action); \
         try {{ \
           & $engine -Action $action -NoPause -AssumeYes *>> $report; \
           $code=$LASTEXITCODE; if ($null -eq $code) {{ $code=0 }}; \
           Add-Content -Path $report -Value ('[{{0}}] END {{1}} exit={{2}}' -f (Get-Date -Format o), $action, $code); \
           exit ([int]$code); \
         }} catch {{ \
           Add-Content -Path $report -Value ('[{{0}}] ERROR {{1}}' -f (Get-Date -Format o), $_.Exception.Message); \
           exit 1; \
         }}",
        report = ps_single_quote(&report_path.to_string_lossy()),
        engine = ps_single_quote(&engine.to_string_lossy()),
        action = ps_single_quote(action),
    );

    #[cfg(windows)]
    {
        if !is_process_admin() {
            let runner_path = report_dir.join(format!(
                "{}_{}_runner.ps1",
                epoch_millis(),
                safe_file_stem(action)
            ));
            fs::write(&runner_path, &script).map_err(|err| err.to_string())?;
            return spawn_elevated_powershell_runner(&runner_path, &report_path, action);
        }
    }

    let mut command = powershell_command()?;
    command
        .arg("-NoProfile")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-Command")
        .arg(script)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }

    command.spawn().map_err(|err| err.to_string())?;
    Ok(CommandResult {
        ok: true,
        message: format!(
            "{action} queued. Execution report: {}",
            report_path.display()
        ),
    })
}

fn ui_action_report_dir(root: &PathBuf) -> PathBuf {
    #[cfg(windows)]
    {
        if let Some(program_data) = std::env::var_os("ProgramData") {
            return PathBuf::from(program_data)
                .join("NeoOptimize")
                .join("reports")
                .join("ui-actions");
        }
    }
    root.join("reports").join("ui-actions")
}

#[cfg(windows)]
fn spawn_elevated_powershell_runner(
    runner_path: &PathBuf,
    report_path: &PathBuf,
    action: &str,
) -> Result<CommandResult, String> {
    let ps = powershell_path();
    let start_script = format!(
        "$runner={runner}; $ps={ps}; Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$runner) -Verb RunAs",
        runner = ps_single_quote(&runner_path.to_string_lossy()),
        ps = ps_single_quote(&ps.to_string_lossy()),
    );

    let mut command = powershell_command()?;
    command
        .arg("-NoProfile")
        .arg("-WindowStyle")
        .arg("Hidden")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-Command")
        .arg(start_script)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    use std::os::windows::process::CommandExt;
    command.creation_flags(0x08000000);
    command.spawn().map_err(|err| err.to_string())?;

    Ok(CommandResult {
        ok: true,
        message: format!(
            "{action} queued. Approve the Windows UAC prompt if shown. Execution report: {}",
            report_path.display()
        ),
    })
}

fn ps_single_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "''"))
}

fn safe_file_stem(value: &str) -> String {
    value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

fn epoch_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
}

fn detect_rmm_connected() -> bool {
    let cache = RMM_STATE.get_or_init(|| Mutex::new(None));
    if let Ok(mut guard) = cache.lock() {
        if let Some((checked_at, value)) = *guard {
            if checked_at.elapsed() < Duration::from_secs(10) {
                return value;
            }
        }
        let value = detect_rmm_connected_uncached();
        *guard = Some((Instant::now(), value));
        return value;
    }
    detect_rmm_connected_uncached()
}

#[cfg(windows)]
fn detect_rmm_connected_uncached() -> bool {
    if endpoint_sync_state_present() || rmm_health_probe_from_config() {
        return true;
    }

    for name in ["NeoOptimize RMM Agent", "NeoOptimize Endpoint Sync Agent"] {
        let mut command = Command::new("sc.exe");
        command
            .arg("query")
            .arg(name)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        apply_no_window(&mut command);
        if let Ok(output) = command.output() {
            let text = String::from_utf8_lossy(&output.stdout).to_uppercase();
            if text.contains("RUNNING") {
                return true;
            }
        }
    }
    false
}

#[cfg(windows)]
fn endpoint_sync_state_present() -> bool {
    let Some(program_data) = std::env::var_os("ProgramData") else {
        return false;
    };
    let state_path = PathBuf::from(program_data)
        .join("NeoOptimize")
        .join("EndpointSync.json");
    let Ok(content) = fs::read_to_string(state_path) else {
        return false;
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&content) else {
        return false;
    };
    let server_url = value
        .get("ServerUrl")
        .and_then(|item| item.as_str())
        .unwrap_or("")
        .trim();
    let api_key = value
        .get("ApiKey")
        .and_then(|item| item.as_str())
        .unwrap_or("")
        .trim();
    !server_url.is_empty() && !api_key.is_empty()
}

#[cfg(windows)]
fn rmm_health_probe_from_config() -> bool {
    let Ok(root) = resolve_program_root() else {
        return false;
    };
    let config_path = root.join("config").join("NeoOptimize.RMM.json");
    let Ok(content) = fs::read_to_string(config_path) else {
        return false;
    };
    let Ok(value) = serde_json::from_str::<serde_json::Value>(&content) else {
        return false;
    };

    let mut urls = Vec::new();
    if let Ok(env_url) = std::env::var("NEOOPTIMIZE_RMM_URL") {
        if !env_url.trim().is_empty() {
            urls.push(env_url);
        }
    }
    if let Some(items) = value.get("candidate_server_urls").and_then(|item| item.as_array()) {
        for item in items {
            if let Some(url) = item.as_str() {
                if !url.trim().is_empty() {
                    urls.push(url.to_string());
                }
            }
        }
    }

    urls.into_iter().take(6).any(|url| rmm_health_probe(&root, &url))
}

#[cfg(windows)]
fn rmm_health_probe(root: &PathBuf, url: &str) -> bool {
    let script = format!(
        "$ErrorActionPreference='Stop'; $u={url}.TrimEnd('/'); try {{ $r=Invoke-RestMethod -Uri ($u + '/health') -Method Get -TimeoutSec 1; if ($r.status -eq 'ok') {{ exit 0 }} }} catch {{ }}; exit 1",
        url = ps_single_quote(url),
    );
    let Ok(mut command) = powershell_command() else {
        return false;
    };
    command
        .arg("-NoProfile")
        .arg("-WindowStyle")
        .arg("Hidden")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-Command")
        .arg(script)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    apply_no_window(&mut command);
    command.status().map(|status| status.success()).unwrap_or(false)
}

#[cfg(not(windows))]
fn detect_rmm_connected_uncached() -> bool {
    false
}

fn position_mini_window(window: &WebviewWindow) {
    let Ok(Some(monitor)) = window.current_monitor() else {
        return;
    };
    let area = monitor.work_area();
    let x = area.position.x + area.size.width as i32 - MINI_WIDTH as i32 - 18;
    let y = area.position.y + area.size.height as i32 - MINI_HEIGHT as i32 - 18;
    let _ = window.set_position(Position::Physical(PhysicalPosition::new(
        x.max(0),
        y.max(0),
    )));
}

fn resolve_program_root() -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|err| err.to_string())?;
    let mut candidates = Vec::new();
    if let Some(home) = std::env::var_os("NEOOPTIMIZE_HOME") {
        candidates.push(PathBuf::from(home));
    }
    if let Some(parent) = exe.parent() {
        candidates.push(parent.to_path_buf());
        candidates.push(parent.join("program"));
        candidates.push(parent.join("NeoOptimize"));
        candidates.push(parent.join("..").join("NeoOptimize"));
        candidates.push(parent.join("..").join("..").join("client"));
    }
    let cwd = std::env::current_dir().map_err(|err| err.to_string())?;
    candidates.push(cwd.clone());
    candidates.push(cwd.join("client"));
    candidates.push(cwd.join("program"));
    candidates.push(cwd.join("..").join("client"));

    if let Some(manifest_dir) = option_env!("CARGO_MANIFEST_DIR") {
        let manifest = PathBuf::from(manifest_dir);
        candidates.push(manifest.clone());
        candidates.push(manifest.join(".."));
        candidates.push(manifest.join("..").join("..").join("client"));
    }

    #[cfg(windows)]
    {
        if let Some(program_files) = std::env::var_os("ProgramFiles") {
            candidates.push(
                PathBuf::from(program_files)
                    .join("NeoOptimize")
                    .join("program"),
            );
        }
    }

    #[cfg(not(windows))]
    {
        candidates.push(PathBuf::from("/opt/NeoOptimize"));
        candidates.push(PathBuf::from("/opt/NeoOptimize/program"));
        candidates.push(PathBuf::from("/usr/local/share/neooptimize"));
        candidates.push(PathBuf::from("/usr/local/share/neooptimize/program"));
        if let Some(home) = std::env::var_os("HOME") {
            candidates.push(
                PathBuf::from(home)
                    .join(".local")
                    .join("share")
                    .join("NeoOptimize"),
            );
        }
    }

    for candidate in candidates {
        let normalized = normalize_candidate(candidate);
        if is_runtime_root(&normalized) {
            return Ok(normalized);
        }
    }

    exe.parent()
        .map(|path| path.to_path_buf())
        .ok_or_else(|| "cannot resolve NeoOptimize runtime directory".to_string())
}

fn normalize_candidate(candidate: PathBuf) -> PathBuf {
    fs::canonicalize(&candidate).unwrap_or(candidate)
}

fn is_runtime_root(candidate: &PathBuf) -> bool {
    candidate.join("NeoOptimize.ps1").exists()
        || candidate
            .join("modules-linux")
            .join("neo-linux.sh")
            .exists()
}

fn powershell_command() -> Result<Command, String> {
    #[cfg(windows)]
    {
        let powershell = powershell_path();
        if powershell.exists() {
            return Ok(Command::new(powershell));
        }
        return Ok(Command::new("powershell.exe"));
    }

    #[cfg(not(windows))]
    {
        Ok(Command::new("pwsh"))
    }
}

#[cfg(windows)]
fn apply_no_window(command: &mut Command) {
    use std::os::windows::process::CommandExt;
    command.creation_flags(0x08000000);
}

#[cfg(windows)]
fn powershell_path() -> PathBuf {
    let windir = std::env::var("WINDIR").unwrap_or_else(|_| "C:\\Windows".to_string());
    PathBuf::from(windir)
        .join("System32")
        .join("WindowsPowerShell")
        .join("v1.0")
        .join("powershell.exe")
}

#[cfg(windows)]
fn run_powershell_capture(
    root: &PathBuf,
    args: Vec<String>,
    timeout: Duration,
) -> Result<String, String> {
    let mut command = powershell_command()?;
    command
        .args(args)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }

    let mut child = command.spawn().map_err(|err| err.to_string())?;

    let start = Instant::now();
    loop {
        if child.try_wait().map_err(|err| err.to_string())?.is_some() {
            let output = child.wait_with_output().map_err(|err| err.to_string())?;
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            if !stdout.is_empty() {
                return Ok(stdout);
            }
            return Ok(stderr);
        }

        if start.elapsed() > timeout {
            let _ = child.kill();
            return Err("NEO command timed out".to_string());
        }
        std::thread::sleep(Duration::from_millis(120));
    }
}

fn format_duration(seconds: u64) -> String {
    let days = seconds / 86_400;
    let hours = (seconds % 86_400) / 3_600;
    let minutes = (seconds % 3_600) / 60;
    format!("{days}d {hours}h {minutes}m")
}

fn startup_arg_present(names: &[&str]) -> bool {
    let args: Vec<String> = std::env::args().skip(1).collect();
    args.iter()
        .any(|arg| names.iter().any(|name| arg.eq_ignore_ascii_case(name)))
}

fn launch_legacy_console_if_requested() -> Result<bool, String> {
    let mode = if startup_arg_present(&["--console", "-console", "/console"]) {
        Some("-Console")
    } else {
        None
    };

    let Some(mode_arg) = mode else {
        return Ok(false);
    };

    let root = resolve_program_root()?;
    let launcher = root.join("NeoOptimize.Launcher.ps1");
    if !launcher.exists() {
        return Err(format!("launcher script not found: {}", launcher.display()));
    }

    let mut command = powershell_command()?;
    command
        .arg("-NoProfile")
        .arg("-WindowStyle")
        .arg("Hidden")
        .arg("-ExecutionPolicy")
        .arg("Bypass")
        .arg("-File")
        .arg(launcher)
        .arg(mode_arg)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }

    command.spawn().map_err(|err| err.to_string())?;
    Ok(true)
}

#[cfg(windows)]
fn is_process_admin() -> bool {
    use windows_sys::Win32::UI::Shell::IsUserAnAdmin;
    unsafe { IsUserAnAdmin() != 0 }
}

#[cfg(windows)]
fn relaunch_self_elevated_if_needed() -> Result<bool, String> {
    if is_process_admin() {
        return Ok(false);
    }

    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;

    let exe = std::env::current_exe().map_err(|err| err.to_string())?;
    let exe_w = wide_null(&exe.to_string_lossy());
    let params = std::env::args()
        .skip(1)
        .map(|arg| quote_windows_arg(&arg))
        .collect::<Vec<_>>()
        .join(" ");
    let params_w = wide_null(&params);
    let runas_w = wide_null("runas");

    let result = unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            runas_w.as_ptr(),
            exe_w.as_ptr(),
            if params.is_empty() {
                std::ptr::null()
            } else {
                params_w.as_ptr()
            },
            std::ptr::null(),
            SW_SHOWNORMAL,
        )
    } as isize;

    if result <= 32 {
        return Err(format!(
            "Windows elevation failed with ShellExecute code {result}."
        ));
    }
    Ok(true)
}

#[cfg(windows)]
fn quote_windows_arg(value: &str) -> String {
    if value.is_empty() {
        return "\"\"".to_string();
    }
    if !value.chars().any(|ch| ch.is_whitespace() || ch == '"') {
        return value.to_string();
    }

    let mut quoted = String::from("\"");
    let mut backslashes = 0;
    for ch in value.chars() {
        match ch {
            '\\' => backslashes += 1,
            '"' => {
                quoted.push_str(&"\\".repeat(backslashes * 2 + 1));
                quoted.push('"');
                backslashes = 0;
            }
            _ => {
                if backslashes > 0 {
                    quoted.push_str(&"\\".repeat(backslashes));
                    backslashes = 0;
                }
                quoted.push(ch);
            }
        }
    }
    if backslashes > 0 {
        quoted.push_str(&"\\".repeat(backslashes * 2));
    }
    quoted.push('"');
    quoted
}

#[cfg(windows)]
fn wide_null(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

#[cfg(windows)]
fn show_startup_error(message: &str) {
    use windows_sys::Win32::UI::WindowsAndMessaging::MessageBoxW;
    let title = wide_null("NeoOptimize");
    let body = wide_null(message);
    unsafe {
        MessageBoxW(
            std::ptr::null_mut(),
            body.as_ptr(),
            title.as_ptr(),
            0x00000010,
        );
    }
}

#[cfg(windows)]
struct SingleInstanceGuard(windows_sys::Win32::Foundation::HANDLE);

#[cfg(windows)]
impl Drop for SingleInstanceGuard {
    fn drop(&mut self) {
        unsafe {
            let _ = windows_sys::Win32::Foundation::CloseHandle(self.0);
        }
    }
}

#[cfg(windows)]
fn is_another_instance_running() -> bool {
    use windows_sys::Win32::System::Threading::OpenMutexW;

    const SYNCHRONIZE_ACCESS: u32 = 0x0010_0000;
    let name = wide_null(SINGLE_INSTANCE_MUTEX_NAME);
    let handle = unsafe { OpenMutexW(SYNCHRONIZE_ACCESS, 0, name.as_ptr()) };
    if handle.is_null() {
        return false;
    }
    unsafe {
        let _ = windows_sys::Win32::Foundation::CloseHandle(handle);
    }
    true
}

#[cfg(windows)]
fn acquire_single_instance_guard() -> Result<SingleInstanceGuard, String> {
    use windows_sys::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS};
    use windows_sys::Win32::System::Threading::CreateMutexW;

    let name = wide_null(SINGLE_INSTANCE_MUTEX_NAME);
    let handle = unsafe { CreateMutexW(std::ptr::null_mut(), 0, name.as_ptr()) };
    if handle.is_null() {
        return Err("Could not create NeoOptimize single-instance guard.".to_string());
    }
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        unsafe {
            let _ = windows_sys::Win32::Foundation::CloseHandle(handle);
        }
        return Err("NeoOptimize is already running.".to_string());
    }
    Ok(SingleInstanceGuard(handle))
}

fn main() {
    #[cfg(windows)]
    if is_another_instance_running() {
        show_startup_error("NeoOptimize is already running.");
        return;
    }

    #[cfg(windows)]
    match relaunch_self_elevated_if_needed() {
        Ok(true) => return,
        Ok(false) => {}
        Err(err) => {
            show_startup_error(&format!(
                "NeoOptimize must run as Administrator for full local access.\n\n{err}"
            ));
            return;
        }
    }

    #[cfg(windows)]
    let _single_instance_guard = match acquire_single_instance_guard() {
        Ok(guard) => guard,
        Err(err) => {
            show_startup_error(&err);
            return;
        }
    };

    let startup_mini = startup_arg_present(&["--tray", "-tray", "/tray"]);

    match launch_legacy_console_if_requested() {
        Ok(true) => return,
        Ok(false) => {}
        Err(err) => eprintln!("NeoOptimize legacy mode failed: {err}"),
    }

    tauri::Builder::default()
        .setup(move |app| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.unmaximize();
                let _ = window.set_fullscreen(false);
                let _ = window.set_resizable(false);
                let _ = window.set_min_size(Some(Size::Logical(LogicalSize::new(MAIN_WIDTH, MAIN_HEIGHT))));
                let _ = window.set_max_size(Some(Size::Logical(LogicalSize::new(MAIN_WIDTH, MAIN_HEIGHT))));
                let _ = window.set_size(Size::Logical(LogicalSize::new(MAIN_WIDTH, MAIN_HEIGHT)));
                let _ = window.center();
                if startup_mini {
                    let _ = window.hide();
                }

                let mini = WebviewWindowBuilder::new(
                    app,
                    "neo-mini",
                    WebviewUrl::App("index.html?view=mini".into()),
                )
                .title("NEO Mini")
                .inner_size(MINI_WIDTH as f64, MINI_HEIGHT as f64)
                .min_inner_size(340.0, 420.0)
                .resizable(false)
                .decorations(false)
                .always_on_top(true)
                .skip_taskbar(true)
                .visible(startup_mini)
                .build()?;
                position_mini_window(&mini);

                let main_for_event = window.clone();
                let mini_for_event = mini.clone();
                window.on_window_event(move |event| match event {
                    WindowEvent::Focused(false) => {
                        let main = main_for_event.clone();
                        let mini = mini_for_event.clone();
                        std::thread::spawn(move || {
                            std::thread::sleep(Duration::from_millis(250));
                            if main.is_minimized().unwrap_or(false) {
                                position_mini_window(&mini);
                                let _ = mini.show();
                            }
                        });
                    }
                    WindowEvent::CloseRequested { api, .. } => {
                        api.prevent_close();
                        let _ = main_for_event.hide();
                        position_mini_window(&mini_for_event);
                        let _ = mini_for_event.show();
                    }
                    _ => {}
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_system_snapshot,
            run_action,
            ask_neo,
            open_voice_command,
            show_neo_mini,
            hide_neo_mini,
            show_main_window,
            exit_app,
            open_external_url
        ])
        .run(tauri::generate_context!())
        .expect("error while running NeoOptimize");
}
