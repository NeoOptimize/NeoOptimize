# NeoOptimasi AI Project Structure

Struktur ini memisahkan backend agentic AI, schema database, dan Windows native client agar deployment dan maintenance tetap jelas.

```text
D:\NeoOptimize
|-- backend/
|   |-- app/
|   |   |-- api/
|   |   |   |-- deps.py
|   |   |   `-- v1/endpoints/
|   |   |       |-- ai.py
|   |   |       |-- auth.py
|   |   |       |-- commands.py
|   |   |       |-- health.py
|   |   |       |-- telemetry.py
|   |   |       `-- websocket.py
|   |   |-- core/
|   |   |   |-- config.py
|   |   |   `-- security.py
|   |   |-- models/
|   |   |   `-- schemas.py
|   |   |-- services/
|   |   |   |-- ai_agent.py
|   |   |   `-- supabase_client.py
|   |   `-- main.py
|   |-- .env.example
|   |-- Dockerfile
|   |-- README.md
|   `-- requirements.txt
|-- client_windows/
|   |-- NeoOptimize/
|   |   |-- src/
|   |   |   |-- NeoOptimize.App/           # WinUI/WPF desktop shell
|   |   |   |-- NeoOptimize.Service/       # Windows background service + scheduler
|   |   |   |-- NeoOptimize.Agent/         # Command executor and remote control worker
|   |   |   |-- NeoOptimize.Core/          # Domain logic, DTO, scheduler contracts
|   |   |   |-- NeoOptimize.Infrastructure/# REST/WebSocket/Supabase integration
|   |   |   |-- NeoOptimize.NativeBridge/  # C++/Rust/C# low-level system hooks
|   |   |   `-- NeoOptimize.Contracts/     # Shared API contracts with backend
|   |   |-- tests/
|   |   |   `-- NeoOptimize.Tests/
|   |   `-- README.md
|   `-- installer/
|       |-- scripts/
|       `-- wix/
|-- database/
|   `-- supabase_schema.sql
|-- docs/
|   `-- project-structure.md
`-- frontend/                              # Ops/admin dashboard jika nanti dibutuhkan
```

## Peran utama

- `backend/`: agentic AI, API, auth client, telemetry ingestion, remote command queue, dan logging ke Supabase.
- `client_windows/NeoOptimize.Service`: menjalankan cron internal untuk Smart Monitor, Smart Booster, Health Check, dan Integrity Scan.
- `client_windows/NeoOptimize.NativeBridge`: modul native untuk registry, service control, process priority, thermal probe, dan fingerprint hardware.
- `database/`: schema Supabase, trigger, RLS, dan realtime publication.
