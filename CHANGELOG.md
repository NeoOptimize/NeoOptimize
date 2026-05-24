# Changelog

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
