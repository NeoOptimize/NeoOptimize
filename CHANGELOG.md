# Changelog

## 1.2.2 Public Beta

Release date: 2026-05-22

### Added

- Remote Access Readiness tool for trusted Windows maintenance environments.
- Secure transport configuration for request signing, HTTPS enforcement, and certificate pinning.
- Replay protection support for signed maintenance requests.
- Public documentation for NEO AI skills, secure transport, and update integrity.

### Improved

- Installer rebuilt as `NeoOptimize.exe` with updated client policy, tools, skills, and configuration.
- Public README remains focused on the NeoOptimize Windows client only.
- Update and repair documentation now highlights credential-gated SHA-256 verification.
- Lab guest tooling is no longer bundled in the public installer.

### Verification

- Client UI production build completed.
- Client maintenance runtime build completed.
- Agent route and safety manifest tests passed.
- Installer package inspected for updated client files and generated with SHA-256 verification.

## 1.2.1 Public Beta

Release date: 2026-05-21

### Added

- Public Windows client distribution for NeoOptimize.
- About section with support contact, donation links, and update access.
- Defender Lab Recovery mode for loosening overly strict lab hardening without disabling protection.
- SHA-256 checksum file for download verification.
- Public documentation focused only on NeoOptimize client usage.

### Improved

- Cleaner public repository layout.
- Safer wording around security and administrator actions.
- Installer package rebuilt as `NeoOptimize.exe`.
- README rebuilt with professional public-facing content.

### Verification

- Client packaging completed.
- Release checksum generated.
- Public documentation scan completed with no private infrastructure wording.

## 1.0.0 Initial Lab Build

- First Windows optimization modules.
- Initial installer and VM validation workflow.
