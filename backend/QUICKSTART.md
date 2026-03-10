# Neo Optimize AI - Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Step 1: Install Python (if not already installed)
Download and install Python 3.10+ from https://www.python.org

Verify installation:
```bash
python --version
```

### Step 2: Navigate to Backend Directory
```bash
cd d:\NeoOptimize\backend
```

### Step 3: Start the Backend Server
**Option A (Recommended - Automatic Setup):**
```bash
start_backend.bat
```

**Option B (Manual):**
```bash
pip install -r requirements-neoai.txt
python neoai_backend.py
```

You should see:
```
INFO:NeoOptimizeAI:=== Neo AI Backend Starting ===
INFO:NeoOptimizeAI:Supabase client initialized
INFO:NeoOptimizeAI:SystemMonitor started
INFO:NeoOptimizeAI:Starting Neo Optimize AI backend...
```

The backend is ready when you see:
```
INFO:     Application startup complete [uvicorn]
```

**Backend URL:** http://localhost:7860

### Step 4: Open New Terminal and Start UI
```bash
cd d:\NeoOptimize\backend
start_ui.bat
```

Or manually:
```bash
python gradio_ui.py
```

The UI will launch automatically in your browser.

**UI URL:** http://localhost:7861

### Step 5: Start Optimizing!

#### 👆 Quick Actions:
1. **System Monitor Tab** - View system health
2. **Cleaners Tab** - Clean junk files
3. **Smart Boost Tab** - One-click optimization

---

## 📋 Common Operations

### Clean Temporary Files
1. Go to **Cleaners** tab
2. Select "Dry Run" to preview
3. Click "Clean Temp Files"
4. Review results
5. Change to "Execute" and run again for actual cleanup

### Optimize Disk
1. Go to **Defragmentation & TRIM** tab
2. Select drive (C, D, etc.)
3. Choose operation:
   - **HDD:** Select "Defragment" (takes 1-24 hours)
   - **SSD:** Select "Run TRIM" (takes 10-30 minutes)
4. Click button and wait

### Run Full Optimization
1. Go to **Smart Boost** tab
2. Select "Preview" mode first
3. Click "START SMART BOOST"
4. Review all operations that will run
5. Change to "Execute" mode
6. Click "START SMART BOOST" again

---

## 🔧 Configuration

### Update HuggingFace Token (for real AI)
1. Get token from https://huggingface.co/settings/tokens
2. Edit `backend\.env`
3. Replace:
   ```
   HF_TOKEN=hf_placeholder_token_for_testing
   ```
   With your actual token:
   ```
   HF_TOKEN=hf_your_real_token_here
   ```
4. Restart backend (Ctrl+C, then run again)

### Custom API Key
1. Edit `backend\.env`
2. Change:
   ```
   CLIENT_API_KEY=dev_key_12345
   ```
   To your secure key:
   ```
   CLIENT_API_KEY=your_very_secure_key_xyz
   ```

---

## 📊 Monitoring

### Check System Health
1. Go to **System Monitor** tab
2. Click **Refresh System Info**
3. View:
   - RAM usage
   - Disk space
   - Overall health status

### Get Smart Advice
- Appears automatically on **Cleaners** and **Smart Boost** tabs
- Provides recommendations based on current system state

### View Logs
```bash
# Backend logs
type d:\NeoOptimize\logs\neoai_backend.log

# Command execution logs  
type d:\NeoOptimize\logs\windows_cmd_executor.log

# View last 50 lines
powershell -Command "Get-Content 'd:\NeoOptimize\logs\neoai_backend.log' -Tail 50"
```

---

## ⚙️ API Usage

### Direct API Calls
Call the API directly from scripts or other applications:

```bash
# Check system info
curl -H "X-API-Key: dev_key_12345" http://localhost:7860/system-info

# Get advice
curl -H "X-API-Key: dev_key_12345" http://localhost:7860/smart-advice

# Run tool
curl -X POST http://localhost:7860/execute-tool \
  -H "X-API-Key: dev_key_12345" \
  -H "Content-Type: application/json" \
  -d @- << 'EOF'
{
  "tool_name": "clean_temp",
  "dry_run": true
}
EOF
```

### API Documentation
Full API docs available at: http://localhost:7860/docs

---

## 🔒 Safety Tips

### ✅ DO:
- Use **Dry Run mode** first for new operations
- Create **system restore point** before major changes
- Review **Smart Advice** recommendations
- Keep **backups** of important data
- Read **operation results** carefully

### ❌ DON'T:
- Skip dry-run mode on unknown operations
- Run multiple heavy operations simultaneously
- Wipe free space if you might need data recovery
- Disable critical system services
- Make changes without backup

---

## 🆘 Troubleshooting

### Backend won't start
```bash
# Check Python
python --version

# Check port
netstat -ano | findstr :7860

# Install dependencies
pip install -r requirements-neoai.txt --upgrade

# Run with verbose output
python neoai_backend.py
```

### UI can't connect
```bash
# Test backend is running
curl http://localhost:7860/health

# Check firewall
netstat -ano | findstr LISTENING

# Restart backend and UI
```

### Operation fails
1. Run as administrator (right-click Command Prompt → Run as admin)
2. Check disk space: `Disk Management` or `Properties`
3. Check Windows updates are current
4. Try SFC scan: `sfc /scannow`

### High CPU during operation
This is normal for:
- Defragmentation
- SFC scan
- DISM repair
- Free space wipe
Safe to pause if needed.

---

## 📈 Next Steps

### After First Run:
1. ✅ Test clean operations (Cleaners tab)
2. ✅ Review Smart Advice
3. ✅ Try Smart Boost preview
4. ✅ Check system info regularly

### Optimization Schedule:
1. **Daily:** Monitor system info
2. **Weekly:** Run Smart Boost (off-hours)
3. **Monthly:** Run SFC scan + DISM repair
4. **Quarterly:** Full defrag/TRIM + wipe free space

### Integration with Desktop App:
Integrate Neo AI with main NeoOptimize desktop app:
- Use API endpoints from WebView
- Call Smart Boost from menu buttons
- Display system monitor data in dashboard

---

## 📞 Support

For detailed information:
- **Full Documentation:** `README_NEOAI.md`
- **API Reference:** `http://localhost:7860/docs`
- **Logs:** `d:\NeoOptimize\logs\`
- **Issues:** Check logs and error messages

---

## 🎯 Key Features Overview

| Feature | What It Does | Time | Safety |
|---------|-------------|------|--------|
| Clean Temp | Remove temporary files | 1-5 min | Safe ✅ |
| Browser Cache | Clear browser caches | 1-2 min | Safe ✅ |
| Defrag (HDD) | Optimize disk layout | 1-24 hrs | Safe ✅ |
| TRIM (SSD) | Maintain SSD performance | 10-30 min | Essential ✅ |
| Scan Disk | Check for errors | 30 min - 2 hrs | Safe ✅ |
| Wipe Free Space | Secure erase | 2-8 hrs | Irreversible ⚠️ |
| SFC Scan | Repair system files | 15-60 min | Safe ✅ |
| DISM Repair | Deep system repair | 30-120 min | Safe ✅ |
| Remove Bloatware | Uninstall junk apps | 5-10 min | Reversible |
| Disable Telemetry | Privacy improvement | 1 min | Safe ✅ |
| Smart Boost | All-in-one optimization | 30-60 min | Safe ✅ |

---

**Ready to optimize? Start with Step 1 above!** 🚀
