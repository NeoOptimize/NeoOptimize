# Changelog

## 1.2.0 NeoCortex - Public Beta

Release date: 2026-05-21

### Added

- Wider RMM system modal with page-friendly layout and 1 second telemetry refresh.
- Expanded endpoint telemetry for CPU, GPU, RAM, disk, network, device profile, process counts, location summary, and security state.
- Neo AI advisory workflow for local recommendations, script planning, safety context, and RMM/OpenFang handoff.
- Secure update manager workflow with checksum verification and repair path.
- About and support section moved to the NeoOptimize Windows client.
- Public installer guardrails: no VM guest tools bundled, no private keys, no local credentials.

### Improved

- RMM About page removed from the dashboard navigation.
- Dashboard telemetry API now supports richer historic fallback for offline agents.
- Agent telemetry collector keeps camera and microphone capture disabled by default.
- Release readiness uses an external secure signing key directory instead of repository-local keys.
- README rebuilt for public distribution with clean ASCII Markdown.

### Verification

- Dashboard build passed.
- .NET agent build passed.
- Client self-test passed.
- Installer self-test passed.
- RMM read-only API audit passed.
- Release readiness passed with 14 checks, 0 warnings, and 0 failures.

## 1.0.0 - Initial Lab Build

- First Windows optimization modules.
- Early RMM dashboard.
- Initial installer and VM validation workflow.
