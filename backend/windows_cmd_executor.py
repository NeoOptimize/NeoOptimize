"""
Neo Optimize AI - Windows Command Line Wrapper
Direct system operation executor (for backend command processing)
"""

import os
import sys
import subprocess
import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

# ============================================================
# SETUP
# ============================================================

log_dir = Path("d:/NeoOptimize/logs")
log_dir.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    filename=log_dir / "windows_cmd_executor.log",
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("WindowsCmdExecutor")

# ============================================================
# COMMAND EXECUTORS
# ============================================================

class WindowsCommandExecutor:
    """Execute Windows system commands with elevation when needed"""
    
    @staticmethod
    def run_elevated(command: str, timeout: int = 300) -> Dict[str, Any]:
        """Run command with administrator privileges"""
        try:
            # Create temporary batch file
            batch_file = log_dir / f"temp_cmd_{datetime.now().timestamp()}.bat"
            batch_file.write_text(f"@echo off\n{command}\nexit /b %errorlevel%")
            
            # Execute with elevation
            result = subprocess.run(
                ["powershell", "-Command", f"Start-Process -FilePath {batch_file} -Verb RunAs -Wait"],
                capture_output=True,
                text=True,
                timeout=timeout
            )
            
            # Clean up
            try:
                batch_file.unlink()
            except:
                pass
            
            return {
                "success": result.returncode == 0,
                "stdout": result.stdout,
                "stderr": result.stderr,
                "exit_code": result.returncode
            }
        except Exception as e:
            logger.error(f"Elevated execution error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def cleanup_temp_files(dry_run: bool = True) -> Dict[str, Any]:
        """Clean temporary files"""
        try:
            cmd = 'powershell -Command "'
            cmd += f'$temp1 = "$env:TEMP"; '
            cmd += f'$temp2 = "$env:SystemRoot\\Temp"; '
            cmd += f'$dirs = @($temp1, $temp2) | Where-Object {{Test-Path $_}}; '
            cmd += f'foreach ($dir in $dirs) {{ '
            if not dry_run:
                cmd += f'Remove-Item -Path "$dir\\*" -Force -Recurse -ErrorAction SilentlyContinue '
            cmd += f'}} '
            cmd += f'Write-Host "Cleanup completed"'
            cmd += '")'
            
            return WindowsCommandExecutor.run_elevated(cmd, timeout=300)
        except Exception as e:
            logger.error(f"Cleanup temp error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def defrag_drive(drive: str) -> Dict[str, Any]:
        """Defragment a drive"""
        try:
            cmd = f'powershell -Command "Optimize-Volume -DriveLetter {drive} -Defrag -Verbose"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=3600)
        except Exception as e:
            logger.error(f"Defrag error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def trim_ssd(drive: str) -> Dict[str, Any]:
        """TRIM an SSD drive"""
        try:
            cmd = f'powershell -Command "Optimize-Volume -DriveLetter {drive} -SlimFast -Verbose"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=600)
        except Exception as e:
            logger.error(f"TRIM error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def scan_disk(drive: str, fix: bool = False) -> Dict[str, Any]:
        """Scan disk for errors"""
        try:
            if fix:
                cmd = f'powershell -Command "Repair-Volume -DriveLetter {drive} -Scan -SpotFix"'
            else:
                cmd = f'powershell -Command "Repair-Volume -DriveLetter {drive} -Scan"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=3600)
        except Exception as e:
            logger.error(f"Disk scan error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def wipe_free_space(drive: str) -> Dict[str, Any]:
        """Wipe free disk space securely"""
        try:
            cmd = f'powershell -Command "cipher /w:{drive}:"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=7200)
        except Exception as e:
            logger.error(f"Wipe free space error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def run_sfc() -> Dict[str, Any]:
        """Run System File Checker"""
        try:
            cmd = f'powershell -Command "sfc /scannow"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=1800)
        except Exception as e:
            logger.error(f"SFC error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def run_dism() -> Dict[str, Any]:
        """Run DISM repair"""
        try:
            cmd = 'powershell -Command "DISM /Online /Cleanup-Image /RestoreHealth"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=1800)
        except Exception as e:
            logger.error(f"DISM error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def empty_recycle_bin() -> Dict[str, Any]:
        """Empty the recycle bin"""
        try:
            cmd = 'powershell -Command "Clear-RecycleBin -Force -Confirm:$false"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=60)
        except Exception as e:
            logger.error(f"Recycle bin clear error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def disable_service(service_name: str) -> Dict[str, Any]:
        """Disable a Windows service"""
        try:
            cmd = f'powershell -Command "Stop-Service -Name {service_name} -Force -ErrorAction SilentlyContinue; Set-Service -Name {service_name} -StartupType Disabled -ErrorAction SilentlyContinue"'
            return WindowsCommandExecutor.run_elevated(cmd, timeout=60)
        except Exception as e:
            logger.error(f"Service disable error: {e}")
            return {"success": False, "error": str(e)}
    
    @staticmethod
    def get_system_info() -> Dict[str, Any]:
        """Get system information"""
        try:
            cmd = 'powershell -Command "'
            cmd += '$os = Get-WmiObject Win32_OperatingSystem; '
            cmd += '$mem = Get-WmiObject Win32_ComputerSystem; '
            cmd += '$disks = Get-PSDrive -PSProvider FileSystem | Select-Object Name; '
            cmd += '@{OS=$os.Caption; RAM=[math]::Round($mem.TotalPhysicalMemory/1GB,2); Cores=$mem.NumberOfLogicalProcessors} | ConvertTo-Json'
            cmd += '")'
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )
            
            try:
                data = json.loads(result.stdout)
                return {"success": True, "data": data}
            except:
                return {"success": True, "stdout": result.stdout}
        except Exception as e:
            logger.error(f"System info error: {e}")
            return {"success": False, "error": str(e)}

# ============================================================
# MAIN EXECUTOR
# ============================================================

def execute_command(command_type: str, **kwargs) -> Dict[str, Any]:
    """Execute command by type"""
    
    command_map = {
        "cleanup_temp": lambda: WindowsCommandExecutor.cleanup_temp_files(kwargs.get("dry_run", True)),
        "defrag": lambda: WindowsCommandExecutor.defrag_drive(kwargs.get("drive", "C")),
        "trim": lambda: WindowsCommandExecutor.trim_ssd(kwargs.get("drive", "C")),
        "scan_disk": lambda: WindowsCommandExecutor.scan_disk(
            kwargs.get("drive", "C"), 
            kwargs.get("fix", False)
        ),
        "wipe_free": lambda: WindowsCommandExecutor.wipe_free_space(kwargs.get("drive", "C")),
        "sfc": lambda: WindowsCommandExecutor.run_sfc(),
        "dism": lambda: WindowsCommandExecutor.run_dism(),
        "recycle": lambda: WindowsCommandExecutor.empty_recycle_bin(),
        "disable_service": lambda: WindowsCommandExecutor.disable_service(kwargs.get("service", "DiagTrack")),
        "system_info": lambda: WindowsCommandExecutor.get_system_info(),
    }
    
    try:
        executor = command_map.get(command_type)
        if not executor:
            return {"success": False, "error": f"Unknown command: {command_type}"}
        
        logger.info(f"Executing: {command_type}")
        result = executor()
        logger.info(f"Result: {result.get('success', False)}")
        
        return result
    except Exception as e:
        logger.error(f"Command execution error: {e}")
        return {"success": False, "error": str(e)}

# ============================================================
# CLI INTERFACE
# ============================================================

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python windows_cmd_executor.py <command> [options]")
        print("\nAvailable commands:")
        print("  cleanup_temp [--dry-run]")
        print("  defrag --drive C")
        print("  trim --drive C")
        print("  scan_disk --drive C [--fix]")
        print("  wipe_free --drive C")
        print("  sfc")
        print("  dism")
        print("  recycle")
        print("  disable_service --service DiagTrack")
        print("  system_info")
        sys.exit(1)
    
    command = sys.argv[1]
    kwargs = {}
    
    for i in range(2, len(sys.argv), 2):
        if sys.argv[i].startswith("--"):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv):
                kwargs[key] = sys.argv[i + 1]
            else:
                kwargs[key] = True
    
    result = execute_command(command, **kwargs)
    print(json.dumps(result, indent=2))
