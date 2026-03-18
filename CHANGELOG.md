# Changelog ΓÇö NeoOptimize

All notable changes to NeoOptimize are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.1.0] ΓÇö 2026-03-18 ≡ƒÜÇ *Production Release*

### Γ£¿ Highlights

NeoOptimize v1.1.0 transforms the optimizer from a solid foundation into a
full **offline-first, AI-powered** Windows toolkit ΓÇö complete with local LLM,
vector memory, real OS operations, and a production-grade installer.

### Added

#### ≡ƒºá Local AI Memory (offline-first)
- **`LocalDbContext`** ΓÇö SQLite WAL-mode database for persistent AI memory.
- **`LocalMemoryStore`** ΓÇö cosine-similarity search over conversation history; all queries parameterized (SQL-injection safe).
- **`EmbeddingService`** ΓÇö local ONNX inference (`all-MiniLM-L6-v2`, 384-dim vectors, L2-normalized).
- **`LocalLlmService`** ΓÇö LLamaSharp CPU backend for fully offline LLM; auto-falls back to cloud (Gemini/DeepSeek) when model absent.
- **`ModelDownloadService`** ΓÇö atomic SHA256-verified download of ONNX and GGUF models from HuggingFace CDN.

#### ≡ƒÆ¼ AI Chat ΓÇö 5-step RAG Pipeline
The **Neo AI Chat** window now implements full Retrieval-Augmented Generation:
1. Embed user query (local ONNX)
2. Search SQLite memory for relevant past context
3. Inject top-3 matches into LLM system prompt
4. Generate response (local or cloud)
5. Save conversation turn back to SQLite

Real-time mode indicator: **≡ƒöÆ Local AI + Memory** / **Γÿü∩╕Å Cloud AI**.

#### ΓÜÖ∩╕Å Engine ΓÇö Real OS Operations
- **`NeoEngineBridge`** ΓÇö P/Invoke to `NeoOptimize.Engine.dll` (9 exported C functions, pinned GCHandle callbacks).
- **`EngineService`** ΓÇö full real-OS capability map:
  - `flush_dns` ΓåÆ `DnsFlushResolverCache` WinAPI
  - `clean_temp` ΓåÆ Enumerate + delete temp dirs
  - `trim_working_set` ΓåÆ `EmptyWorkingSet` (psapi.dll)
  - `sfc_verify` ΓåÆ `sfc.exe /scannow`
  - `dism_check` ΓåÆ `DISM.exe /RestoreHealth`
  - `trim_ssd` / `defrag_hdd` ΓåÆ `defrag.exe`
  - `fix_windows_update` ΓåÆ service stop/start cycle
  - `clamav_scan` ΓåÆ local `clamscan.exe` (Program Files or local tools)
  - `python_cleaner` ΓåÆ CleanerEngine (50+ categories, dry-run safe)
  - `repair_windows` ΓåÆ `Repair_Windows.exe` preset system

#### ≡ƒùæ∩╕Å Bloatware Manager (100+ apps)
- **`bloatware.json`** ΓÇö categorized database of 117 Windows bloatware entries (Xbox, Bing, OEM, Social, Streaming, etc.) with risk levels (`low` / `medium` / `high`) and removal methods (`appx` / `winget` / `msi`).
- **`BloatwareService`** ΓÇö scans installed AppX via PowerShell; removes via method-specific handlers; **blocks all `high`-risk removals**; supports `--dry-run` mode.

#### ≡ƒòÉ Windows Task Scheduler Integration
- **`NeoSchedulerService`** ΓÇö 3 background tasks via XML schtasks:
  - **SmartBoost** ΓÇö every 30 min (idle)
  - **SmartOptimize** ΓÇö every 12 hours
  - **IntegrityScan** ΓÇö daily at 02:00

#### ≡ƒôª Installer (Inno Setup 6 ΓÇö v1.1.0 upgrade)
- .NET 8 Desktop Runtime detection with download link dialog
- Optional scheduler task registration (checked by default)
- Auto-creates `%LocalAppData%\NeoOptimize\models\`
- Bundles `bloatware.json`, `permissions.json`, `NeoOptimize.Engine.dll`
- Indonesian language support; consent file timestamps
- Uninstall cleanup removes all schtasks

#### ≡ƒº¬ Test Suite
- **`NeoOptimize.Tests`** ΓÇö 9 passing / 2 skipped (admin+internet only)

### Changed
- `NeoAiChatWindow.xaml.cs` ΓÇö AI mode indicator now shown in assistant greeting.
- `NeoOptimizeClientOptions` ΓÇö added LocalAI configuration keys.
- `App.xaml.cs` ΓÇö registered all new production services in DI.
- `NeoOptimize.App.csproj` ΓÇö publish profile (`win-x64-release.pubxml`) resolves LLamaSharp NETSDK1152 conflict.

### Fixed
- `NeoSchedulerService` ΓÇö  `SchedulerResult.Error` ΓåÆ `.Message` compile error.
- `NeoAiChatWindow.xaml.cs` ΓÇö removed reference to non-existent `AiModeIndicator` XAML element.
- `NU1605` ΓÇö Microsoft.Extensions version conflict in test project.

### Security
- All SQLite queries use parameterized statements.
- BloatwareService validates IDs against internal DB before PowerShell execution.
- Model downloads use atomic write + SHA256 verification.

---

## [1.0.0] ΓÇö 2026-03-14 *Initial Release*

- Core WPF/.NET 8 application
- FastAPI backend (Supabase, Hugging Face)
- WebView2 embedded frontend
- Hardware fingerprint registration
- Basic SmartBoost, SmartOptimize, IntegrityScan stubs
- NeoMonitor (Next.js monitoring dashboard)

---

*For full implementation details see the [walkthrough](./docs/walkthrough.md).*
