# NeoOptimize Installation

For public users, install NeoOptimize from the GitHub Releases installer. The source-checkout helper scripts in this folder are for development and lab testing only.

## Public Installer

1. Download `NeoOptimize.exe` from GitHub Releases.
2. Verify the published SHA-256 checksum.
3. Run the installer as Administrator.
4. Launch NeoOptimize from the Start Menu or desktop shortcut.
5. Configure the RMM server URL only when joining an authorized fleet.

## Development Checkout

```cmd
LAUNCH.bat
```

or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -FullAuto
```

`-FullAuto` is Safe Care only: dashboard audit, deep scan, diagnostics, light cleanup, and AI report. It does not silently apply Defender hardening or high-risk repair policy.

## Lab Defender Recovery

If an older CLI build made Defender policy too aggressive in a VM, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -Action DefenderAuditMode
```

This keeps Microsoft Defender enabled and moves aggressive lab CFA, Network Protection, and configured ASR rules to AuditMode.

## Requirements

- Windows 10/11 or Windows Server 2019+
- Administrator approval for maintenance actions
- PowerShell 5.1+
- .NET 8 bundled in the public agent build
- Optional RMM server for fleet features

## Safety

- Signed RMM command verification
- Safety manifest guardrails
- Local reports for before/after analysis
- Restore point and rollback paths for risky repair flows
- Credential-gated update manager with SHA-256 verification
