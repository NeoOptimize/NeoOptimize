# NeoOptimize Local Agent (PoC)

This is a minimal proof-of-concept local agent that communicates with NeoMonitor (default http://127.0.0.1:4411).

Usage:

PowerShell:
```powershell
cd D:\NeoOptimize
npm run start:agent
```

Environment variables:
- `NEOMONITOR_URL` - monitor base URL (default `http://127.0.0.1:4411`)
- `NEO_AGENT_ID` - optional agent id
- `NEO_AGENT_KEY` - optional agent key

This agent is intentionally minimal: it sends heartbeats and reports dummy action results for PoC.
