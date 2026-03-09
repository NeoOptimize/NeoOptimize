# NeoOptimize Windows Client

Target implementasi client Windows dibagi menjadi beberapa komponen:

- `src/NeoOptimize.App`: desktop UI untuk user, command center, dan notifikasi.
- `src/NeoOptimize.Service`: Windows Service untuk job scheduler 1 menit, 30 menit, 1 jam, dan 24 jam.
- `src/NeoOptimize.Agent`: executor untuk remote command, self-heal, dan patch deployment.
- `src/NeoOptimize.Core`: domain models dan orchestration logic.
- `src/NeoOptimize.Infrastructure`: REST client, WebSocket client, Supabase auth bridge, logging sink.
- `src/NeoOptimize.NativeBridge`: akses low-level ke registry, service manager, WMI, ETW, thermal sensor, dan SHA-256 integrity scan.
- `src/NeoOptimize.Contracts`: kontrak DTO yang mengikuti backend FastAPI.
- `tests/NeoOptimize.Tests`: unit dan integration test.

Stack yang direkomendasikan: `.NET 8` untuk App/Service/Agent, ditambah `C++` atau `Rust` untuk native bridge bila perlu akses sistem yang lebih rendah.
