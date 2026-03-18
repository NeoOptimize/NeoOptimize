# NeoOptimize ΓÇö AI-Powered Windows System Optimizer

[![Version](https://img.shields.io/badge/version-1.1.0-blue?style=flat-square)](https://github.com/NeoOptimize/NeoOptimize/releases)
[![Build](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)](#)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%2F12-blue?style=flat-square)](#system-requirements)
[![.NET](https://img.shields.io/badge/.NET-8.0-purple?style=flat-square)](https://dotnet.microsoft.com/download/dotnet/8.0)
[![AI](https://img.shields.io/badge/AI-Local%20%2B%20Cloud-orange?style=flat-square)](#-ai-features)
[![Stars](https://img.shields.io/github/stars/NeoOptimize/NeoOptimize?style=flat-square)](https://github.com/NeoOptimize/NeoOptimize)
[![License](https://img.shields.io/badge/license-Custom-lightgrey?style=flat-square)](./LICENSE.txt)

> **NeoOptimize v1.1.0** ΓÇö Offline-first AI system optimizer with local LLM memory, real OS operations, 117-app bloatware manager, and Windows Task Scheduler integration.

[≡ƒôÑ Download](#-download) ΓÇó [Γ£¿ Features](#-features) ΓÇó [≡ƒÜÇ Quick Start](#-quick-start) ΓÇó [≡ƒôû Docs](#-documentation) ΓÇó [≡ƒÆû Support](#-support)

---

## ≡ƒôÑ Download

| File | Description |
|------|-------------|
| [NeoOptimize-Setup-1.1.0.exe](https://github.com/NeoOptimize/NeoOptimize/releases/latest) | **Installer** (recommended) |
| [NeoOptimize-v1.1.0-win-x64.zip](https://github.com/NeoOptimize/NeoOptimize/releases/latest) | Portable ZIP |
| [CHECKSUMS-SHA256.txt](https://github.com/NeoOptimize/NeoOptimize/releases/latest) | SHA256 verification |

**Requires:** Windows 10 v1903+ ┬╖ .NET 8 Desktop Runtime ┬╖ Admin privileges

---

## ≡ƒû╝∩╕Å Screenshots

| Dashboard | AI Chat |
|:---------:|:-------:|
| ![Dashboard](docs/assets/dashboard.png) | ![AI Chat](docs/assets/ai_chat.png) |

---

## Γ£¿ Features

### ≡ƒºá Local AI Memory (Offline-First)
- **SQLite vector store** ΓÇö remembers past conversations with cosine-similarity search
- **Local ONNX embedding** (`all-MiniLM-L6-v2`, 384-dim, auto-downloaded 22 MB)
- **LLamaSharp LLM** ΓÇö fully offline inference, auto-falls back to Cloud (Gemini/DeepSeek)
- **5-step RAG pipeline**: Embed ΓåÆ Search ΓåÆ Inject context ΓåÆ Generate ΓåÆ Save

### ΓÜÖ∩╕Å Real OS Operations
| Capability | How |
|-----------|-----|
| `flush_dns` | WinAPI `DnsFlushResolverCache` |
| `clean_temp` | Delete all user & system temp dirs |
| `trim_working_set` | `EmptyWorkingSet` (psapi.dll) |
| `sfc_verify` | `sfc.exe /scannow` |
| `dism_check` | `DISM.exe /RestoreHealth` |
| `trim_ssd` / `defrag_hdd` | `defrag.exe` |
| `clamav_scan` | Local `clamscan.exe` |
| `python_cleaner` | CleanerEngine (50+ categories) |
| `repair_windows` | `Repair_Windows.exe` presets |

### ≡ƒùæ∩╕Å Bloatware Manager
- 117-app categorized database (`bloatware.json`) ΓÇö Xbox, Bing, OEM, Social, Streaming, etc.
- Risk levels: `low` / `medium` / `high` ΓÇö high-risk apps always require manual removal
- Removal via `appx` / `winget` / `msi` ΓÇö with **dry-run mode**

### ≡ƒòÉ Background Automation
- **SmartBoost** ΓÇö every 30 min (idle)
- **SmartOptimize** ΓÇö every 12 hours
- **IntegrityScan** ΓÇö daily at 02:00
- Registered as Windows Task Scheduler tasks (`RunLevel=HighestAvailable`)

### ≡ƒöä Auto-Update
- Polls GitHub Releases every 6 hours in the background
- Applies updates silently via Velopack `Update.exe` if present

---

## ≡ƒÜÇ Quick Start

### Option A ΓÇö Installer
1. Download `NeoOptimize-Setup-1.1.0.exe`
2. Run as Administrator
3. Follow the setup wizard ΓÇö **.NET 8 check** runs automatically
4. Optionally enable **background scheduler tasks** (checked by default)
5. Launch NeoOptimize ΓÇö AI model downloads automatically on first run

### Option B ΓÇö Portable
```powershell
# Extract and run as Admin
Expand-Archive NeoOptimize-v1.1.0-win-x64.zip -DestinationPath "C:\Tools\NeoOptimize"
Start-Process "C:\Tools\NeoOptimize\NeoOptimize.App.exe" -Verb RunAs
```

### Option C ΓÇö Build from Source
```powershell
git clone https://github.com/NeoOptimize/NeoOptimize
cd NeoOptimize\client_windows\NeoOptimize

# Build
dotnet build src\NeoOptimize.App\NeoOptimize.App.csproj -c Release

# Publish (win-x64)
dotnet publish src\NeoOptimize.App\NeoOptimize.App.csproj /p:PublishProfile=win-x64-release
```

---

## ≡ƒùú∩╕Å AI Voice Commands

| English | Bahasa Indonesia |
|---------|-----------------|
| `smart boost` | `tingkatkan performa` |
| `smart optimize` | `optimasi sistem` |
| `health check` | `periksa kesehatan sistem` |
| `integrity scan` | `periksa integritas file` |
| `flush dns` | `bersihkan dns` |
| `clean temp files` | `hapus temp` |
| `open reports` | `buka laporan` |

---

## ≡ƒöÆ Security

- All SQLite queries are **parameterized** (SQL-injection safe)
- BloatwareService validates package IDs **against internal DB** before PowerShell execution
- Model downloads use **atomic write + SHA256 verification**
- Task Scheduler tasks use `DisallowStartIfOnBatteries=true`
- Consent file written to `%ProgramData%\NeoOptimize\consent.json` on install

---

## ≡ƒôÜ Documentation

| Doc | Description |
|-----|-------------|
| [CHANGELOG.md](./CHANGELOG.md) | Full version history |
| [EULA.txt](./installer/resources/EULA.txt) | License agreement |
| [PRIVACY.txt](./installer/resources/PRIVACY.txt) | Privacy policy |

---

## ΓÜÖ∩╕Å System Requirements

| | Minimum | Recommended |
|-|---------|-------------|
| **OS** | Windows 10 v1903 | Windows 11/12 |
| **RAM** | 4 GB | 8 GB+ |
| **Disk** | 500 MB | 3 GB (with GGUF model) |
| **Runtime** | .NET 8 Desktop | .NET 8 Desktop |
| **GPU** | ΓÇö | CUDA for faster AI |

---

## ≡ƒÆû Support

- ≡ƒôº Email: neooptimizeofficial@gmail.com
- Γÿò [Buy Me A Coffee](https://buymeacoffee.com/nol.eight)
- ≡ƒç«≡ƒç⌐ [Saweria](https://saweria.co/dtechtive) ┬╖ [Dana](https://ik.imagekit.io/dtechtive/Dana)
- Γé┐ Bitcoin: `bc1q3yfdzz5qtllm3luws5zudnz3t6d472r4w05ds5`

---

## ≡ƒñ¥ Contributing

Contributions are welcome! See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## ≡ƒôä License

NeoOptimize Software License Agreement. See [LICENSE.txt](./LICENSE.txt).
