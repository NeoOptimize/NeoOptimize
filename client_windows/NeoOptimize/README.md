# NeoOptimize Windows Client

Solution `.NET` ini menyiapkan integrasi dasar NeoOptimize ke backend Hugging Face Space dan Supabase.

## Proyek

- `src/NeoOptimize.Contracts`: DTO yang cocok dengan endpoint FastAPI.
- `src/NeoOptimize.Infrastructure`: HTTP client, fingerprint hardware, registration store, dan snapshot telemetry/health.
- `src/NeoOptimize.Service`: Worker service yang register client, push telemetry, push health, dan poll remote command.

## Build

```bash
dotnet build client_windows/NeoOptimize/NeoOptimize.slnx
```

## Konfigurasi

Override `NeoOptimize__BackendBaseUrl` jika URL runtime Space berbeda dari default `https://neooptimize-neooptimize.hf.space/`.
