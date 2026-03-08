# Neo Optimize AI - Advanced Windows System Optimizer

[![Stars](https://img.shields.io/github/stars/NeoOptimize/NeoOptimize?style=flat-square)](https://github.com/NeoOptimize/NeoOptimize)
[![Forks](https://img.shields.io/github/forks/NeoOptimize/NeoOptimize?style=flat-square)](https://github.com/NeoOptimize/NeoOptimize)
[![Issues](https://img.shields.io/github/issues/NeoOptimize/NeoOptimize?style=flat-square)](https://github.com/NeoOptimize/NeoOptimize/issues)
[![Windows 10/11/12](https://img.shields.io/badge/windows-10%2F11%2F12-blue?style=flat-square)](#-features)

> Professional-grade AI-powered Windows optimization system | System cleaning, disk optimization, privacy protection, and autonomous monitoring with explicit consent.

[Documentation](./docs/project-structure.md) • [Issues](https://github.com/NeoOptimize/NeoOptimize/issues) • [Discussions](https://github.com/NeoOptimize/NeoOptimize/discussions)

---

## Features

### Implemented in v1.0

- Smart Boost: free RAM, flush DNS, clean temp, optimize priority.
- Smart Optimize: deep cleanup, dump file cleanup, optional bloatware removal.
- Health Check: OS diagnostics (SFC/DISM status checks).
- Integrity Scan: SHA-256 verification for NeoOptimize installation files.
- Real-time monitoring: CPU/RAM/GPU/Disk IO alerting.
- HTML reports: clickable and viewable in browser.
- Neo AI chat with voice commands (speech-to-text).
- Consent gating and Auto/Manual execution toggle.

### In Progress / Planned

- Browser cache cleaning (Chrome, Edge, Firefox).
- Registry cleanup.
- Disk optimization (defrag, TRIM, scan/repair).
- Driver update scan and maintenance.
- Privacy controls (telemetry and history cleanup).
- Backup and restore point automation.
- Remote troubleshooting (consent required).

---

## Quick Start (End Users)

1. Install x64 or x86 build and run as Administrator.
2. Choose install location (C: or D:).
3. Ensure WebView2 runtime is installed.
4. Launch the app and review consent settings.

---

## Quick Start (Backend Dev, Optional)

```bash
cd backend
pip install -r requirements.txt
python -m uvicorn app.main:app --host 0.0.0.0 --port 7860
```

Required environment variables:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_ANON_KEY`
- `HF_TOKEN`
- `HF_MODEL_ID`

---

## Voice Commands and Actions

Example phrases:

- "smart boost", "boost performance", "tingkatkan performa"
- "smart optimize", "optimasi sistem"
- "health check", "periksa kesehatan sistem"
- "integrity scan", "periksa integritas file"
- "clean temp files", "hapus temp"
- "flush dns", "bersihkan dns"
- "clean dump files", "bersihkan memory dump"
- "switch to auto mode", "mode otomatis"
- "switch to manual mode", "mode manual"
- "open reports", "buka laporan"
- "clear chat", "hapus chat"

If a phrase does not match, Neo AI will fall back to chat assistance.

---

## Reports

Reports are generated as HTML files (format: `report-dd-MM-yyyy.html`) in the reports folder configured in app settings. They are clickable from the Reports panel.

---

## Trial and Licensing

Market test phase uses a 90-day trial that starts on first launch. After the trial ends, AI features are locked while non-AI optimization tools remain available. Subscription activation will be added after the trial period.

---

## Screenshot

![NeoOptimize UI](docs/assets/neooptimize-ui.png)

---

## Support Development

- Email: neooptimizeofficial@gmail.com
- Buy Me A Coffee: https://buymeacoffee.com/nol.eight
- Saweria: https://saweria.co/dtechtive
- Dana: https://ik.imagekit.io/dtechtive/Dana
- Bitcoin: bc1q3yfdzz5qtllm3luws5zudnz3t6d472r4w05ds5

---

## System Requirements

### Minimum

- OS: Windows 10 Version 1809+
- RAM: 4 GB
- Disk: 500 MB free

### Recommended

- OS: Windows 11/12
- RAM: 8 GB+

---

## Security

See [SECURITY.md](./SECURITY.md) for reporting issues.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## Acknowledgments

- FastAPI
- Supabase
- Hugging Face
- WebView2
