# NeoOptimize Rust UI

This directory contains the next-generation NeoOptimize desktop shell.

## Purpose

- Rust/Tauri owns the desktop window, layout, realtime telemetry, NEO mini console, and safe process supervision.
- PowerShell remains the Windows execution engine for approved maintenance actions only.
- The UI is designed to become cross-platform while endpoint maintenance modules stay OS-specific.

## Windows Build

Install prerequisites on the Windows build machine:

```powershell
winget install --id OpenJS.NodeJS.LTS -e
winget install --id Rustlang.Rustup -e
winget install --id Microsoft.VisualStudio.2022.BuildTools -e
```

Then build:

```powershell
cd client-nextgen
npm install
npm run tauri:build
```

Expected Windows executable:

```text
client-nextgen\src-tauri\target\release\neooptimize.exe
```

The public installer build script prefers this executable automatically when it exists:

```bash
USE_RUST_UI=1 BUILD_RUST_UI=0 bash installer/client/build.sh
```

## Linux Host Note

Linux Mint can build and serve the RMM. It cannot produce the final Windows Tauri `.exe` without a Windows toolchain or CI runner. Use a Windows VM or GitHub Actions Windows runner for the final public Windows artifact.
