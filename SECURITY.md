# Security Policy

NeoOptimize controls Windows maintenance workflows and must be treated as privileged software.

## Reporting

Report security issues privately by email:

neooptimizeofficial@gmail.com

Please include:

- affected component,
- reproduction steps,
- expected impact,
- logs or screenshots with secrets removed,
- suggested mitigation if known.

## Public Build Rules

- Never commit private keys, service role keys, API keys, local admin credentials, lab certificates, or generated installers.
- Keep Supabase service role keys server-side only.
- Keep command signing private keys outside the repository.
- Require SHA-256 verification for public update packages.
- Keep camera, microphone, and biometric capture disabled unless a user explicitly enables a diagnostic flow.
- Route privileged endpoint commands through signed RMM manifests and agent-side verification.

## Supported Security Surfaces

- RMM authentication and authorization.
- Agent enrollment.
- Command signing and verification.
- Update manager integrity checks.
- Safety rollback and local recovery.
- Supabase mirror queue and server-side integration secrets.

## Non-Goals

NeoOptimize public builds do not include hidden drivers, covert capture, credential collection, or bundled VM guest tools.
