# Changelog

## 1.0.5 Fixed-Scale UI, Single Instance & Voice Label

Release date: 2026-05-26

### Fixed

- Main NeoOptimize desktop window is fixed at `1024x680` and no longer resizes or drifts into horizontal/vertical scroll.
- NeoOptimize now blocks duplicate desktop instances with a Windows single-instance mutex.
- NEO Mini voice command control now has an explicit accessible voice label and tooltip.

### Updated

- README screenshot refreshed from the current Windows VM validation screen.
- Public release metadata, WinGet manifest, Chocolatey manifest, and checksum updated to `1.0.5`.

### Verification

- Client-nextgen production build passed.
- Rust/Tauri Windows target check passed.
- Rust/Tauri desktop executable and NSIS installer rebuilt.
- Installer rebuilt and verified with SHA-256 `7432e2bb2bacb82215e58967b21a09938ca1c9919f5daeda1bc154d097f5d3f4`.

## 1.0.4 No-CMD Runtime & Local AI Bootstrap

Release date: 2026-05-26

### Fixed

- NeoOptimize runtime workers no longer spawn visible CMD/PowerShell windows from the native UI.
- Installer, update repair, maintenance, uninstall, service checks, RMM bootstrap, `taskkill`, `chkdsk`, and Ollama setup now use hidden worker execution.
- Legacy Windows App Paths registration now points to `NeoOptimize.exe` instead of `LAUNCH.bat`.

### Added

- Installer bootstrap downloads and installs Ollama when missing.
- Installer starts `ollama serve` hidden and prepares `neo-light:latest`, `neo:latest`, and `neo-latest:latest`.
- Local NEO model alias fallback can create Ollama aliases when direct NEO model pull is unavailable.

### Verification

- RMM live endpoint smoke passed for `/health`, `/healthz`, `/readyz`, `/livez`, `/api/v1/health`, and `/downloads/NeoOptimize.exe`.
- RMM download asset SHA-256 matched the local release artifact.
- Server Jest suite passed: `57/57` tests across `17` suites.
- Python AI engine tests passed: `3/3`.
- Public bundle verifier, static no-CMD-popup scan, module allowlist check, Rust/Tauri Windows build, and installer rebuild passed.
- Installer rebuilt and verified with SHA-256 `e1aa5037023f156fd3343962c1688bc6ea469153af146c53b6558370d47e286f`.

## 1.0.3 RMM Runtime Health & VM Release Gate

Release date: 2026-05-26

### Fixed

- RMM health checks no longer mark a healthy Node.js process as degraded from small-heap startup memory ratios.
- Prometheus metrics export now uses the live application metrics registry and emits valid quoted labels.
- Fastify request metrics middleware now completes callback flow correctly.
- Bootstrap authentication tests use a lower bcrypt cost because they validate session flow, not password-hash benchmark timing.

### Improved

- Windows VM release-gate evidence now includes QEMU guest-agent status, detected guest IP, remote-control port scan, and screenshot capture.
- Guest execution is marked blocked when QGA, SSH, WinRM, and RDP are unavailable instead of silently skipping guest validation.
- Public README now shows the latest VM validation screenshot and v1.0.3 installer checksum.

### Verification

- RMM live endpoint smoke passed for `/health`, `/healthz`, `/readyz`, `/livez`, `/api/v1/health`, `/api/v1/metrics`, and `/downloads/NeoOptimize.exe`.
- RMM browser smoke passed across dashboard routes with no console errors and no HTTP 4xx/5xx responses.
- Server Jest suite passed: `55/55` tests across `16` suites.
- Python AI engine tests passed: `3/3`.
- Client-nextgen production build passed.
- .NET agent and UI wrapper builds passed.
- Public bundle verifier passed.
- Installer rebuilt and verified with SHA-256 `3667a2cb5ff7dfa6aed7ac7a131b6997ffb764fda3a5f4e6bfdb81bcc90620cc`.

## 1.0.0 Public Release

Release date: 2026-05-25

### Added

- Package manager distribution manifests for WinGet, Chocolatey, and Scoop.
- Remote Access Readiness tool for trusted Windows maintenance environments.
- Secure transport configuration for request signing, HTTPS enforcement, and certificate pinning.
- Replay protection support for signed maintenance requests.
- Public documentation for NEO skills, secure transport, and update integrity.
- PowerShell launcher that works when Windows Script Host is disabled.
- Linux Mint style Update Manager panel for check, verified install, repair, integrity scan, and release access.
- Mini tray companion with realtime CPU/RAM/DISK monitor, NEO chat, voice command, reports, provider status, and Update Manager shortcuts.
- Clear Chat control in the mini tray NEO chat window.
- Mini tray now opens a compact lower-right realtime monitor automatically after launch.
- NEO Agentic Autopilot for local observe, diagnose, plan, approval, action, verification, and learning loops.
- NEO role registry so AI Doctor, local model, Script Forge, MCP bridge, and update workflow each have clear task ownership.
- Optional tooling registry for PowerToys readiness and Winbindex reference intelligence.
- NEO identity response: Neural Execution Operator, artificial intelligence built at zenthralix-lab by nol_eight.

### Improved

- Installer rebuilt as `NeoOptimize.exe` with updated endpoint policy, tools, skills, and configuration.
- Public README remains focused on NeoOptimize only.
- Update and repair documentation now highlights credential-gated SHA-256 verification.
- Lab guest tooling is no longer bundled in the public installer.
- Support wording is consistent across public-facing screens.
- Installer no longer terminates itself when the public installer is named `NeoOptimize.exe`.
- UI action handlers now catch module/dialog failures and keep the main interface alive.
- Mini tray polling is lighter and no longer requests administrator elevation at login.
- NEO panel remains accessible while maintenance tasks are running, while duplicate task execution is still throttled.
- Main NeoOptimize AI page keeps monitoring and provider controls clean; interactive chat lives in the mini tray.
- Installer stops the existing endpoint sync service before replacing agent files, then reinstalls the service to `C:\Program Files\NeoOptimize\Agent`.
- Windows VM final install verified with endpoint sync agent `1.0.0`.

### Verification

- NeoOptimize UI production build completed.
- NeoOptimize maintenance runtime build completed.
- Safety manifest and NeoOptimize workflow tests passed.
- Installer package inspected for updated application files and generated with SHA-256 verification.
- Windows VM install verified: NeoOptimize installed, endpoint sync agent reconnected as version `1.0.0`, safe command dispatch works, and telemetry continues to arrive.
