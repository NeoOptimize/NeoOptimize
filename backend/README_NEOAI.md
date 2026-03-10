# Neo Optimize AI - Complete System Documentation

## Overview

Neo Optimize AI is a comprehensive, production-grade Windows system optimization suite powered by artificial intelligence. It provides complete system cleaning, disk optimization, privacy protection, and autonomous monitoring capabilities.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Neo Optimize AI System Architecture           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Gradio Web Interface (Port 7861)         │  │
│  │  - System Monitoring Dashboard                   │  │
│  │  - Tool Execution Interface                      │  │
│  │  - Real-time Results & Advice                    │  │
│  └──────────────────┬───────────────────────────────┘  │
│                     │                                   │
│                     ↓ HTTP + API Key Auth              │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │    FastAPI Backend Server (Port 7860)            │  │
│  │  - Tool Execution Engine                         │  │
│  │  - System Monitoring Service                     │  │
│  │  - Command Polling Interface                     │  │
│  └──────────────────┬───────────────────────────────┘  │
│                     │                                   │
│                     ↓ Windows Commands                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │    Windows Command Executor                      │  │
│  │  - Elevated Command Runner                       │  │
│  │  - File/Registry Operations                      │  │
│  │  - System Calls                                  │  │
│  └──────────────────┬───────────────────────────────┘  │
│                     │                                   │
│                     ↓ PowerShell / WMI                  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │        Windows System (10/11/12)                 │  │
│  │  - File System                                   │  │
│  │  - Registry                                      │  │
│  │  - Services                                      │  │
│  │  - Processes (Memory/CPU)                        │  │
│  │  - Disks (HDD/SSD)                               │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │         Optional: Supabase Backend                │  │
│  │  - Command Queue                                 │  │
│  │  - Long-term Memory                              │  │
│  │  - Telemetry (if enabled)                        │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Components

### 1. **Gradio Web Interface** (`gradio_ui.py`)
User-friendly web interface with tabs for:
- System Monitor: Real-time CPU, RAM, and disk information
- Cleaners: Temp files, browser cache, recycle bin, registry
- Defragmentation: HDD defrag and SSD TRIM
- Disk Scan: Error detection and repair
- System Health: SFC and DISM operations
- Privacy: Bloatware removal and telemetry disabling
- Smart Boost: One-click comprehensive optimization

**Access:** http://localhost:7861

### 2. **FastAPI Backend** (`neoai_backend.py`)
Core backend service providing:
- RESTful API for all operations
- System monitoring and health checks
- Tool execution with dry-run preview
- API key authentication
- Comprehensive logging
- Autonomous monitoring (runs in background)

**Access:** http://localhost:7860

**API Docs:** http://localhost:7860/docs

### 3. **Windows Command Executor** (`windows_cmd_executor.py`)
Direct Windows system integration:
- Elevated command execution
- WMI queries for system info
- Registry operations
- Service management
- Disk operations

### 4. **System Monitor** (Built-in)
Autonomous monitoring thread:
- Checks system health every minute
- Auto-cleanup when RAM exceeds 85%
- Smart recommendations based on system status
- Scheduled task execution
- Proactive advice generation

## Installation & Setup

### Prerequisites
- Windows 10/11/12
- Python 3.10+
- Administrator privileges (for some operations)

### Installation Steps

1. **Install Python dependencies:**

```bash
cd d:\NeoOptimize\backend
pip install -r requirements-neoai.txt
```

2. **Configure environment:**

```bash
# Edit .env with your settings
set HF_TOKEN=your_huggingface_token
set SUPABASE_URL=your_supabase_url
set SUPABASE_KEY=your_supabase_key
set CLIENT_API_KEY=your_secure_api_key
```

3. **Start Backend:**

```bash
# Option 1: Run batch file (auto-setup)
start_backend.bat

# Option 2: Manual
python neoai_backend.py
```

4. **Start Web Interface (in separate terminal):**

```bash
start_ui.bat

# Or manually
python gradio_ui.py
```

## Tool Documentation

### Cleaners

#### Clean Temporary Files
Removes system temporary files from:
- %TEMP% directory
- %SystemRoot%\Temp
- %LocalAppData%\Temp

**Safety:** Safe to clean - Windows recreates as needed

#### Clean Browser Cache
Removes cache from:
- Google Chrome
- Microsoft Edge  
- Mozilla Firefox
- Opera, Brave, Vivaldi

**Safety:** Browser will rebuild cache on next use

#### Empty Recycle Bin
Permanently deletes files in recycle bin.

**Safety:** Requires confirmation in dry-run mode

#### Clean Registry
Removes invalid/obsolete registry entries.

**Safety:** Creates backup before modification (if enabled)

### Disk Optimization

#### Defragmentation (HDD)
Optimizes HDD drive layout using Windows `Optimize-Volume -Defrag`.

**Duration:** 1-24 hours depending on drive size
**Safety:** Non-destructive, improves performance

#### TRIM (SSD)
Executes TRIM operation on SSD to maintain performance.

**Duration:** 5-30 minutes
**Safety:** Essential for SSD longevity

### Disk Scanning

#### Scan Disk
Checks for disk errors using `Repair-Volume`.

**Options:**
- Scan Only: Detect errors without fixing
- Scan & Repair: Automatically fix found errors

**Duration:** 30 minutes - several hours
**Safety:** Can fix corrupted sectors automatically

#### Wipe Free Space
Securely erases free disk space using `cipher.exe`.

**Duration:** Several hours depending on drive size
**Safety:** Cannot recover deleted files afterward

### System Health

#### System File Checker (SFC)
Windows built-in tool to scan and repair system files.

**Command:** `sfc /scannow`
**Duration:** 15-60 minutes
**Safety:** Repairs critical system files, requires admin

#### DISM Repair
Deep system repair using Deployment Image Servicing and Management.

**Command:** `DISM /Online /Cleanup-Image /RestoreHealth`
**Duration:** 30-120 minutes
**Safety:** Repairs Windows component store

### Privacy & Security

#### Remove Bloatware
Removes pre-installed unnecessary applications:
- Bing Weather, News, Maps
- Mixed Reality Portal
- Xbox App, Zune Music/Video
- OneConnect, People
- And more

**Safety:** Can be reverted using Windows Store

#### Disable Telemetry
Disables Windows telemetry services:
- DiagTrack (Diagnostic Tracking Service)
- dmwappushservice
- AppVShNotify

**Safety:** Privacy improvement, no system impact

#### Disable Privacy Tracking
Disables privacy-invasive features:
- Activity history
- App suggestions
- Advertising ID tracking

**Safety:** Improves privacy, no system impact

### Smart Boost
Comprehensive all-in-one optimization that:
1. Cleans temporary files
2. Cleans browser caches
3. Empties recycle bin
4. Disables telemetry
5. Disables tracking
6. Removes bloatware
7. Runs SFC scan

**Duration:** 30-60 minutes
**Safety:** All operations are safely reversible

## API Reference

### Authentication
All API requests require `X-API-Key` header:
```
X-API-Key: your_api_key_here
```

### Endpoints

#### GET `/`
Service information and status.

#### GET `/health`
Health check endpoint.

#### GET `/system-info`
Get current system information (CPU, RAM, disks).

```json
{
  "device": {
    "cpu_name": "Intel Core i7-...",
    "cpu_cores": 8,
    "ram_total_mb": 16384,
    "ram_free_mb": 8192,
    "ram_percent": 50.0,
    "disks": [
      {
        "drive": "C",
        "total_gb": 238.5,
        "free_gb": 68.3,
        "used_percent": 71.4
      }
    ]
  }
}
```

#### GET `/smart-advice`
Get AI-generated optimization recommendations.

```json
{
  "advice": "🟢 RAM usage is healthy.\n🟡 Drive C: is 71.4% full. Schedule cleanup."
}
```

#### POST `/execute-tool`
Execute a system optimization tool.

**Request:**
```json
{
  "tool_name": "clean_temp",
  "params": {},
  "dry_run": true
}
```

**Response:**
```json
{
  "tool": "clean_temp",
  "status": "success",
  "dry_run": true,
  "result": "Cleaned 234 files, 1234.56 MB freed",
  "timestamp": "2024-03-10T12:34:56"
}
```

**Available Tools:**
- `clean_temp` - Clean temporary files
- `clean_browser` - Clean browser caches
- `clean_recycle` - Empty recycle bin
- `clean_registry` - Clean registry
- `defrag` - Defragment drive (params: drive)
- `trim` - TRIM SSD (params: drive)
- `scan_disk` - Scan disk (params: drive, fix_errors)
- `wipe_free` - Wipe free space (params: drive)
- `disable_telemetry` - Disable telemetry
- `disable_tracking` - Disable privacy tracking
- `remove_bloatware` - Remove bloatware
- `sfc_scan` - Run SFC scan
- `dism_repair` - Run DISM repair
- `driver_scan` - Scan for driver updates
- `smart_boost` - Run smart boost

#### POST `/smart-boost`
Execute comprehensive smart boost optimization.

**Request:**
```json
{
  "dry_run": true
}
```

**Response:**
```json
{
  "operation": "smart-boost",
  "status": "success",
  "dry_run": true,
  "result": "✓ Step 1: Cleaned temp files\n✓ Step 2: Cleaned browser cache\n...",
  "timestamp": "2024-03-10T12:34:56"
}
```

## Configuration

### Environment Variables
Create `.env` file in `backend/` directory:

```env
# HuggingFace (optional, for AI features)
HF_TOKEN=hf_your_token_here
HF_MODEL_ID=Qwen/Qwen2.5-7B-Instruct

# Supabase (optional, for cloud features)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your_anon_key

# API Security
CLIENT_API_KEY=your_secure_random_key

# Application
APP_ENV=production
APP_HOST=0.0.0.0
APP_PORT=7860
```

### Startup Configuration
Edit batch files to customize:
- `start_backend.bat` - Backend server settings
- `start_ui.bat` - UI server settings

## Monitoring & Logging

### Log Files
Located in `d:\NeoOptimize\logs\`:
- `neoai_backend.log` - Backend operations
- `windows_cmd_executor.log` - System commands
- `smoke-elevated-full.log` - Audit logs

### Monitoring Endpoints
- Backend health: `http://localhost:7860/health`
- Gradio status: `http://localhost:7861/`

### System Monitor
Automatic monitoring thread runs:
- Every 60 seconds: System health checks
- RAM > 85%: Trigger memory cleanup
- Disk > 90%: Warning and recommendation
- Provides real-time proactive advice

## Safety Features

### Dry-Run Mode
All destructive operations support dry-run mode:
- Preview what would be deleted
- No actual changes made
- Perfect for testing

### Reversible Operations
Most operations are reversible:
- Cleaned files can be recovered from recycle bin
- Registry has automatic backups
- System restore points before major changes

### API Key Authentication
- All API endpoints require valid API key
- Prevents unauthorized access
- Configurable in `.env`

### Command Logging
- All executed commands are logged
- Timestamps and results recorded
- Audit trail for compliance

## Best Practices

1. **Always use dry-run first** for new operations
2. **Create system restore point** before major changes
3. **Back up important data** before defrag/wipe operations
4. **Run SFC regularly** (monthly) for system health
5. **Monitor smart advice** for optimization opportunities
6. **Schedule Smart Boost** during off-hours
7. **Keep logs** for troubleshooting and auditing
8. **Update HF token** for real AI capabilities

## Troubleshooting

### Backend won't start
1. Check Python version: `python --version` (needs 3.10+)
2. Check dependencies: `pip install -r requirements-neoai.txt`
3. Check .env file exists and has valid format
4. Check port 7860 is not in use: `netstat -ano | findstr :7860`

### UI can't connect to backend
1. Verify backend is running: `http://localhost:7860/health`
2. Check API key in UI matches .env setting
3. Check firewall allows localhost:7860
4. Check network connectivity

### Tool execution fails
1. Requires administrator privileges - run as admin
2. Check disk space for cleanup operations
3. Check Windows updates are current
4. Check system files integrity with SFC

### High system usage during operations
1. This is normal during:
   - Defragmentation (HDD)
   - SFC scan
   - DISM repair
   - Free space wipe
2. Avoid other heavy tasks during these operations
3. Operations can take several hours
4. Safe to pause operations if needed

## Performance Optimization

### Recommended Schedule
- **Daily:** Smart Boost (off-hours)
- **Weekly:** SFC scan, registry cleanup
- **Monthly:** DISM repair, defrag (HDD) or TRIM (SSD)
- **Quarterly:** Full disk wipe free space

### System Resource Usage
- Backend: ~150-200 MB RAM
- UI: ~100-150 MB RAM
- Total: ~300 MB baseline
- Increases during operations (defrag, SFC, DISM)

## Support & Contributing

For issues, suggestions, or contributions:
1. Check logs in `d:\NeoOptimize\logs\`
2. Review error messages in backend response
3. Try dry-run mode to isolate issues
4. Consult Windows system logs: `Event Viewer`

## License & Legal

Neo Optimize AI is provided as-is for system optimization.
All operations are performed with your explicit consent.
Always review changes before executing real operations.

---

**Version:** 1.0.0  
**Last Updated:** March 10, 2026  
**Status:** Production Ready
