# NeoOptimize v1.0.0 Installation Guide

## Quick Start

### Windows 10/11 (Admin Required)

1. **Batch File Method (Recommended)**
   ```cmd
   Right-click LAUNCH.bat → Run as administrator
   ```

2. **PowerShell Direct (Advanced)**
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   cd NeoOptimize-v1.0
   .\NeoOptimize.ps1
   ```

3. **Agent Mode (Remote Management)**
   ```powershell
   .\NeoOptimizeAgent.ps1
   ```

## System Requirements

- Windows 10 Build 1909+ or Windows Server 2016+
- PowerShell 5.1 or newer
- Administrator privileges required
- 50 MB free disk space
- Internet connection for updates

## Module Overview

| Module | Lines | Function |
|--------|-------|----------|
| 01_Cleaner | 205 | Temp file removal, cache cleanup |
| 02_Performance | 191 | CPU/Memory/Disk optimization |
| 03_Privacy | 201 | Telemetry and tracking removal |
| 04_Network | 193 | DNS optimization, network tuning |
| 05_Security | 194 | Defender config, firewall rules |
| 06_Services | 207 | Unnecessary service disabling |
| 07_Updates | 267 | Windows Update management |
| 08_Power | 227 | Power plan and thermal settings |

## Execution Modes

- **Quick Mode**: Essential optimizations only (5-10 mins)
- **Standard Mode**: All modules enabled (15-20 mins)
- **God Mode**: Full system optimization (30-45 mins)

## Safety Features

✓ Automatic system restore point creation  
✓ Registry backup before modifications  
✓ Rollback capability for each module  
✓ Detailed logging to /logs/  
✓ Dry-run mode available  

## Troubleshooting

### Issue: "cannot be loaded because running scripts is disabled"

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "Access Denied"

Run PowerShell as Administrator

### Issue: Script hangs

Press Ctrl+C and check logs/ directory

## Support

For issues: Check logs/ directory for detailed error messages
Documentation: See docs/ folder


---
## Production Notes (v1.0.1)
- Ollama endpoint: http://192.168.122.1:11434 (Linux host, accessible from VM)
- RMM Server: http://192.168.122.1:3000
- Supabase: https://ohyaiyujvafqxfbpbryl.supabase.co
- NullClaw: pip install nullclaw, then: nullclaw onboard --interactive
