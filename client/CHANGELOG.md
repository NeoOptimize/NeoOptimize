# NeoOptimize Changelog

## NeoOptimize Versi 1.0.3 - RMM Runtime Health, Hidden Workers & Local AI Bootstrap

### Fixed
- Runtime PowerShell, service checks, maintenance, update repair, uninstall, RMM bootstrap, and Ollama setup now use hidden workers instead of spawning visible CMD/PowerShell windows from the native UI.
- Legacy App Paths registration now points to `NeoOptimize.exe` instead of `LAUNCH.bat`.

### Added
- Installer bootstrap downloads/installs Ollama when missing, starts `ollama serve` hidden, and prepares `neo-light:latest`, `neo:latest`, and `neo-latest:latest`.
- NEO model alias fallback creates local Ollama aliases from bundled recipes when direct model pull is unavailable.

### Verification
- Server tests passed: 57/57 across 17 suites.
- Python AI tests passed: 3/3.
- Client-nextgen build, Rust/Tauri Windows build, public bundle verification, static no-CMD-popup scan, and installer rebuild passed.
- Installer SHA-256 checksum file regenerated at `release/windows/NeoOptimize.exe.sha256`.

## NeoOptimize Versi 1.0.3 - RMM Runtime Health & VM Release Gate

### Fixed
- RMM health check uses V8 heap limit so small startup heaps do not trigger false degraded status.
- Prometheus metrics endpoint now exports live request/process metrics.
- Metrics middleware no longer risks hanging Fastify requests.

### Changed
- VM lab harness saves QEMU guest-agent status, guest IP, remote-control port scan, and screenshot evidence.
- VM execution is marked `BLOCKED` when QGA/SSH/WinRM/RDP are unavailable.

### Verification
- Server tests passed: 57/57 across 17 suites.
- Python AI tests passed: 3/3.
- Client-nextgen build, .NET builds, public bundle verification, RMM browser smoke, live endpoint smoke, and installer rebuild passed.
- Installer SHA-256 checksum file regenerated at `release/windows/NeoOptimize.exe.sha256`.

## NeoOptimize Versi 1.0.2 - Safe Windows Maintenance Expansion

### Added
- Selectable Debloater with audit-first inventory, manual selection, protected core apps, and optional OneDrive autostart disable.
- Modules 24-36: Device Snapshot, Benchmark Report, Privacy Review, Network Diagnostics, Container/Hyper-V Tuning, Zero-Trust Security, Game Mode Ultra, AI/NPU Caching, Storage Tiering, Remote Readiness, Update Repair, Power Plan Tuning, and Security Audit.
- Bundled module reference document: `docs\MODULE_REFERENCES_2026.md`.

### Changed
- Camera, Microphone, and Location remain user-controlled; NeoOptimize does not lock them with organization AppPrivacy or LocationAndSensors policies.
- Permission preflight is audit-only and does not enable remote access, suppress UAC, or configure wildcard TrustedHosts.
- High-impact maintenance actions require explicit confirmation or `-Enforce`.

### Verification
- Client build, server tests, Python AI tests, .NET builds, installer rebuild, public bundle verification, and SHA-256 checksum validation passed.

## NeoOptimize Versi 1.0

### Core
- Modern WPF Control Center with default language EN, optional IN, and theme mode System/Dark/Light.
- CLI launcher with module actions for automation and RMM.
- Version pinned to `1.0` across installer metadata, UI, CLI, and `VERSION.txt`.
- Installer shortcut now launches the UI through `NeoOptimize.Launcher.vbs` to avoid extra CMD windows.

### NeoCore AI
- Added built-in local policy model: `models/NeoCore.Policy.json`.
- Added offline training data: `datasets/neocore_training_seed.jsonl`.
- Added trainer: `tools/Train-NeoCore.ps1`.
- Provider order: NeoCore local model, optional Ollama, optional NullClaw, safety rule engine.
- AI policy blocks secret collection, camera capture, microphone capture, and biometric collection.

### Maintenance
- Added `modules/09_Maintenance.ps1`.
- Added Clean All Junk: temp, prefetch, browser cache, shader cache, update cache, Delivery Optimization cache, recycle bin.
- Added scheduled cleanup task: `NeoOptimize Smart Cleanup`.
- Added Smart Booster and Smart Optimize.
- Added Disk Status, Scan Disk, Repair Disk, Defrag/TRIM, and Windows Health Repair.

### RMM
- Added bundled `rmm-agent` package.
- Added `NeoOptimize.RMMBootstrap.ps1`.
- Added `config/NeoOptimize.RMM.json` with local lab candidate endpoints.
- Installer attempts to connect to a reachable NeoMonitor RMM `/health` endpoint and install the agent.

### Fixes
- Fixed RAM free calculation from WMI `FreePhysicalMemory`.
- Removed stale visible wording from older package documents.
- Rebuilt `NeoOptimize-Setup-1.0.exe` and `NeoOptimize-Setup-Windows-VM.iso`.
