# NeoOptimize Changelog

## NeoOptimize Versi 1.0

### Core
- Modern WPF Control Center with default language EN, optional IN, and theme mode System/Dark/Light.
- CLI launcher with module actions for automation and RMM.
- Version pinned to `1.0` across installer metadata, UI, CLI, and `VERSION.txt`.
- Installer shortcut now launches the UI through `NeoOptimize.Launcher.vbs` to avoid extra CMD windows.

### NeoCore AI
- Added built-in local policy model: `models/NeoCore.Policy.json`.
- Added offline training data: `datasets/neocore_training_seed.jsonl`.
- Added trainer: `tools/Train-NeoCore.ps1`.
- Provider order: NeoCore local model, optional Ollama, optional NullClaw, safety rule engine.
- AI policy blocks secret collection, camera capture, microphone capture, and biometric collection.

### Maintenance
- Added `modules/09_Maintenance.ps1`.
- Added Clean All Junk: temp, prefetch, browser cache, shader cache, update cache, Delivery Optimization cache, recycle bin.
- Added scheduled cleanup task: `NeoOptimize Smart Cleanup`.
- Added Smart Booster and Smart Optimize.
- Added Disk Status, Scan Disk, Repair Disk, Defrag/TRIM, and Windows Health Repair.

### RMM
- Added bundled `rmm-agent` package.
- Added `NeoOptimize.RMMBootstrap.ps1`.
- Added `config/NeoOptimize.RMM.json` with local lab candidate endpoints.
- Installer attempts to connect to a reachable NeoMonitor RMM `/health` endpoint and install the agent.

### Fixes
- Fixed RAM free calculation from WMI `FreePhysicalMemory`.
- Removed stale visible wording from older package documents.
- Rebuilt `NeoOptimize-Setup-1.0.exe` and `NeoOptimize-Setup-Windows-VM.iso`.
