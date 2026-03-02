Create elevated scheduled task for NeoOptimize backend

Usage (run PowerShell as Administrator):

```powershell
# Create task (example):
.\create_elevated_task.ps1 -InstallPath 'D:\NeoOptimize' -NodeExe 'C:\Program Files\nodejs\node.exe'

# Remove task:
schtasks /Delete /TN NeoOptimize_Backend /F
```

Notes:
- This helper uses `schtasks` to create a logon task running with highest privileges.
- It avoids bundling third-party helpers (nssm). For a production installer, using an actual Windows Service wrapper is recommended.
