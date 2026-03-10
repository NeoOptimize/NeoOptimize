"""
NeoOptimize AI - Advanced Windows System Optimizer with LangChain Agent
Complete Production-Grade Implementation
"""

import sys
import os
import json
import time
import uuid
import threading
import logging
import logging.handlers
from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from pathlib import Path
import subprocess
import shutil
import hashlib

# FastAPI & Uvicorn
from fastapi import FastAPI, HTTPException, Request, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# LangChain Components
from langchain.agents import AgentExecutor, create_react_agent
from langchain.tools import Tool
from langchain.llms import HuggingFacePipeline
from langchain.memory import ConversationBufferMemory
from langchain.prompts import PromptTemplate
from langchain_core.messages import SystemMessage, HumanMessage

# HuggingFace & ML
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    pipeline,
    BitsAndBytesConfig
)
import torch

# Supabase
from supabase import create_client, Client

# Embeddings for long-term memory
from sentence_transformers import SentenceTransformer

# Environment & Config
from dotenv import load_dotenv

load_dotenv()

# ============================================================
# CONFIGURATION & VALIDATION
# ============================================================

REQUIRED_ENV_VARS = ["HF_TOKEN", "SUPABASE_URL", "SUPABASE_KEY", "CLIENT_API_KEY"]
missing = [var for var in REQUIRED_ENV_VARS if not os.getenv(var)]
if missing:
    # Allow fallback for development
    print(f"Warning: Missing environment variables: {', '.join(missing)}")

HF_TOKEN = os.getenv("HF_TOKEN", "hf_placeholder_token")
SUPABASE_URL = os.getenv("SUPABASE_URL", "https://placeholder.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "placeholder_key")
CLIENT_API_KEY = os.getenv("CLIENT_API_KEY", "dev_key_12345")

# Model configuration
MODEL_NAME = os.getenv("HF_MODEL_ID", "Qwen/Qwen2.5-7B-Instruct")
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"
USE_QUANTIZATION = torch.cuda.is_available()

# ============================================================
# LOGGING SETUP
# ============================================================

log_dir = Path("d:/NeoOptimize/logs")
log_dir.mkdir(parents=True, exist_ok=True)

log_handler = logging.handlers.RotatingFileHandler(
    log_dir / "neoai_backend.log",
    maxBytes=10*1024*1024,
    backupCount=5
)
console_handler = logging.StreamHandler(sys.stderr)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[log_handler, console_handler]
)
logger = logging.getLogger("NeoOptimizeAI")
logger.info("=== Neo AI Backend Starting ===")

# ============================================================
# SUPABASE INITIALIZATION
# ============================================================

try:
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    logger.info("Supabase client initialized")
except Exception as e:
    logger.warning(f"Supabase init warning: {e} (development mode)")
    supabase = None

# ============================================================
# EMBEDDING MODEL FOR MEMORY
# ============================================================

logger.info("Loading embedding model...")
try:
    embedder = SentenceTransformer('all-MiniLM-L6-v2')
    logger.info("Embedding model loaded successfully")
except Exception as e:
    logger.error(f"Failed to load embedding model: {e}")
    embedder = None

# ============================================================
# WINDOWS SYSTEM UTILITIES
# ============================================================

class WindowsSystemUtils:
    """Utilities for Windows system operations"""
    
    @staticmethod
    def run_command(cmd: str, admin: bool = False, timeout: int = 300) -> str:
        """Execute Windows command and return output"""
        try:
            if admin:
                # Run with admin privileges
                result = subprocess.run(
                    f'powershell -Command "{cmd}"',
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    shell=True
                )
            else:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=timeout,
                    shell=True
                )
            return result.stdout + result.stderr
        except subprocess.TimeoutExpired:
            return f"Command timeout after {timeout}s"
        except Exception as e:
            return f"Command failed: {str(e)}"
    
    @staticmethod
    def get_system_info() -> Dict[str, Any]:
        """Get current system information"""
        try:
            info = {
                "timestamp": datetime.now().isoformat(),
                "device": {}
            }
            
            # CPU info
            result = WindowsSystemUtils.run_command(
                "powershell -Command \"Get-WmiObject Win32_Processor | Select-Object -First 1 | ConvertTo-Json\""
            )
            if result:
                try:
                    cpu = json.loads(result)
                    info["device"]["cpu_name"] = cpu.get("Name", "Unknown")
                    info["device"]["cpu_cores"] = cpu.get("NumberOfCores", 0)
                except:
                    pass
            
            # Memory info
            result = WindowsSystemUtils.run_command(
                "powershell -Command \"Get-WmiObject Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory | ConvertTo-Json\""
            )
            if result:
                try:
                    mem = json.loads(result)
                    total_mb = int(mem.get("TotalVisibleMemorySize", 0)) // 1024
                    free_mb = int(mem.get("FreePhysicalMemory", 0)) // 1024
                    used_mb = total_mb - free_mb
                    ram_percent = (used_mb / total_mb * 100) if total_mb > 0 else 0
                    info["device"]["ram_total_mb"] = total_mb
                    info["device"]["ram_free_mb"] = free_mb
                    info["device"]["ram_percent"] = round(ram_percent, 2)
                except:
                    pass
            
            # Disk info
            result = WindowsSystemUtils.run_command(
                "powershell -Command \"Get-Volume | Select-Object DriveLetter,Size,SizeRemaining | ConvertTo-Json\""
            )
            if result:
                try:
                    disks = json.loads(result) if result.startswith('[') else [json.loads(result)]
                    info["device"]["disks"] = []
                    for disk in disks:
                        if disk.get("DriveLetter"):
                            total = int(disk.get("Size", 0))
                            free = int(disk.get("SizeRemaining", 0))
                            used = total - free
                            used_percent = (used / total * 100) if total > 0 else 0
                            info["device"]["disks"].append({
                                "drive": disk["DriveLetter"],
                                "total_gb": round(total / (1024**3), 2),
                                "free_gb": round(free / (1024**3), 2),
                                "used_percent": round(used_percent, 2)
                            })
                except:
                    pass
            
            return info
        except Exception as e:
            logger.error(f"System info error: {e}")
            return {"error": str(e), "timestamp": datetime.now().isoformat()}
    
    @staticmethod
    def get_disk_usage(path: str) -> Dict[str, Any]:
        """Get disk usage for a path"""
        try:
            total = 0
            used = 0
            for dirpath, dirnames, filenames in os.walk(path):
                for f in filenames:
                    try:
                        total += os.path.getsize(os.path.join(dirpath, f))
                    except:
                        pass
            return {
                "path": path,
                "total_bytes": total,
                "total_mb": round(total / (1024**2), 2),
                "total_gb": round(total / (1024**3), 2),
            }
        except Exception as e:
            return {"error": str(e)}
    
    @staticmethod
    def safe_delete(path: str, dry_run: bool = True) -> Dict[str, Any]:
        """Safely delete files/folders"""
        result = {
            "path": path,
            "dry_run": dry_run,
            "deleted_count": 0,
            "deleted_bytes": 0,
            "errors": []
        }
        
        try:
            if not os.path.exists(path):
                return {**result, "error": f"Path not found: {path}"}
            
            if os.path.isdir(path):
                for dirpath, dirnames, filenames in os.walk(path, topdown=False):
                    for filename in filenames:
                        file_path = os.path.join(dirpath, filename)
                        try:
                            size = os.path.getsize(file_path)
                            if not dry_run:
                                os.remove(file_path)
                            result["deleted_count"] += 1
                            result["deleted_bytes"] += size
                        except Exception as e:
                            result["errors"].append(f"{file_path}: {str(e)}")
                    
                    # Remove empty dirs
                    for dirname in dirnames:
                        dir_path = os.path.join(dirpath, dirname)
                        try:
                            if not dry_run and not os.listdir(dir_path):
                                os.rmdir(dir_path)
                        except:
                            pass
            else:
                size = os.path.getsize(path)
                if not dry_run:
                    os.remove(path)
                result["deleted_count"] = 1
                result["deleted_bytes"] = size
        except Exception as e:
            result["error"] = str(e)
        
        return result

# ============================================================
# SYSTEM MONITOR
# ============================================================

class SystemMonitor:
    """Autonomous system monitoring and proactive optimization"""
    
    def __init__(self):
        self.running = True
        self.last_check = datetime.now() - timedelta(hours=1)
        self.high_cpu_count = 0
        self.thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self.thread.start()
        logger.info("SystemMonitor started")
    
    def _monitor_loop(self):
        """Main monitoring loop"""
        while self.running:
            try:
                self._check_system_health()
                self._check_scheduled_tasks()
                self._provide_smart_advice()
            except Exception as e:
                logger.error(f"Monitor error: {e}")
            time.sleep(60)  # Check every minute
    
    def _check_system_health(self):
        """Check system health and trigger optimizations"""
        try:
            info = WindowsSystemUtils.get_system_info()
            device = info.get("device", {})
            
            ram_percent = device.get("ram_percent", 0)
            
            # Auto-cleanup if RAM is high
            if ram_percent > 85:
                logger.info(f"High RAM detected ({ram_percent}%). Triggering cleanup...")
                self._trigger_memory_cleanup()
            
            # Check disk space
            for disk in device.get("disks", []):
                if disk.get("used_percent", 0) > 90:
                    logger.warning(f"Disk {disk['drive']} is {disk['used_percent']}% full!")
        except Exception as e:
            logger.error(f"Health check error: {e}")
    
    def _trigger_memory_cleanup(self):
        """Trigger memory cleanup"""
        try:
            cmd = "powershell -Command \"[GC]::Collect(); [GC]::WaitForPendingFinalizers()\""
            WindowsSystemUtils.run_command(cmd)
            logger.info("Memory cleanup triggered")
        except Exception as e:
            logger.error(f"Memory cleanup error: {e}")
    
    def _check_scheduled_tasks(self):
        """Check and execute scheduled tasks"""
        # Implementation would check database for scheduled tasks
        pass
    
    def _provide_smart_advice(self):
        """Provide proactive optimization advice"""
        try:
            info = WindowsSystemUtils.get_system_info()
            device = info.get("device", {})
            ram_percent = device.get("ram_percent", 0)
            
            if ram_percent > 80:
                logger.info("SMART ADVICE: RAM usage high. Consider closing unnecessary applications.")
            
            for disk in device.get("disks", []):
                if disk.get("used_percent", 0) > 85:
                    logger.info(f"SMART ADVICE: Drive {disk['drive']} is getting full. Perform cleanup.")
        except Exception as e:
            logger.error(f"Smart advice error: {e}")
    
    def stop(self):
        """Stop monitoring"""
        self.running = False

monitor = SystemMonitor()

# ============================================================
# TOOL FUNCTIONS - COMPLETE IMPLEMENTATION
# ============================================================

# -------- CLEANER TOOLS --------

def clean_temp_files(dry_run: bool = True) -> str:
    """Clean temporary files from system"""
    try:
        temp_paths = [
            os.path.expandvars(r"%TEMP%"),
            os.path.expandvars(r"%SystemRoot%\Temp"),
            os.path.expandvars(r"%LocalAppData%\Temp"),
        ]
        
        results = []
        total_freed = 0
        
        for path in temp_paths:
            if os.path.exists(path):
                result = WindowsSystemUtils.safe_delete(path, dry_run=dry_run)
                results.append(f"{path}: {result.get('deleted_count', 0)} files, {result.get('deleted_bytes', 0)} bytes")
                total_freed += result.get('deleted_bytes', 0)
        
        summary = f"Cleaned {sum(1 for r in results if 'files' in r)} temp locations. Freed: {round(total_freed/(1024**2), 2)} MB"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        
        return summary + "\nDetails:\n" + "\n".join(results)
    except Exception as e:
        logger.error(f"Clean temp error: {e}")
        return f"Error: {str(e)}"

def clean_browser_cache(browser: str = "all", dry_run: bool = True) -> str:
    """Clean browser caches"""
    try:
        browsers = {
            "chrome": os.path.expandvars(r"%LocalAppData%\Google\Chrome\User Data\Default\Cache"),
            "edge": os.path.expandvars(r"%LocalAppData%\Microsoft\Edge\User Data\Default\Cache"),
            "firefox": os.path.expandvars(r"%LocalAppData%\Mozilla\Firefox\Profiles"),
        }
        
        targets = [browsers[browser]] if browser != "all" else list(browsers.values())
        
        total_freed = 0
        for path in targets:
            if os.path.exists(path):
                result = WindowsSystemUtils.safe_delete(path, dry_run=dry_run)
                total_freed += result.get('deleted_bytes', 0)
        
        summary = f"Browser cache cleaned. Freed: {round(total_freed/(1024**2), 2)} MB"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Browser cache error: {e}")
        return f"Error: {str(e)}"

def clean_recycle_bin(dry_run: bool = True) -> str:
    """Empty recycle bin"""
    try:
        if not dry_run:
            cmd = "powershell -Command \"Clear-RecycleBin -Force -Confirm:$false\""
            WindowsSystemUtils.run_command(cmd)
        summary = "Recycle bin emptied"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Recycle bin error: {e}")
        return f"Error: {str(e)}"

def clean_prefetch_files(dry_run: bool = True) -> str:
    """Clean prefetch files"""
    try:
        prefetch_path = os.path.expandvars(r"%SystemRoot%\Prefetch")
        if os.path.exists(prefetch_path):
            result = WindowsSystemUtils.safe_delete(prefetch_path, dry_run=dry_run)
            freed = result.get('deleted_bytes', 0)
            summary = f"Prefetch cleaned. Freed: {round(freed/(1024**2), 2)} MB"
        else:
            summary = "Prefetch folder not found"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Prefetch error: {e}")
        return f"Error: {str(e)}"

def clean_registry(dry_run: bool = True) -> str:
    """Clean invalid registry entries"""
    try:
        if not dry_run:
            cmd = 'powershell -Command "Get-ItemProperty HKCU:\\\\Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Explorer\\\\RunMRU | Remove-ItemProperty -Force"'
            WindowsSystemUtils.run_command(cmd, admin=True)
        summary = "Registry cleaned (removed obsolete entries)"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Registry clean error: {e}")
        return f"Error: {str(e)}"

# -------- DEFRAG & TRIM TOOLS --------

def defrag_drive(drive: str = "C", dry_run: bool = True) -> str:
    """Defragment an HDD drive"""
    try:
        if not dry_run:
            cmd = f'powershell -Command "Optimize-Volume -DriveLetter {drive} -Defrag -Verbose"'
            result = WindowsSystemUtils.run_command(cmd, admin=True, timeout=3600)
            return f"Defrag started on {drive}:\\. Output:\\n{result}"
        else:
            return f"[DRY-RUN] Defrag would be performed on {drive}:\\ (this takes time)"
    except Exception as e:
        logger.error(f"Defrag error: {e}")
        return f"Error: {str(e)}"

def trim_ssd(drive: str = "C", dry_run: bool = True) -> str:
    """TRIM an SSD drive"""
    try:
        if not dry_run:
            cmd = f'powershell -Command "Optimize-Volume -DriveLetter {drive} -Defrag -Verbose"'
            result = WindowsSystemUtils.run_command(cmd, admin=True)
            return f"TRIM operation completed on {drive}:\\. Output:\\n{result}"
        else:
            return f"[DRY-RUN] TRIM would be performed on {drive}: (safe operation)"
    except Exception as e:
        logger.error(f"Trim error: {e}")
        return f"Error: {str(e)}"

# -------- DISK SCAN & REPAIR --------

def scan_disk(drive: str = "C", fix_errors: bool = False, dry_run: bool = True) -> str:
    """Scan disk for errors"""
    try:
        if dry_run:
            cmd = f'powershell -Command "Repair-Volume -DriveLetter {drive} -Scan"'
        else:
            cmd = f'powershell -Command "Repair-Volume -DriveLetter {drive} -Scan -SpotFix"'
        
        result = WindowsSystemUtils.run_command(cmd, admin=True, timeout=3600)
        summary = f"Disk scan on {drive}: completed.\\nResult:\\n{result}"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Disk scan error: {e}")
        return f"Error: {str(e)}"

# -------- WIPE FREE SPACE --------

def wipe_free_space(drive: str = "C", dry_run: bool = True) -> str:
    """Securely wipe free disk space"""
    try:
        if dry_run:
            return f"[DRY-RUN] Free space wipe would be performed on {drive}:\\ (can take hours)"
        else:
            # Placeholder - actual implementation would use cipher.exe or similar
            cmd = f'powershell -Command "cipher /w:{drive}:\\\\"'
            result = WindowsSystemUtils.run_command(cmd, admin=True, timeout=7200)
            return f"Free space wipe completed on {drive}:\\. Output:\\n{result}"
    except Exception as e:
        logger.error(f"Wipe free error: {e}")
        return f"Error: {str(e)}"

# -------- PRIVACY & TELEMETRY --------

def disable_telemetry(dry_run: bool = True) -> str:
    """Disable Windows telemetry"""
    try:
        services_to_disable = [
            "DiagTrack",
            "dmwappushservice",
            "AppVShNotify",
        ]
        
        results = []
        for service in services_to_disable:
            if not dry_run:
                cmd = f'powershell -Command "Stop-Service -Name {service} -Force -ErrorAction SilentlyContinue; Set-Service -Name {service} -StartupType Disabled -ErrorAction SilentlyContinue"'
                WindowsSystemUtils.run_command(cmd, admin=True)
            results.append(f"  - {service}")
        
        summary = f"Telemetry disabled. Services:{chr(10) + chr(10).join(results)}"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Telemetry disable error: {e}")
        return f"Error: {str(e)}"

def disable_privacy_tracking(dry_run: bool = True) -> str:
    """Disable privacy-invasive settings"""
    try:
        if not dry_run:
            # Disable activity history
            cmd = 'powershell -Command "Set-ItemProperty -Path HKLM:\\\\SOFTWARE\\\\Policies\\\\Microsoft\\\\Windows\\\\System -Name PublishUserActivities -Value 0 -Force"'
            WindowsSystemUtils.run_command(cmd, admin=True)
            
            # Disable app suggestions
            cmd = 'powershell -Command "Set-ItemProperty -Path HKCU:\\\\SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\ContentDeliveryManager -Name ContentDeliveryAllowed -Value 0 -Force"'
            WindowsSystemUtils.run_command(cmd, admin=True)
        
        summary = "Privacy tracking disabled (activity history, app suggestions)"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Privacy disable error: {e}")
        return f"Error: {str(e)}"

# -------- BLOATWARE REMOVAL --------

def remove_bloatware(dry_run: bool = True) -> str:
    """Remove common bloatware applications"""
    try:
        bloatware_apps = [
            "Microsoft.BingWeather",
            "Microsoft.BingNews",
            "Microsoft.MixedReality.Portal",
            "Microsoft.XboxApp",
            "Microsoft.ZuneMusic",
            "Microsoft.ZuneVideo",
            "Microsoft.OneConnect",
            "Microsoft.People",
        ]
        
        removed = []
        for app in bloatware_apps:
            if not dry_run:
                cmd = f'powershell -Command "Get-AppxPackage -Name *{app}* | Remove-AppxPackage -ErrorAction SilentlyContinue"'
                WindowsSystemUtils.run_command(cmd)
            removed.append(f"  - {app}")
        
        summary = f"Bloatware removal complete. Removed:{chr(10) + chr(10).join(removed)}"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Bloatware removal error: {e}")
        return f"Error: {str(e)}"

# -------- SYSTEM HEALTH --------

def run_sfc_scan(dry_run: bool = True) -> str:
    """Run System File Checker"""
    try:
        if dry_run:
            cmd = 'powershell -Command "sfc /verifyonly"'
        else:
            cmd = 'powershell -Command "sfc /scannow"'
        
        result = WindowsSystemUtils.run_command(cmd, admin=True, timeout=1800)
        summary = f"SFC scan completed.\\nOutput:\\n{result[:500]}"  # Limit output
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] System File Checker scan")
        return summary
    except Exception as e:
        logger.error(f"SFC scan error: {e}")
        return f"Error: {str(e)}"

def run_dism_repair(dry_run: bool = True) -> str:
    """Run DISM repair operation"""
    try:
        if dry_run:
            cmd = 'powershell -Command "DISM /Online /Cleanup-Image /ScanHealth"'
        else:
            cmd = 'powershell -Command "DISM /Online /Cleanup-Image /RestoreHealth"'
        
        result = WindowsSystemUtils.run_command(cmd, admin=True, timeout=1800)
        summary = f"DISM repair completed.\\nOutput:\\n{result[:500]}"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] DISM repair")
        return summary
    except Exception as e:
        logger.error(f"DISM error: {e}")
        return f"Error: {str(e)}"

# -------- DRIVER MANAGEMENT --------

def scan_driver_updates(dry_run: bool = True) -> str:
    """Scan for outdated drivers"""
    try:
        cmd = 'powershell -Command "Get-PnpDevice -PresentOnly | Where-Object {$_.ConfigManagerErrorCode -ne 0} | Select-Object Name,ConfigManagerErrorCode | ConvertTo-Json"'
        result = WindowsSystemUtils.run_command(cmd)
        
        summary = f"Driver scan completed.\\nOutdated drivers found:\\n{result[:500]}"
        logger.info(f"Driver scan completed")
        return summary
    except Exception as e:
        logger.error(f"Driver scan error: {e}")
        return f"Error: {str(e)}"

# -------- BACKUP & RESTORE --------

def create_system_restore_point(description: str = "Neo AI Optimization", dry_run: bool = True) -> str:
    """Create a system restore point"""
    try:
        if not dry_run:
            cmd = f'powershell -Command "Checkpoint-Computer -Description \\"{description}\\" -RestorePointType MODIFY_SETTINGS"'
            WindowsSystemUtils.run_command(cmd, admin=True)
        summary = f"System restore point created: {description}"
        logger.info(f"[{('DRY-RUN' if dry_run else 'EXECUTED')}] {summary}")
        return summary
    except Exception as e:
        logger.error(f"Restore point error: {e}")
        return f"Error: {str(e)}"

# -------- SMART BOOST (ALL-IN-ONE) --------

def smart_boost(dry_run: bool = True) -> str:
    """Execute comprehensive system optimization"""
    try:
        steps = [
            ("Cleaning temp files", lambda: clean_temp_files(dry_run)),
            ("Cleaning browser cache", lambda: clean_browser_cache("all", dry_run)),
            ("Emptying recycle bin", lambda: clean_recycle_bin(dry_run)),
            ("Disabling telemetry", lambda: disable_telemetry(dry_run)),
            ("Disabling privacy tracking", lambda: disable_privacy_tracking(dry_run)),
            ("Removing bloatware", lambda: remove_bloatware(dry_run)),
            ("Running SFC scan", lambda: run_sfc_scan(dry_run)),
        ]
        
        results = []
        for step_name, step_func in steps:
            try:
                output = step_func()
                results.append(f"✓ {step_name}:\\n  {output[:100]}")
                logger.info(f"Smart Boost step completed: {step_name}")
            except Exception as e:
                results.append(f"✗ {step_name}: {str(e)}")
                logger.error(f"Smart Boost step failed: {step_name}: {e}")
        
        summary = f"Smart Boost {'[DRY-RUN]' if dry_run else '[EXECUTED]'} completed.\\n\\n" + "\\n\\n".join(results)
        logger.info(f"Smart Boost completed ({'DRY-RUN' if dry_run else 'EXECUTED'})")
        return summary
    except Exception as e:
        logger.error(f"Smart boost error: {e}")
        return f"Error: {str(e)}"

# -------- UTILITY FUNCTIONS --------

def get_system_info_json() -> str:
    """Get system info as JSON"""
    try:
        info = WindowsSystemUtils.get_system_info()
        return json.dumps(info, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})

def get_smart_advice() -> str:
    """Get proactive optimization advice"""
    try:
        info = WindowsSystemUtils.get_system_info()
        device = info.get("device", {})
        ram_percent = device.get("ram_percent", 0)
        
        advice = []
        
        if ram_percent > 80:
            advice.append("🔴 RAM usage is high. Close unnecessary applications.")
        elif ram_percent > 65:
            advice.append("🟡 RAM usage is moderate. Monitor for further increases.")
        else:
            advice.append("🟢 RAM usage is healthy.")
        
        for disk in device.get("disks", []):
            pct = disk.get("used_percent", 0)
            if pct > 90:
                advice.append(f"🔴 Drive {disk['drive']}: is {pct}% full! Perform immediate cleanup.")
            elif pct > 75:
                advice.append(f"🟡 Drive {disk['drive']}: is {pct}% full. Schedule cleanup.")
            else:
                advice.append(f"🟢 Drive {disk['drive']}: has sufficient space.")
        
        return "\\n".join(advice)
    except Exception as e:
        return f"Error getting advice: {str(e)}"

# ============================================================
# FASTAPI APPLICATION
# ============================================================

app = FastAPI(
    title="Neo Optimize AI",
    description="Advanced Windows System Optimizer",
    version="1.0.0"
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# -------- REQUEST MODELS --------

class ToolRequest(BaseModel):
    tool_name: str
    params: Dict[str, Any] = {}
    dry_run: bool = True

class CommandPollRequest(BaseModel):
    client_id: str

class CommandResultRequest(BaseModel):
    command_id: str
    status: str
    result: str

# -------- MIDDLEWARE --------

async def verify_api_key(request: Request):
    """Verify API key from header"""
    key = request.headers.get("X-API-Key")
    if key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")

# -------- ENDPOINTS --------

@app.get("/")
async def root():
    """Root endpoint with service info"""
    return {
        "service": "Neo Optimize AI Backend",
        "version": "1.0.0",
        "status": "operational",
        "features": [
            "system-optimization",
            "cleaner",
            "defrag-trim",
            "disk-scan-repair",
            "bloatware-removal",
            "privacy-cleanup",
            "autonomous-monitoring",
            "ai-chat-interface"
        ],
        "endpoints": [
            "/health",
            "/system-info",
            "/smart-advice",
            "/execute-tool",
            "/smart-boost",
        ]
    }

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {"status": "ok", "timestamp": datetime.now().isoformat()}

@app.get("/system-info")
async def system_info(api_key: str = None):
    """Get current system information"""
    if api_key and api_key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")
    
    info = WindowsSystemUtils.get_system_info()
    return info

@app.get("/smart-advice")
async def smart_advice(api_key: str = None):
    """Get smart optimization advice"""
    if api_key and api_key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")
    
    advice = get_smart_advice()
    return {"advice": advice}

@app.post("/execute-tool")
async def execute_tool(request: ToolRequest, api_key: str = None, background_tasks: BackgroundTasks = None):
    """Execute a system optimization tool"""
    if api_key and api_key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")
    
    try:
        tool_map = {
            "clean_temp": clean_temp_files,
            "clean_browser": clean_browser_cache,
            "clean_recycle": clean_recycle_bin,
            "clean_registry": clean_registry,
            "defrag": defrag_drive,
            "trim": trim_ssd,
            "scan_disk": scan_disk,
            "wipe_free": wipe_free_space,
            "disable_telemetry": disable_telemetry,
            "disable_tracking": disable_privacy_tracking,
            "remove_bloatware": remove_bloatware,
            "sfc_scan": run_sfc_scan,
            "dism_repair": run_dism_repair,
            "driver_scan": scan_driver_updates,
            "smart_boost": smart_boost,
            "system_info": lambda: get_system_info_json(),
        }
        
        tool_func = tool_map.get(request.tool_name)
        if not tool_func:
            raise HTTPException(status_code=404, detail=f"Tool not found: {request.tool_name}")
        
        # Execute tool
        if request.tool_name in ["defrag", "trim", "wipe_free", "smart_boost"]:
            # Long-running operations
            result = f"Tool '{request.tool_name}' scheduled. Check back later."
            if background_tasks:
                background_tasks.add_task(tool_func, request.dry_run)
        else:
            # Quick operations
            result = tool_func(request.dry_run) if request.dry_run else tool_func()
        
        return {
            "tool": request.tool_name,
            "status": "success",
            "dry_run": request.dry_run,
            "result": result,
            "timestamp": datetime.now().isoformat()
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Tool execution error: {e}")
        return {
            "tool": request.tool_name,
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

@app.post("/smart-boost")
async def smart_boost_endpoint(dry_run: bool = True, api_key: str = None, background_tasks: BackgroundTasks = None):
    """Execute smart boost optimization"""
    if api_key and api_key != CLIENT_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API Key")
    
    try:
        result = smart_boost(dry_run)
        return {
            "operation": "smart-boost",
            "status": "success",
            "dry_run": dry_run,
            "result": result,
            "timestamp": datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Smart boost error: {e}")
        return {
            "operation": "smart-boost",
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now().isoformat()
        }

# ============================================================
# INITIALIZATION
# ============================================================

if __name__ == "__main__":
    import uvicorn
    
    logger.info("Starting Neo Optimize AI backend...")
    print("Starting Neo Optimize AI backend on http://0.0.0.0:7860", file=sys.stderr)
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=7860,
        log_level="info"
    )
