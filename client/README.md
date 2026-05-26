# NeoOptimize

NeoOptimize is a local-first Windows maintenance console with AI-assisted diagnostics, safe optimization workflows, update integrity checks, and an optional managed endpoint sync task for enrolled environments.

## Safety Model

- Safe Care runs read-only local overview, deep scan, diagnostics, light cleanup, and an AI report.
- High-risk repair actions require explicit confirmation, then run through hidden workers behind the native UI.
- The public build does not silently change Microsoft Defender policy.
- Managed commands must be signed by the authorized key before the endpoint accepts them.
- Updates require credentials and SHA-256 verification.
- Camera, microphone, biometric, exact location, credentials, browser secrets, and private keys are not collected by default.

## Launch

Use the installed shortcut or run:

```powershell
.\NeoOptimize.exe
```

For CLI Safe Care:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -FullAuto
```

For a read-only security audit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -Action Security
```

For lab recovery after an older aggressive hardening run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\NeoOptimize.ps1 -Action DefenderAuditMode
```

`DefenderAuditMode` keeps Microsoft Defender enabled and moves aggressive lab CFA, Network Protection, and configured ASR rules into AuditMode. It is intended for lab recovery, not for weakening production endpoints.

## Main Modules

| Area | Mode | Notes |
| --- | --- | --- |
| Dashboard | Read-only | OS, hardware, disk, network, Defender, uptime, telemetry baseline. |
| AI Doctor | Read-only | NeoCore plan, local model advisory, NullClaw/OpenFang context when configured. |
| Capability Catalog | Read-only | Safety map for every diagnostic, repair, cleanup, security, storage, network, update, and operator workflow. |
| Deep Scan | Read-only | Junk estimate, residual files, crash dumps, cache analysis. |
| Cleaner | Low risk | Temp/cache cleanup and recycle bin cleanup. |
| Diagnostics | Read-only | Boot, driver, event log, service, disk, and Defender anomaly scan. |
| Security Audit | Read-only | Defender/firewall/ASR/CFA posture report only. |
| Defender Lab Recovery | Confirmed | Lab-only recovery to AuditMode after old aggressive rules. |
| Windows Repair | Confirmed | DISM/SFC/WinRE/update repair path with confirmation and hidden worker execution. |
| Disk Tools | Mixed | Status/scan read-only; repair and optimize require confirmation. |
| Secure Update Manager | Credential-gated | Downloads only after authentication and SHA-256 validation. |

## AI Providers

Default mode is NeoCore local policy guidance. Optional providers can be configured:

- Ollama/local model for offline advisory.
- Hugging Face Spaces for hosted model experiments.
- Supabase for optional cloud mirror and audit records in enrolled environments.
- E2B for sandboxed script validation.
- OpenFang for enrolled operator/security review context.
- NullClaw bridge is optional and not installed as a hidden driver in public builds.

## Reports

Reports are written to:

```text
reports\
reports\ai\
```

They are JSON-first so managed environments can ingest them without scraping console output.

## Support

- Email: neooptimizeofficial@gmail.com
- Buy Me a Coffee support: https://buymeacoffee.com/nol.eight
- Saweria: https://saweria.co/dtechtive
- Dana: https://ik.imagekit.io/dtechtive/Dana

Made with love at Zenthralix-Lab with Codex.
