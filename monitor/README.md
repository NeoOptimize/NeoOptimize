# NeoMonitor

NeoMonitor is the companion control server for NeoOptimize agents.

## Run

```powershell
cd D:\NeoOptimize
npm run start:monitor
```

By default NeoMonitor runs on `http://127.0.0.1:4411`.
For remote agents, set:

- `NEOMONITOR_HOST=0.0.0.0`
- Strong `NEOMONITOR_ADMIN_TOKEN`

## Auth

- Admin API token comes from env `NEOMONITOR_ADMIN_TOKEN`.
- Default if unset: `neo-monitor-admin` (change this before production).
- Dashboard sends token in header `x-admin-token`.

## Installer (for developer remote server)

Build installer package from project root:

```powershell
npm run package:monitor
```

Output:

- `release/NeoMonitor-Installer.zip`

Extract and run `install-neomonitor.ps1` as Administrator.

## Agent Integration (NeoOptimize)

Set in NeoOptimize (About page -> NeoMonitor Agent) or via API:

- `enabled=true`
- `monitorBaseUrl=http://<monitor-host>:4411`
- `agentId=<unique-id>`
- `agentKey=<shared-secret>`
- `allowRemoteActions=true` (only if you approve remote maintenance)

NeoOptimize can auto-apply recommended remote profile from About page:

- `APPLY RECOMMENDED REMOTE`

This enables monitor heartbeat + verbose diagnostics defaults.

Agent heartbeat endpoint:

- `POST /api/agent/heartbeat`

Diagnostics endpoint:

- `POST /api/agent/diagnostics`

## Safe Remote Action Types

- `ping`
- `readiness`
- `backup-now`
- `quick-safe-clean`
- `registry-safe-scan`
- `clear-logs`
- `diagnostics-send`

No arbitrary shell execution is supported.
