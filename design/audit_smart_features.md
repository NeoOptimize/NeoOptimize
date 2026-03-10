# Audit Plan: Smart features (Smart Boost, Smart Optimize, Health Check, Integrity Scan)

This document summarizes findings and an actionable audit plan for NeoOptimize smart features.

## Discovered command names (from `app.services.ai_agent.ACTION_RULES`)
- `smart_booster` (frontend label: Smart Boost)
- `flush_dns`
- `health_check`
- `clear_temp_files`

## Audit goals
- Verify each action is safe to run on Windows 10/11/12
- Ensure idempotency or safe guards for destructive steps
- Check required privileges and request elevation where needed
- Add logging, undo/restore where feasible (System Restore / create backups)
- Add telemetry + user confirmation flows for risky actions

## Per-action checklist

- smart_booster:
  - Steps: reprioritize processes, free RAM, clear temp, adjust power plan
  - Privilege: low (per-user) for temp cleanup; high for system process priority changes
  - Risks: terminating critical processes; data loss if apps terminated
  - Tests: simulate on VM, verify responsiveness improvements, ensure no system services stopped
  - Mitigations: request confirmation, exclude known-safe process whitelist, run with dry-run first

- smart_optimize (Smart Optimize):
  - Steps: broader tuning (drivers, scheduled tasks, services)
  - Privilege: admin required
  - Risks: disabling needed services, breaking startup
  - Tests: list affected services/tasks, snapshot settings before change, provide restore steps
  - Mitigations: backup registry keys, create restore point, provide UI to revert

- health_check:
  - Steps: run `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth`, check event logs
  - Privilege: admin
  - Risks: long-running, may require reboot
  - Tests: validate exit codes and report parsing, timeouts
  - Mitigations: run with progress reporting, allow user to cancel, capture logs

- integrity_scan:
  - Steps: hash critical files, compare with known-good database, run SFC/DISM
  - Privilege: admin for system locations
  - Risks: false positives, slow I/O
  - Tests: run on test image, verify reporting format and remediation suggestions

## Implementation tasks
1. Locate client executors (desktop agent that polls `/api/v1/commands/poll`) and instrument code with safety wrappers.
2. Add per-action metadata: required privilege level, risk rating, dry-run capability, rollback steps.
3. Add tests: unit tests for command-to-action mapping; PowerShell smoke scripts to simulate actions in a safe manner.
4. Add server-side guardrails: require explicit `confirm=true` for destructive actions, rate-limit remote command dispatch.
5. Add UI prompts for user confirmation and visible progress; use WebView host to request elevation when needed.

## Next steps I will take now
1. Scan the codebase for the client poller and command executors and summarize findings.
2. Create a `scripts/smoke_actions.ps1` that simulates smart_booster actions in a non-destructive dry-run mode.
3. Add metadata registry for actions in `backend/app/core/actions.json` (draft).
