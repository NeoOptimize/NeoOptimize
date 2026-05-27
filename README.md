# NeoOptimize

NeoOptimize is an AI-empowered Windows optimization and maintenance platform for
local diagnostics, safe cleanup, repair guidance, update integrity checks,
real-time system monitoring, and before/after maintenance reporting.

The public release focuses on the NeoOptimize desktop application, local safety
workflow, mini tray companion, update manager, NEO local assistant features, and
RMM release-gate validation.

![NeoOptimize running in a Windows VM with RMM connected](assets/neooptimize-screenshot.png)

_Latest release-gate screenshot captured from the Windows VM validation run._

## Download

| Item | Value |
| --- | --- |
| Version | `1.0` |
| Installer | `NeoOptimize.exe` |
| SHA-256 | `ae2d63b0b30f5f4b4195f3d3d71a5b088b5985263f1afba46717f3e056cfd5f4` |
| Release | https://github.com/NeoOptimize/NeoOptimize/releases/latest |

Verify the installer before running it:

```powershell
Get-FileHash .\NeoOptimize.exe -Algorithm SHA256
```

The hash must match:

```text
ae2d63b0b30f5f4b4195f3d3d71a5b088b5985263f1afba46717f3e056cfd5f4
```

## What NeoOptimize Does

NeoOptimize is built for practical Windows maintenance. It is not a cosmetic
one-click optimizer. The application reads local system signals, explains
probable causes, recommends safe actions, and keeps high-impact changes behind
explicit user approval.

Core goals:

- Detect performance bottlenecks across CPU, GPU, RAM, disk, network, startup,
  services, updates, and power configuration.
- Explain system health in a format normal users and technicians can act on.
- Separate scan, report, cleanup, repair, benchmark, and update operations.
- Reduce accidental damage by ranking actions by risk and reversibility.
- Produce before/after reports so maintenance results can be measured.
- Keep local-first operation available without requiring a cloud account.

## Product Components

| Component | Purpose |
| --- | --- |
| Main desktop UI | Central dashboard for monitoring, AI Doctor, optimization modules, reports, settings, and update checks. |
| Mini tray companion | Compact lower-right monitor for CPU, RAM, disk, NEO chat, voice command, clear chat, and quick-open actions. |
| AI Doctor | Converts local telemetry into a risk-ranked care plan with practical maintenance recommendations. |
| Optimizer modules | Runs guided cleanup, diagnostics, repair, debloat review, privacy review, update audit, power audit, and benchmark workflows. |
| Safety engine | Keeps privileged actions confirmation-gated, logged, and separated from read-only scans. |
| Update Manager | Checks release metadata, verifies SHA-256 integrity, installs updates, and repairs damaged installs. |
| Report engine | Generates local reports for health checks, benchmark results, repairs, and maintenance history. |
| NEO assistant | Local AI workflow for text guidance, voice entry, anomaly explanation, and script planning assistance. |
| RMM release gate | Verifies local health probes, Prometheus metrics, dashboard routes, installer download, and VM evidence before release. |

## Main Features

### Real-Time Monitoring

- CPU usage, kernel pressure, and clock information.
- GPU availability and usage when the local system exposes compatible counters.
- RAM usage, available memory, committed memory pressure, and cache indicators.
- Disk free space, read/write pressure, queue length, and latency indicators.
- Network throughput, adapter status, local IP information, and connectivity state.
- Uptime, process count, thread count, handle count, and power-state visibility.

### AI Doctor

AI Doctor turns local telemetry into a practical care plan. It prioritizes
actions based on expected benefit, risk level, privilege requirement, and
reversibility.

It can help explain:

- high idle CPU usage,
- RAM pressure,
- disk queue spikes,
- slow boot,
- network instability,
- Windows Update failures,
- repeated repair failures,
- unusual process growth,
- common security posture problems.

### Mini Tray Companion

The mini tray is designed to stay lightweight while the main window is minimized.
It gives quick access to monitoring and NEO interaction without opening extra
PowerShell windows.

Mini tray capabilities:

- compact live CPU, RAM, and disk status,
- NEO text conversation panel,
- voice command entry point,
- clear chat action,
- quick-open button for the main interface,
- update and provider status shortcuts,
- automatic chat retention cleanup to avoid long local chat buildup.

### NEO Local Assistant

NEO stands for Neural Execution Operator. It is the local assistant layer inside
NeoOptimize.

When asked who it is, NEO answers:

> I am NEO, Neural Execution Operator, an artificial intelligence built at Zenthralix-Lab by nol_eight.

NEO responsibilities:

- summarize local telemetry,
- explain anomalies,
- draft safe maintenance plans,
- guide the user through repair workflows,
- prepare PowerShell or CMD maintenance drafts for review,
- support text and voice interaction from the mini tray,
- keep actions tied to allowlisted NeoOptimize modules,
- require approval before executing privileged maintenance.

Local model support is designed for privacy-preserving offline diagnosis. The
installer can download and install Ollama locally, start the local API hidden,
and prepare `neo-light:latest`, `neo:latest`, and `neo-latest:latest` for NEO.
Optional cloud providers can be configured by the user, but core local
diagnostics remain available without requiring an API key.

### Update Manager

The Update Manager follows a cautious, Linux Mint style workflow:

1. Check for update metadata.
2. Show release information and version details.
3. Verify SHA-256 before install.
4. Apply the update only after confirmation.
5. Repair the local installation if required files are missing or damaged.

Update actions are credential-gated and integrity-checked so an update package
cannot be silently replaced without detection.

## Optimization Module Catalog

| Module | Function |
| --- | --- |
| Disk Cleaner | Removes temporary files, caches, dumps, logs, and common residual files. |
| Deep Scan | Searches deeper junk locations before removal and reports findings first. |
| System Repair | Guides SFC, DISM, WinRE, boot repair, and Windows Update reset workflows. |
| Windows Repair | Runs conservative Windows repair planning for image, file integrity, recovery, and service state issues. |
| Update Repair | Reviews Windows Update component health and prepares confirmation-gated repair actions. |
| Privacy Review | Reviews telemetry-related settings and application permission posture. |
| Network Diagnose | Checks adapter state, DNS, latency, routing, and connectivity symptoms. |
| Containerization & Hyper-V | Audits WSL2, Hyper-V, virtualization, and container-related performance posture. |
| Zero-Trust Security | Reviews Defender, firewall, ASR, SMB, TLS, UAC, exploit protection, and credential protection posture. |
| Game Mode Ultra | Reviews gaming-related CPU, GPU, scheduler, power, and latency settings before applying high-impact changes. |
| AI & NPU Caching | Audits local AI, NPU, memory pressure, and model-cache limits for workstation tuning. |
| NVMe DirectStorage & Storage Tiering | Reviews SSD health, TRIM, BypassIO/DirectStorage readiness, and storage tiering posture. |
| Update Audit | Reviews Windows Update state and repair options. |
| Power Audit | Reviews active power plan, battery posture, and performance-related settings. |
| Power Plan Tuning | Prepares balanced, high-performance, or workstation-specific power recommendations. |
| Device Snapshot | Captures hardware, driver, OS, and security posture inventory before changes. |
| Startup Review | Helps identify startup entries that slow down boot. |
| Service Review | Reviews service state and startup behavior before any change is applied. |
| Security Audit | Reviews Defender, firewall, ASR, UAC, SMB, TLS, and exploit protection posture. |
| Benchmark | Captures before/after metrics so maintenance impact can be measured. |
| Remote Access Readiness | Checks RDP, WinRM, firewall, network profile, and admin readiness without silently enabling access. |
| Report Export | Saves local reports for later troubleshooting or support review. |

## Release Validation

The `1.0` release gate completed with:

- Fixed-scale desktop UI validation at `1024x680` from the current Windows VM screenshot.
- Single-instance desktop guard validation for NeoOptimize startup.
- NEO Mini voice command label and tooltip validation.
- NEO Mini local AI fallback validation for status, anomaly scan, code repair guidance, corpus-aware suggestions, and Local AI setup prompts.
- Hidden Ollama setup validation: installer starts the Local AI helper in a background worker with no visible CMD/PowerShell window.
- RMM live endpoint smoke for `/health`, `/healthz`, `/readyz`, `/livez`, `/api/v1/health`, `/api/v1/metrics`, and `/downloads/NeoOptimize.exe`.
- RMM browser smoke across dashboard routes with no console errors and no HTTP 4xx/5xx responses.
- Server Jest suite: `69/69` tests across `21` suites.
- Python AI engine tests: `3/3`.
- Client-nextgen production build, Rust/Tauri Windows build, public bundle verifier, static no-CMD-popup scan, and installer rebuild.

## Safety Model

NeoOptimize is audit-first by default.

- Scan and report actions are separated from cleanup and repair actions.
- High-impact actions require administrator approval.
- Repair workflows are confirmation-gated and run behind the native UI through hidden workers.
- Cleanup tasks are scoped to known safe locations.
- Privileged execution still requires Windows Administrator approval when required.
- Remote access readiness features are disabled unless explicitly enabled by an administrator.
- Camera, microphone, browser secrets, private keys, documents, and biometric data are not collected by default.
- Reports stay local unless the user chooses to share them.

## Privacy

NeoOptimize is designed as a local-first maintenance utility. The public build
does not require a user account for local diagnosis. Network access is used for
release downloads, update metadata, optional support links, and optional
user-configured AI providers.

## Install

1. Open the release page.
2. Download `NeoOptimize.exe`.
3. Verify the SHA-256 checksum.
4. Run the installer as Administrator.
5. Let the installer finish local AI setup. It downloads/installs Ollama if needed, starts `ollama serve` hidden, and prepares `neo-light:latest`, `neo:latest`, and `neo-latest:latest`.
6. Open NeoOptimize from the Start Menu or desktop shortcut.
7. Start with AI Doctor, Safe Cleanup, or Benchmark.

## Windows Defender Notice

Unsigned public installers can trigger SmartScreen or reputation warnings.
NeoOptimize is preparing a SignPath-based signing workflow for public freeware
releases. SmartScreen reputation can still take time to build even after signing.

If an older lab build made Windows Security too strict, open NeoOptimize and run
the Defender Lab Recovery action, or run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -Action DefenderAuditMode
```

This keeps Microsoft Defender enabled and moves aggressive lab ASR, Controlled
Folder Access, and Network Protection policies to AuditMode.

## System Requirements

| Requirement | Minimum |
| --- | --- |
| OS | Windows 10 or Windows 11 |
| Privilege | Administrator approval for maintenance actions |
| Runtime | PowerShell 5.1 or later |
| Disk | 300 MB for the app, plus additional space for Ollama and local model files |
| Network | Optional, used for updates, downloads, and optional providers |

## Package Managers

Package manager manifests are prepared under `distribution/`.

| Channel | Package | Status |
| --- | --- | --- |
| WinGet | `ZenthralixLab.NeoOptimize` | Manifest prepared for registry submission. |
| Chocolatey | `neooptimize` | Package template prepared for moderation submission. |
| Scoop | `neooptimize` | Planned for a later user-space package. |

Until each registry accepts the package, use the GitHub Release download and
verify the SHA-256 checksum.

## Code Signing

Free code signing is planned through SignPath.io with certificates from the
SignPath Foundation. The signing workflow is intentionally gated until the
public repository contains the complete application source and installer build
recipe required for reproducible signing.

See `SIGNPATH.md` for the signing plan.

## Support Zenthralix-Lab

NeoOptimize is released as a free public utility. Support helps Zenthralix-Lab
fund testing hardware, build infrastructure, documentation, security review,
release maintenance, and future free software projects for the community.

- Email: [neooptimizeofficial@gmail.com](mailto:neooptimizeofficial@gmail.com)
- Buy Me a Coffee: https://buymeacoffee.com/nol.eight
- Saweria: https://saweria.co/dtechtive
- Dana: https://ik.imagekit.io/dtechtive/Dana

## About

Made with love at Zenthralix-Lab with Codex.

## License

NeoOptimize is released under the Apache License 2.0.
