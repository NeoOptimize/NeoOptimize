# Changelog

## 1.0.0 Public Release

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
- Safety manifest and client workflow tests passed.
- Installer package inspected for updated client files and generated with SHA-256 verification.
