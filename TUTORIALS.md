# Neo Optimize AI - Tutorials & Guides

Complete step-by-step tutorials for all Neo Optimize AI features.

---

## 📋 Table of Contents

1. [Getting Started (5 minutes)](#1-getting-started-5-minutes)
2. [First Optimization (10 minutes)](#2-first-optimization-10-minutes)
3. [System Cleaning Deep Dive](#3-system-cleaning-deep-dive)
4. [Defragmentation & SSD Optimization](#4-defragmentation--ssd-optimization)
5. [Privacy & Security Hardening](#5-privacy--security-hardening)
6. [Advanced Features](#6-advanced-features)
7. [Troubleshooting](#7-troubleshooting)
8. [Integration with Desktop Apps](#8-integration-with-desktop-apps)

---

## 1. Getting Started (5 minutes)

### Prerequisites
- Windows 10/11/12
- Python 3.10+
- 500 MB free disk space
- Administrator account (for some features)

### Installation Steps

**Step 1: Download & Install**
```bash
# Clone the repository
git clone https://github.com/NeoOptimize/NeoOptimize.git
cd NeoOptimize\backend
```

**Step 2: Automatic Setup (Easiest)**
```bash
# Run this command in Command Prompt or PowerShell
start_backend.bat

# Then in a NEW terminal window:
start_ui.bat

# Your browser should automatically open http://localhost:7861
```

**Step 3: Manual Setup (If Automatic Fails)**
```bash
# Create virtual environment
python -m venv venv
venv\Scripts\activate

# Install dependencies
pip install -r requirements-neoai.txt

# Create .env file
# (Copy from .env.example if it exists)

# Start backend
python neoai_backend.py

# In new terminal, start UI
python gradio_ui.py
```

**Step 4: Verify Installation**
1. Open http://localhost:7861 in your browser
2. Click "Refresh System Info" button
3. You should see your system metrics
4. You're ready to go! ✅

---

## 2. First Optimization (10 minutes)

### Your First Smart Boost

**Step 1: Navigate to Dashboard**
- Ensure http://localhost:7861 is open
- You should see the System Monitor tab

**Step 2: Check System Health**
- Click "**Refresh System Info**" button
- Review your current stats:
  - RAM usage
  - CPU cores
  - Disk space
  - Health indicators (🟢🟡🔴)

**Step 3: Review Smart Advice**
- Scroll down to see recommendations
- These are AI-powered suggestions based on your system

**Step 4: Run Smart Boost (Dry-run First)**
1. Go to "**Smart Boost**" tab
2. You should see "**Execute Mode**" toggle
3. Make sure it's in "Preview Mode" (shows dry-run)
4. Click "**Run Smart Boost**" button
5. Wait 30-60 seconds
6. Review what will be cleaned:
   - Temp files cleaned
   - Cache removed
   - Bloatware identified
   - etc.

**Step 5: Confirm & Execute**
1. If you're satisfied with the preview, toggle to "Execute Mode"
2. Click "**Run Smart Boost**" again
3. This time it will actually execute the operations
4. Progress will show on screen
5. ✅ Optimization complete!

**Step 6: Verify Results**
- Return to "System Monitor" tab
- Click "**Refresh System Info**" again
- You should notice:
  - More free RAM
  - More free disk space
  - Faster system response

---

## 3. System Cleaning Deep Dive

### Understanding Each Cleaner

#### 3A. Clean Temporary Files

**What it does:**
- Removes Windows temporary files
- Cleans browsing cache
- Removes application temp files
- Frees up 100 MB - 5 GB typically

**How to use:**
1. Go to "**Cleaners**" tab
2. Find "Clean Temp Files" section
3. Toggle "Dry-run Mode" to see what will be deleted
4. Click "Clean"
5. Review the report
6. Turn off dry-run and click again to actually delete

**Safety:** ✅ Completely safe - all files can be recreated

#### 3B. Clean Browser Cache

**What it does:**
- Removes cached web pages, images, videos
- Supports: Chrome, Edge, Firefox, Opera, Brave
- Frees up 500 MB - 10 GB typically
- Keeps login sessions and bookmarks

**How to use:**
1. Go to "**Cleaners**" tab
2. Find "Clean Browser Cache" section
3. Optionally select specific browser
4. Toggle dry-run to preview
5. Click "Clean"

**Safety:** ✅ Completely safe - caches will rebuild automatically

#### 3C. Clean Recycle Bin

**What it does:**
- Permanently deletes files in Recycle Bin
- Frees up space occupied by deleted files
- Cannot be undone (but files aren't truly erased)

**How to use:**
1. Go to "**Cleaners**" tab
2. Find "Empty Recycle Bin" section
3. Click "Clean"
4. Confirm when prompted

**Safety:** ⚠️ Cannot be easily undone, but data recovery is possible

#### 3D. Clean Registry

**What it does:**
- Removes obsolete Windows registry entries
- Removes unused app registrations
- Improves system stability
- Frees up minimal space (1-50 MB typically)

**How to use:**
1. Go to "**Cleaners**" tab
2. Find "Clean Registry" section
3. Toggle dry-run to see what will be removed
4. Click "Clean"

**Safety:** ✅ Only removes safe entries that won't break anything

#### 3E. Clean Prefetch

**What it does:**
- Clears Windows prefetch memory
- Speeds up startup times
- Improves application launch speed

**How to use:**
1. Go to "**Cleaners**" tab
2. Find "Clean Prefetch" section
3. Click "Clean"
4. Restart computer to see full benefits

**Safety:** ✅ Completely safe - rebuilt automatically

---

## 4. Defragmentation & SSD Optimization

### 4A. Defragmentation (for HDDs)

**When to defragment:**
- If you have a traditional hard drive (HDD)
- After deleting large files
- System feels sluggish
- Every 1-3 months

**How to defrag:**

1. Go to "**Defrag & TRIM**" tab
2. Select drive (usually C: or D:)
3. Click "**Analyze Drive**" first to check fragmentation
4. Toggle "**Dry-run**" to estimate time
5. Click "**Start Defragmentation**"
6. Wait 1-24 hours depending on drive size
   - 100 GB: ~2-4 hours
   - 500 GB: ~4-10 hours
   - 1 TB+: ~10-24 hours
7. Do NOT restart during defrag
8. ✅ Complete when finished

**Safety:** ✅ Completely safe - improves performance

### 4B. SSD TRIM (for SSDs)

**When to TRIM:**
- If you have a Solid State Drive (SSD)
- After deleting large files
- Monthly optimization
- To maintain SSD speed

**How to TRIM:**

1. Go to "**Defrag & TRIM**" tab
2. Select SSD drive (usually C: or D:)
3. Click "**Run TRIM**"
4. Takes 10-30 minutes
5. Do NOT turn off computer
6. ✅ Complete when finished

**Safety:** ✅ Essential for SSD performance

### 4C. Identify Your Drive Type

**Is your drive HDD or SSD?**

```
Windows 10/11/12:
1. Right-click "This PC" or "My Computer"
2. Click "Manage"
3. Click "Device Manager" (left sidebar)
4. Expand "Disks"
5. Look at your drive name:
   - Contains "SSD" = Solid State Drive
   - Contains "HDD" = Hard Drive
   - No label = Check Disk Properties
```

**Check via System Info:**
```powershell
# Open PowerShell and run:
Get-PhysicalDisk | Select-Object FriendlyName, MediaType

# Look for:
# SSD = Solid State Drive
# HDD = Hard Disk Drive
```

---

## 5. Privacy & Security Hardening

### 5A. Remove Bloatware

**What it removes:**
- Microsoft Edge (if not needed)
- Xbox Gaming Service
- Zune Music & Video
- OneDrive recommendations
- Cortana
- OneNote
- And 9+ more apps

**How to remove:**

1. Go to "**Privacy & Security**" tab
2. Find "Remove Bloatware" section
3. Review list in dry-run mode
4. Click "Remove Bloatware"
5. App uninstallation begins
6. Takes 5-10 minutes
7. ✅ Complete when finished

**After removal:**
- More free disk space (2-10 GB)
- Faster startup
- Less background processes
- Better performance

**Can you reinstall?**
✅ Yes! Use "Add/Remove Programs" anytime

### 5B. Disable Telemetry

**What it does:**
- Stops Windows telemetry service
- Prevents diagnostic data upload
- Improves privacy
- Slight performance boost

**How to disable:**

1. Go to "**Privacy & Security**" tab
2. Find "Disable Telemetry" section
3. Click "Disable"
4. Services will be stopped
5. Takes 1-2 minutes
6. ✅ Complete when finished

**What changes:**
- DiagTrack service disabled
- No diagnostic uploads
- Improved privacy
- No functional changes to Windows

**Can you re-enable?**
✅ Yes, but not recommended

### 5C. Disable Privacy Tracking

**What it does:**
- Disables Activity History
- Disables App Suggestions
- Blocks tracking ID
- Improves privacy

**How to disable:**

1. Go to "**Privacy & Security**" tab
2. Find "Disable Privacy Tracking" section
3. Click "Disable"
4. Registry entries modified
5. Takes 1-2 minutes
6. ✅ Complete when finished

**What improves:**
- Better privacy
- No targeted ads
- No activity logging
- No behavior tracking

---

## 6. Advanced Features

### 6A. Disk Scan & Repair

**What it does:**
- Scans drive for errors
- Repairs file system issues
- Checks disk health
- Prevents data loss

**How to scan:**

1. Go to "**Disk Scan**" tab
2. Select drive to scan
3. Click "**Scan Disk**" (dry-run mode)
   - Shows what needs fixing
   - Takes 30 min - 2 hours
4. Review results
5. Click "**Repair**" to fix errors
6. Takes 30 min - 2 hours
7. May require restart
8. ✅ Complete when finished

**Safety:** ✅ Completely safe - fixes problems

### 6B. Secure Free Space Wipe

**What it does:**
- Securely erases deleted files
- Multiple pass overwrite
- Prevents data recovery
- Very thorough (2-8 hours)

**How to wipe:**

1. Go to "**Disk Scan**" tab
2. Find "Wipe Free Space" section
3. Select drive
4. Click "**Wipe**"
5. Takes 2-8 hours depending on drive size
   - 100 GB: ~1 hour
   - 500 GB: ~3 hours
   - 1 TB: ~6 hours
6. Do NOT turn off during operation
7. ✅ Complete when finished

**Safety:** ⚠️ **Irreversible** - data will be unrecoverable

### 6C. System File Checker (SFC Scan)

**What it does:**
- Scans Windows system files
- Repairs corrupted files
- Fixes system stability issues
- Prevents crashes and errors

**How to scan:**

1. Go to "**System Health**" tab
2. Find "SFC Scan" section
3. Click "**Run SFC Scan**"
4. Takes 15-60 minutes
5. May show "Repairs made" or "No issues found"
6. May require restart
7. ✅ Complete when finished

**Results interpretation:**
- ✅ "No integrity violations" = All good
- ✅ "Repairs made" = Issues fixed
- ⚠️ "Unable to repair" = Contact support

### 6D. System Health Check (DISM)

**What it does:**
- Deep Windows image analysis
- Repairs system image
- Fixes major system issues
- More thorough than SFC

**How to scan:**

1. Go to "**System Health**" tab
2. Find "DISM Repair" section
3. Click "**Run DISM**"
4. Takes 30-120 minutes
5. Do NOT interrupt
6. May require restart
7. ✅ Complete when finished

**When to use:**
- After SFC found issues
- System won't start
- Frequent blue screens
- Major stability issues

---

## 7. Troubleshooting

### 7A. Backend Won't Start

**Problem:** `start_backend.bat` runs but closes immediately

**Solutions:**
```bash
# 1. Check Python version
python --version
# Must be 3.10 or higher

# 2. Check dependencies
pip install -r requirements-neoai.txt

# 3. Check port availability
netstat -ano | findstr :7860
# If in use, kill it or change port

# 4. Run with detailed errors
python neoai_backend.py
# Look for error message
```

### 7B. UI Can't Connect to Backend

**Problem:** Web interface shows "Connection Error"

**Solutions:**
```bash
# 1. Verify backend is running
# Should see "Application startup complete" message

# 2. Test backend health
curl http://localhost:7860/health

# 3. Check firewall
netstat -ano | findstr LISTENING
# Should show port 7860 in use

# 4. Restart both services
# Close both start_backend.bat and start_ui.bat
# Run them again

# 5. Kill stuck processes
taskkill /F /IM python.exe
# Then restart
```

### 7C. Operations Fail with "Permission Denied"

**Problem:** Operations fail with permission/elevation errors

**Solutions:**
1. Run as Administrator
   - Right-click Command Prompt → "Run as administrator"
   - Then run `start_backend.bat`
2. Add user to admin group
3. Retry operation
4. Check Windows permissions

### 7D. High Memory/CPU Usage

**Problem:** Neo Optimize causes high resource usage

**Solutions:**
1. Run one operation at a time
2. Avoid running multiple tabs simultaneously
3. Don't run defrag and TRIM together
4. Reduce browser tabs
5. Wait for current operation to complete

### 7E. Disk Space Shows Incorrect

**Problem:** Reported free space doesn't match Windows

**Solutions:**
1. Refresh System Info (may show cached value)
2. Run "Clean All" to free space
3. Empty Recycle Bin
4. Check for hidden files (`Ctrl+H` in File Explorer)

---

## 8. Integration with Desktop Apps

### 8A. JavaScript Integration (WebView2)

For HTML-based desktop applications:

```javascript
// Import the client
<script src="neoai-client.js"></script>

// Create client instance
const neoAI = new NeoAIClient('http://localhost:7860', 'dev_key_12345');

// Get system info
neoAI.getSystemInfo().then(info => {
    console.log(`RAM: ${info.device.ram_percent}%`);
    console.log(`Disk: ${info.device.disks[0].used_percent}%`);
});

// Run a tool
neoAI.executeTool('clean_temp', {}, true).then(result => {
    console.log(result);
});

// Run smart boost
neoAI.smartBoost(true).then(result => {
    console.log(`Optimization preview: ${result}`);
});
```

See [Integration Guide](./docs/INTEGRATION.md) for complete examples.

### 8B. C# Integration (WPF)

For C# desktop applications:

```csharp
using NeoOptimizeAI;

// Create service instance
var neoAI = new NeoAIBackendService();

// Check health
bool isHealthy = await neoAI.HealthCheckAsync();

// Get system info
var info = await neoAI.GetSystemInfoAsync();
Console.WriteLine($"RAM: {info["device"]["ram_percent"]}%");

// Run tool
var result = await neoAI.ExecuteToolAsync("clean_temp", new {}, true);

// Run optimization
var boost = await neoAI.SmartBoostAsync(dryRun: true);
```

See [Integration Guide](./docs/INTEGRATION.md) for complete examples.

---

## 📚 Additional Resources

- [📖 Full Documentation](./README_NEOAI.md)
- [⚡ Quick Start](./QUICKSTART.md)
- [🔗 Integration Guide](./INTEGRATION.md)
- [🔌 API Reference](./API_REFERENCE.md)
- [❓ FAQ](./FAQ.md)
- [🆘 Troubleshooting](./TROUBLESHOOTING.md)

---

## 💡 Pro Tips

1. **Always use dry-run first** - See what will happen before executing
2. **Create restore point before major operations** - Allows easy rollback
3. **Schedule cleaners weekly** - Maintain peak performance
4. **Monitor system health daily** - Catch issues early
5. **Update dependencies monthly** - Security improvements
6. **Review logs after operations** - Verify everything worked
7. **Backup important data** - Before disk operations
8. **Close applications during optimization** - For best results

---

## 🎯 Recommended Schedule

### Daily
- Monitor System Health (1 minute)
- Review Smart Advice

### Weekly
- Clean Temp Files (5 minutes)
- Clean Browser Cache (3 minutes)
- Run Smart Boost (30-60 minutes)

### Monthly
- HDD Defragmentation (hours)
- SSD TRIM (30 minutes)
- SFC Scan (30-60 minutes)
- Registry Cleanup (5 minutes)

### Quarterly
- Full Disk Scan (hours)
- Secure Free Space Wipe (hours)
- DISM Repair (30-120 minutes)
- Update Windows

---

<div align="center">

### 🎓 Ready to Optimize?

Start with [Tutorial 1: Getting Started](#1-getting-started-5-minutes)

Then proceed to [Tutorial 2: First Optimization](#2-first-optimization-10-minutes)

</div>
