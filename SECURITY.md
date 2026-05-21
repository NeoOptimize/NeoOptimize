# Security Policy

NeoOptimize is a privileged Windows maintenance utility. Treat every installer,
script, and update package as security-sensitive.

## Reporting

Report security issues privately by email:

neooptimizeofficial@gmail.com

Please include:

- affected version,
- reproduction steps,
- expected impact,
- logs or screenshots with secrets removed,
- suggested mitigation if known.

## Public Build Rules

- Never commit private keys, API keys, local credentials, certificates, or generated installer binaries.
- Verify public downloads with the published SHA-256 checksum.
- Keep update packages integrity-checked before installation or repair.
- Keep camera, microphone, and precise location access disabled unless the user explicitly starts a diagnostic flow.
- Require administrator elevation only for maintenance tasks that genuinely need it.

## Supported Security Surfaces

- Installer and update integrity.
- Local Windows maintenance workflows.
- PowerShell execution policy and administrator prompts.
- Defender-friendly safety and recovery mode.
- Repair and rollback safeguards.

## Non-Goals

NeoOptimize public builds do not include hidden drivers, covert capture,
credential collection, or bundled VM guest tools.
