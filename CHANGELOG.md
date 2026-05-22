# Changelog

## 1.0.0 Public Release

Release date: 2026-05-22

### Added

- Remote Access Readiness tool for trusted Windows maintenance environments.
- Secure transport configuration for request signing, HTTPS enforcement, and certificate pinning.
- Replay protection support for signed maintenance requests.
- Public documentation for NEO skills, secure transport, and update integrity.
- PowerShell launcher that works when Windows Script Host is disabled.
- Linux Mint style Update Manager panel for check, verified install, repair, integrity scan, and release access.
- Mini tray companion with realtime CPU/RAM/DISK monitor, NEO chat, voice command, reports, provider status, and Update Manager shortcuts.
- NEO role registry so AI Doctor, local model, Script Forge, MCP bridge, and update workflow each have clear task ownership.
- NEO identity response: Neural Execution Operator, artificial intelligence built at zenthralix-lab by nol_eight.

### Improved

- Installer rebuilt as `NeoOptimize.exe` with updated endpoint policy, tools, skills, and configuration.
- Public README remains focused on NeoOptimize only.
- Update and repair documentation now highlights credential-gated SHA-256 verification.
- Lab guest tooling is no longer bundled in the public installer.
- Support wording is consistent across public-facing screens.
- Mini tray polling is lighter and no longer requests administrator elevation at login.

### Verification

- NeoOptimize UI production build completed.
- NeoOptimize maintenance runtime build completed.
- Safety manifest and NeoOptimize workflow tests passed.
- Installer package inspected for updated client files and generated with SHA-256 verification.
