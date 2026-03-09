import json
import time
import uuid
import logging
from datetime import datetime, timedelta
from typing import List, Optional
from langchain.tools import Tool
from app.services.supabase_client import get_supabase

logger = logging.getLogger(__name__)

# ==================== DATABASE HELPERS (dengan client_id) ====================
def create_command(client_id: str, tool_name: str, params: dict) -> str:
    supabase = get_supabase()
    cmd_id = str(uuid.uuid4())
    data = {
        "id": cmd_id,
        "client_id": client_id,
        "tool": tool_name,
        "params": json.dumps(params),
        "status": "pending",
        "created_at": datetime.utcnow().isoformat()
    }
    supabase.table("commands").insert(data).execute()
    return cmd_id

def wait_for_result(cmd_id: str, timeout: int = 60) -> str:
    supabase = get_supabase()
    start = time.time()
    while time.time() - start < timeout:
        resp = supabase.table("commands").select("result", "status").eq("id", cmd_id).execute()
        if resp.data:
            row = resp.data[0]
            if row["status"] == "completed" and row.get("result"):
                return row["result"]
            elif row["status"] == "failed":
                return f"Command failed: {row.get('result', 'Unknown error')}"
        time.sleep(1)
    return "Timeout waiting for command execution."

def parse_interval(interval: str) -> timedelta:
    interval = interval.lower().strip()
    if "weekly" in interval or "week" in interval:
        return timedelta(weeks=1)
    elif "daily" in interval or "day" in interval:
        return timedelta(days=1)
    elif "hourly" in interval or "hour" in interval:
        return timedelta(hours=1)
    elif "minute" in interval:
        parts = interval.split()
        if parts[0].isdigit():
            return timedelta(minutes=int(parts[0]))
    return timedelta(days=7)

def add_scheduled_task(task_name: str, interval: str, params: dict):
    supabase = get_supabase()
    task_id = str(uuid.uuid4())
    next_run = datetime.utcnow() + parse_interval(interval)
    data = {
        "id": task_id,
        "task_name": task_name,
        "params": json.dumps(params),
        "interval": interval,
        "next_run": next_run.isoformat(),
        "active": True,
        "created_at": datetime.utcnow().isoformat()
    }
    supabase.table("scheduled_tasks").insert(data).execute()

# ==================== TOOL FUNCTIONS ====================
# Semua fungsi menerima client_id sebagai parameter pertama (kecuali fungsi yang tidak memerlukan)
def run_cleaner(client_id: str, category: str, subcategory: str = None) -> str:
    try:
        params = {"category": category}
        if subcategory:
            params["subcategory"] = subcategory
        cmd_id = create_command(client_id, "cleaner", params)
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("run_cleaner failed")
        return f"Gagal menjalankan cleaner: {str(e)}"

def run_optimizer(client_id: str, category: str) -> str:
    try:
        cmd_id = create_command(client_id, "optimizer", {"category": category})
        return wait_for_result(cmd_id, timeout=180)
    except Exception as e:
        logger.exception("run_optimizer failed")
        return f"Gagal menjalankan optimizer: {str(e)}"

def run_app_management(client_id: str, category: str, app_names: List[str] = None) -> str:
    try:
        params = {"category": category}
        if app_names:
            params["app_names"] = app_names
        cmd_id = create_command(client_id, "app_management", params)
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("run_app_management failed")
        return f"Gagal menjalankan app management: {str(e)}"

def check_integrity(client_id: str, path: str) -> str:
    try:
        cmd_id = create_command(client_id, "integrity", {"path": path})
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("check_integrity failed")
        return f"Gagal memeriksa integritas: {str(e)}"

def get_system_info(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "system_info", {})
        return wait_for_result(cmd_id, timeout=30)
    except Exception as e:
        logger.exception("get_system_info failed")
        return f"Gagal mendapatkan info sistem: {str(e)}"

def kill_background_processes(client_id: str, threshold: float = 90.0) -> str:
    try:
        cmd_id = create_command(client_id, "kill_background", {"threshold": threshold})
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("kill_background_processes failed")
        return f"Gagal membunuh proses background: {str(e)}"

def fix_system_crash(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "fix_crash", {})
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("fix_system_crash failed")
        return f"Gagal memperbaiki crash sistem: {str(e)}"

def defrag_drive(client_id: str, drive_letter: str) -> str:
    try:
        cmd_id = create_command(client_id, "defrag", {"drive": drive_letter})
        return wait_for_result(cmd_id, timeout=3600)
    except Exception as e:
        logger.exception("defrag_drive failed")
        return f"Gagal mendefrag drive: {str(e)}"

def trim_ssd(client_id: str, drive_letter: str) -> str:
    try:
        cmd_id = create_command(client_id, "trim", {"drive": drive_letter})
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("trim_ssd failed")
        return f"Gagal melakukan trim pada SSD: {str(e)}"

def schedule_task(client_id: str, task_name: str, interval: str, params: dict) -> str:
    try:
        add_scheduled_task(task_name, interval, params)
        return f"Task '{task_name}' scheduled every {interval}."
    except Exception as e:
        logger.exception("schedule_task failed")
        return f"Gagal menjadwalkan task: {str(e)}"

def wipe_free_space(client_id: str, drive_letter: str) -> str:
    try:
        cmd_id = create_command(client_id, "wipe_free", {"drive": drive_letter})
        return wait_for_result(cmd_id, timeout=3600)
    except Exception as e:
        logger.exception("wipe_free_space failed")
        return f"Gagal menghapus ruang kosong: {str(e)}"

def scan_disk(client_id: str, drive_letter: str, fix_errors: bool = False) -> str:
    try:
        cmd_id = create_command(client_id, "scan_disk", {"drive": drive_letter, "fix": fix_errors})
        return wait_for_result(cmd_id, timeout=3600)
    except Exception as e:
        logger.exception("scan_disk failed")
        return f"Gagal memindai disk: {str(e)}"

def fix_boot(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "fix_boot", {})
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("fix_boot failed")
        return f"Gagal memperbaiki boot: {str(e)}"

def clear_memory_cache(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "clear_memory", {})
        return wait_for_result(cmd_id, timeout=60)
    except Exception as e:
        logger.exception("clear_memory_cache failed")
        return f"Gagal membersihkan memory cache: {str(e)}"

def run_duplicate_finder(client_id: str, scan_method: str = "content", scan_location: str = "all", file_types: List[str] = None) -> str:
    try:
        params = {
            "scan_method": scan_method,
            "scan_location": scan_location,
            "file_types": file_types or []
        }
        cmd_id = create_command(client_id, "duplicate_finder", params)
        return wait_for_result(cmd_id, timeout=600)
    except Exception as e:
        logger.exception("run_duplicate_finder failed")
        return f"Gagal mencari duplikat: {str(e)}"

def run_empty_folder_cleaner(client_id: str, scan_depth: int = -1, exclude_folders: List[str] = None) -> str:
    try:
        params = {
            "scan_depth": scan_depth,
            "exclude_folders": exclude_folders or []
        }
        cmd_id = create_command(client_id, "empty_folder_cleaner", params)
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("run_empty_folder_cleaner failed")
        return f"Gagal membersihkan folder kosong: {str(e)}"

def run_registry_cleaner(client_id: str, scan_categories: List[str] = None) -> str:
    try:
        params = {"scan_categories": scan_categories or []}
        cmd_id = create_command(client_id, "registry_cleaner", params)
        return wait_for_result(cmd_id, timeout=180)
    except Exception as e:
        logger.exception("run_registry_cleaner failed")
        return f"Gagal membersihkan registry: {str(e)}"

def run_network_cleaner(client_id: str, clean_items: List[str] = None) -> str:
    try:
        params = {"clean_items": clean_items or []}
        cmd_id = create_command(client_id, "network_cleaner", params)
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("run_network_cleaner failed")
        return f"Gagal membersihkan network: {str(e)}"

def run_visual_cache_cleaner(client_id: str, clean_items: List[str] = None) -> str:
    try:
        params = {"clean_items": clean_items or []}
        cmd_id = create_command(client_id, "visual_cache_cleaner", params)
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("run_visual_cache_cleaner failed")
        return f"Gagal membersihkan visual cache: {str(e)}"

def run_appx_cleaner(client_id: str, clean_items: List[str] = None) -> str:
    try:
        params = {"clean_items": clean_items or []}
        cmd_id = create_command(client_id, "appx_cleaner", params)
        return wait_for_result(cmd_id, timeout=180)
    except Exception as e:
        logger.exception("run_appx_cleaner failed")
        return f"Gagal membersihkan AppX: {str(e)}"

def run_driver_cleaner(client_id: str, clean_outdated: bool = True, clean_old_versions: bool = True) -> str:
    try:
        params = {
            "clean_outdated": clean_outdated,
            "clean_old_versions": clean_old_versions
        }
        cmd_id = create_command(client_id, "driver_cleaner", params)
        return wait_for_result(cmd_id, timeout=180)
    except Exception as e:
        logger.exception("run_driver_cleaner failed")
        return f"Gagal membersihkan driver: {str(e)}"

def run_driver_scanner(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "driver_scanner", {})
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("run_driver_scanner failed")
        return f"Gagal memindai driver: {str(e)}"

def run_backup_restore(client_id: str, backup_type: str, params: dict) -> str:
    try:
        data = {"backup_type": backup_type, "params": params}
        cmd_id = create_command(client_id, "backup_restore", data)
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("run_backup_restore failed")
        return f"Gagal melakukan backup/restore: {str(e)}"

# ==================== TOOL FUNGSI DAFTAR KATEGORI ====================
def list_cleaner_categories(client_id: str = None) -> str:
    categories = [
        "CAT_TEMP_FILES", "CAT_PREFETCH", "CAT_RECYCLE_BIN",
        "CAT_BROWSER_CACHE_CHROME", "CAT_BROWSER_CACHE_EDGE", "CAT_BROWSER_CACHE_FIREFOX",
        "CAT_BROWSER_CACHE_OPERA", "CAT_BROWSER_CACHE_BRAVE", "CAT_BROWSER_CACHE_VIVALDI",
        "CAT_BROWSER_CACHE_YANDEX", "CAT_BROWSER_CACHE_IE",
        "CAT_BROWSER_HISTORY", "CAT_BROWSER_COOKIES", "CAT_BROWSER_SESSION",
        "CAT_BROWSER_DOWNLOAD_HISTORY",
        "CAT_LOG_FILES", "CAT_LOG_SYSTEM", "CAT_LOG_IIS", "CAT_LOG_SETUP", "CAT_LOG_CRASH",
        "CAT_DUMP_FILES", "CAT_MEMORY_DUMPS", "CAT_SYSTEM_ERROR_DUMPS", "CAT_APP_CRASH_DUMPS",
        "CAT_WINDOWS_UPDATES", "CAT_WINDOWS_UPDATE_CACHE", "CAT_WINDOWS_UPDATE_LOGS",
        "CAT_WINDOWS_UPDATE_BACKUP", "CAT_WINDOWS_UPDATE_CLEANUP",
        "CAT_APP_CACHE", "CAT_STORE_APP_CACHE", "CAT_MICROSOFT_STORE_CACHE",
        "CAT_OFFICE_CACHE", "CAT_VISUAL_STUDIO_CACHE", "CAT_ADOBE_CACHE",
        "CAT_STEAM_CACHE", "CAD_EPIC_GAMES_CACHE", "CAT_BATTLE_NET_CACHE",
        "CAT_ORIGIN_CACHE", "CAT_DISCORD_CACHE", "CAT_SPOTIFY_CACHE",
        "CAT_TEAMS_CACHE", "CAT_ZOOM_CACHE", "CAT_SLACK_CACHE",
        "CAT_TELEGRAM_CACHE", "CAT_WHATSAPP_CACHE",
        "CAT_THUMBNAILS", "CAT_ICON_CACHE", "CAT_FONT_CACHE",
        "CAT_DELIVERY_OPTIMIZATION", "CAT_DIRECTX_SHADER_CACHE",
        "CAT_DEVICE_DRIVER_PACKAGES", "CAT_DOWNLOADED_PROGRAM_FILES",
        "CAT_TEMPORARY_INTERNET_FILES",
        "CAT_SYSTEM_RESTORE", "CAT_VOLUME_SHADOW_COPY", "CAT_WINDOWS_BACKUP",
        "CAT_FILE_HISTORY",
        "CAT_WINDOWS_ERROR_REPORTING", "CAT_QUEUED_ERROR_REPORTING", "CAT_APP_CRASH_REPORTS",
        "CAT_DNS_CACHE", "CAT_ARP_CACHE", "CAT_DHCP_CACHE", "CAT_ROUTING_TABLE",
        "CAT_RECENT_DOCUMENTS", "CAT_RUN_HISTORY", "CAT_SEARCH_HISTORY",
        "CAT_NOTIFICATION_HISTORY", "CAT_CLIPBOARD_HISTORY",
        "CAT_NPM_CACHE", "CAT_PIP_CACHE", "CAT_MAVEN_CACHE", "CAT_GRADLE_CACHE",
        "CAT_NUGET_CACHE", "CAT_VS_CODE_CACHE", "CAT_INTELLIJ_CACHE",
        "CAT_ECLIPSE_CACHE", "CAT_ANDROID_STUDIO_CACHE", "CAT_DOCKER_CACHE",
        "CAT_VIRTUALBOX_CACHE", "CAT_VMWARE_CACHE",
        "CAT_GAME_LOGS", "CAT_GAME_CRASH_DUMPS", "CAT_GAME_CACHE", "CAT_GAME_CONFIG_BACKUP",
        "CAT_WINDOWS_DEFENDER_CACHE", "CAT_ANTIVIRUS_LOGS", "CAT_ANTIVIRUS_QUARANTINE",
        "CAT_OFFICE_RECENT_FILES", "CAT_OFFICE_TEMPLATES_CACHE", "CAT_OFFICE_ADDINS_CACHE",
        "CAT_OFFICE_DOCUMENT_RECOVERY",
        "CAT_WINDOWS_FEATURE_BACKUP", "CAT_WINDOWS_COMPONENT_STORE", "CAT_SERVICING_STACK",
        "CAT_JUMP_LISTS", "CAT_AUTOCOMPLETE_DATA", "CAT_PASSWORD_CACHE",
        "CAT_FINGERPRINT_CACHE", "CAT_WIFI_PROFILES", "CAT_BLUETOOTH_CACHE",
        "CAT_PRINTER_SPOOL", "CAT_FAX_QUEUE",
    ]
    return "Available cleaner categories:\n" + "\n".join(categories)

def list_optimizer_categories(client_id: str = None) -> str:
    categories = [
        "CAT_SFC_SCANNOW", "CAT_SFC_VERIFYONLY", "CAT_SFC_SCANFILE", "CAT_SFC_VERIFYFILE",
        "CAT_SFC_REVERT", "CAT_DISM_CHECKHEALTH", "CAT_DISM_SCANHEALTH", "CAT_DISM_RESTOREHEALTH",
        "CAT_DISM_CLEANUP_COMPONENTS", "CAT_DISM_RESETBASE", "CAT_DISM_ANALYZE_COMPONENT_STORE",
        "CAT_DISM_CLEANUP_WINSXS", "CAT_DISM_ADD_PACKAGE", "CAT_DISM_REMOVE_PACKAGE",
        "CAT_PRIVACY_ACTIVITY_HISTORY", "CAT_PRIVACY_CORTANA", "CAT_PRIVACY_TELEMETRY",
        "CAT_PRIVACY_LOCATION", "CAT_PRIVACY_SPEECH", "CAT_PRIVACY_INKING",
        "CAT_PRIVACY_ADVERTISING_ID", "CAT_PRIVACY_APP_PERMISSIONS", "CAT_PRIVACY_BACKGROUND_APPS",
        "CAT_PRIVACY_FEEDBACK_HUB", "CAT_PRIVACY_WINDOWS_SEARCH", "CAT_PRIVACY_RECENT_FILES",
        "CAT_PRIVACY_RUN_HISTORY", "CAT_PRIVACY_NOTIFICATION_HISTORY", "CAT_PRIVACY_CLIPBOARD_HISTORY",
        "CAT_STORE_CACHE", "CAT_STORE_LOGS", "CAT_STORE_TEMP_FILES", "CAT_STORE_APP_DATA",
        "CAT_STORE_REINSTALL", "CAT_STORE_RESET",
        "CAT_BOOT_FIXMBR", "CAT_BOOT_FIXBOOT", "CAT_BOOT_REBUILDBCD", "CAT_BOOT_SCANOS",
        "CAT_BOOT_BCDEDIT_EXPORT", "CAT_BOOT_BCDEDIT_IMPORT", "CAT_BOOT_BCDEDIT_DEFAULT",
        "CAT_BOOT_BCDEDIT_TIMEOUT", "CAT_BOOT_BCDEDIT_BOOTMENU_POLICY", "CAT_BOOT_BCDEDIT_RECOVERYENABLED",
        "CAT_BOOT_BOOTCFG_REBUILD", "CAT_BOOT_BOOTSECT",
        "CAT_BOOT_TWEAK_TSYNC", "CAT_BOOT_TWEAK_USEPLATFORMTICK", "CAT_BOOT_TWEAK_BOOTMENULEGACY",
        "CAT_BOOT_TWEAK_HYPERVISOR", "CAT_BOOT_TWEAK_NUMPROC", "CAT_BOOT_TWEAK_TRUNCATEMEMORY",
        "CAT_REG_MISSING_SHARED_DLLS", "CAT_REG_UNUSED_SHARED_DLLS", "CAT_REG_INVALID_MSI_PATHS",
        "CAT_REG_COM_ACTIVEX_MISSING", "CAT_REG_MRU_LISTS", "CAT_REG_MISSING_STARTUP_ITEMS",
        "CAT_REG_INVALID_CACHE", "CAT_REG_UNAVAILABLE_SERVICES", "CAT_REG_INCORRECT_UNINSTALLER",
        "CAT_REG_UNUSED_FILE_EXTENSIONS", "CAT_REG_INVALID_FIREWALL_RULES", "CAT_REG_EMPTY_KEYS",
        "CAT_REG_WRONG_APP_PATHS", "CAT_REG_INVALID_CLASS_KEYS", "CAT_REG_CORRUPTED_CONTEXT_MENU",
        "CAT_REG_INVALID_SYSTEM_SETTINGS", "CAT_REG_FONT_CACHE", "CAT_REG_DEVICE_INSTALLER",
        "CAT_REG_SOUND_SCHEMES", "CAT_REG_EVENT_LOG", "CAT_REG_PERFORMANCE_COUNTERS",
        "CAT_REG_NETWORK_SETTINGS",
        "CAT_REG_TWEAK_GRAPHICS_SCHEDULER", "CAT_REG_TWEAK_LARGE_SYSTEM_CACHE",
        "CAT_REG_TWEAK_MMCSS", "CAT_REG_TWEAK_TCP_ACK", "CAT_REG_TWEAK_DIAGNOSTIC_TRACKING",
        "CAT_REG_TWEAK_PRIORITY_SEPARATION", "CAT_REG_TWEAK_POWER_SCHEME",
        "CAT_REG_TWEAK_PREFETCH", "CAT_REG_TWEAK_MEMORY_MANAGEMENT", "CAT_REG_TWEAK_IO_PRIORITY",
        "CAT_BACKUP_SYSTEM_RESTORE_POINT", "CAT_BACKUP_REGISTRY_FULL", "CAT_BACKUP_REGISTRY_HIVE",
        "CAT_BACKUP_DRIVERS", "CAT_BACKUP_BCD", "CAT_BACKUP_BOOT_FILES", "CAT_BACKUP_TASK_SCHEDULER",
        "CAT_BACKUP_POWER_SCHEMES", "CAT_BACKUP_NETWORK_PROFILES",
        "CAT_RESTORE_SYSTEM_RESTORE_POINT", "CAT_RESTORE_REGISTRY", "CAT_RESTORE_DRIVERS",
        "CAT_RESTORE_BCD",
        "CAT_DRIVER_SCAN", "CAT_DRIVER_BACKUP", "CAT_DRIVER_RESTORE", "CAT_DRIVER_ROLLBACK",
        "CAT_DRIVER_REMOVE_OLD", "CAT_DRIVER_DISABLE_UNUSED",
        "CAT_UPDATE_RESET", "CAT_UPDATE_CLEAR_CACHE", "CAT_UPDATE_REMOVE_PREVIOUS",
        "CAT_UPDATE_BLOCK_TELEMETRY", "CAT_UPDATE_PAUSE", "CAT_UPDATE_RESUME",
        "CAT_NET_RESET_WINSOCK", "CAT_NET_RESET_IP", "CAT_NET_RESET_WINHTTP",
        "CAT_NET_FLUSH_DNS", "CAT_NET_RELEASE_RENEW", "CAT_NET_RESET_FIREWALL",
        "CAT_NET_OPTIMIZE_TCP", "CAT_NET_DISABLE_NETBIOS", "CAT_NET_DISABLE_LLMNR",
        "CAT_NET_DISABLE_WPAD",
        "CAT_PERF_VISUAL_EFFECTS", "CAT_PERF_PROCESSOR_SCHEDULING", "CAT_PERF_VIRTUAL_MEMORY",
        "CAT_PERF_STARTUP_PROGRAMS", "CAT_PERF_SERVICES", "CAT_PERF_SCHEDULED_TASKS",
        "CAT_PERF_POWER_PLAN",
        "CAT_HEALTH_PERFMON_REPORT", "CAT_HEALTH_SYSTEM_DIAGNOSTICS",
        "CAT_HEALTH_RELIABILITY_HISTORY", "CAT_HEALTH_EVENT_VIEWER",
    ]
    return "Available optimizer categories:\n" + "\n".join(categories)

def list_app_management_categories(client_id: str = None) -> str:
    categories = [
        "CAT_BLOATWARE_MICROSOFT", "CAT_BLOATWARE_MANUFACTURER", "CAT_BLOATWARE_GAMES",
        "CAT_BLOATWARE_TRIAL_SOFTWARE", "CAT_STARTUP_DISABLE_ALL", "CAT_BACKGROUND_DISABLE_ALL",
        "CAT_APP_CACHE_ALL", "CAT_APP_CACHE_CHROME", "CAT_APP_CACHE_DISCORD",
        "CAT_APP_CACHE_SPOTIFY", "CAT_APP_CACHE_STEAM", "CAT_APP_CACHE_NPM",
        "CAT_DEEP_CLEAN_APP_DATA"
    ]
    return "Available app management categories:\n" + "\n".join(categories)

# ==================== TOOL FUNGSI TAMBAHAN ====================
def smart_boost(client_id: str) -> str:
    try:
        steps = [
            ("cleaner", {"category": "CAT_TEMP_FILES"}),
            ("cleaner", {"category": "CAT_RECYCLE_BIN"}),
            ("cleaner", {"category": "CAT_BROWSER_CACHE_CHROME"}),
            ("optimizer", {"category": "CAT_SFC_SCANNOW"}),
            ("optimizer", {"category": "CAT_DISM_RESTOREHEALTH"}),
            ("clear_memory_cache", {}),
        ]
        results = []
        for tool, params in steps:
            cmd_id = create_command(client_id, tool, params)
            result = wait_for_result(cmd_id, timeout=300)
            results.append(f"{tool}: {result}")
        return "\n".join(results)
    except Exception as e:
        logger.exception("smart_boost failed")
        return f"Smart boost gagal: {str(e)}"

def save_feedback(client_id: str, message_id: str, rating: int, comment: str = "") -> str:
    try:
        supabase = get_supabase()
        data = {
            "message_id": message_id,
            "rating": rating,
            "comment": comment,
            "created_at": datetime.utcnow().isoformat()
        }
        supabase.table("feedback").insert(data).execute()
        return "Terima kasih atas masukannya!"
    except Exception as e:
        logger.exception("save_feedback failed")
        return f"Gagal menyimpan feedback: {str(e)}"

def get_smart_advice(client_id: str) -> str:
    try:
        info_json = get_system_info(client_id)
        if info_json.startswith("Gagal") or info_json.startswith("Timeout"):
            return "Tidak dapat memperoleh info sistem."
        info = json.loads(info_json)
        cpu = info.get("cpu_percent", 0)
        ram = info.get("ram_percent", 0)
        disk = info.get("disk_percent", {})
        advice = []
        if cpu > 80:
            advice.append("CPU usage tinggi. Tutup aplikasi yang tidak perlu.")
        if ram > 85:
            advice.append("RAM hampir penuh. Restart browser atau aplikasi berat.")
        for drive, usage in disk.items():
            if usage > 90:
                advice.append(f"Drive {drive} hampir penuh. Lakukan pembersihan.")
        if not advice:
            advice.append("Sistem dalam kondisi baik. Pertahankan!")
        return "\n".join(advice)
    except Exception as e:
        logger.exception("get_smart_advice failed")
        return f"Gagal mendapatkan saran: {str(e)}"

def web_search(client_id: str, query: str) -> str:
    return "Fitur web search belum diimplementasikan."

def check_driver_updates(client_id: str) -> str:
    try:
        cmd_id = create_command(client_id, "driver_scanner", {})
        return wait_for_result(cmd_id, timeout=120)
    except Exception as e:
        logger.exception("check_driver_updates failed")
        return f"Gagal memeriksa driver: {str(e)}"

def auto_backup(client_id: str, backup_type: str = "system_restore") -> str:
    try:
        params = {"backup_type": backup_type}
        cmd_id = create_command(client_id, "backup_restore", {"backup_type": backup_type, "params": params})
        return wait_for_result(cmd_id, timeout=300)
    except Exception as e:
        logger.exception("auto_backup failed")
        return f"Gagal melakukan backup: {str(e)}"

def analyze_logs(client_id: str, log_type: str = "system") -> str:
    try:
        cmd_id = create_command(client_id, "analyze_logs", {"log_type": log_type})
        return wait_for_result(cmd_id, timeout=180)
    except Exception as e:
        logger.exception("analyze_logs failed")
        return f"Gagal menganalisis log: {str(e)}"

# ==================== DAFTAR TOOL LENGKAP ====================
# Karena LangChain Tool hanya menerima satu argumen string, kita buat wrapper yang memasukkan client_id
# Dalam implementasi ini, client_id akan diambil dari context (misalnya thread-local) atau dari input JSON.
# Untuk memudahkan, kita asumsikan client_id sudah disertakan dalam JSON input.
# Kita buat fungsi pembungkus yang mem-parsing JSON dan memanggil fungsi asli.
import json
from functools import wraps

def tool_wrapper(func):
    @wraps(func)
    def wrapper(input_str: str):
        try:
            args = json.loads(input_str)
            # Pastikan client_id ada, jika tidak coba ambil dari context (fallback)
            client_id = args.pop("client_id", None)
            if client_id is None:
                # TODO: Ambil dari context global (misal menggunakan contextvars)
                # Sementara ini akan gagal jika tidak ada client_id
                return "Error: client_id tidak ditemukan dalam input"
            return func(client_id, **args)
        except Exception as e:
            return f"Error: {str(e)}"
    return wrapper

# Definisikan tools
tools = [
    Tool(name="run_cleaner", func=tool_wrapper(run_cleaner),
         description="Run the cleaner engine. Input: JSON dengan keys: 'client_id' (str), 'category' (str), optional 'subcategory' (str)."),
    Tool(name="run_optimizer", func=tool_wrapper(run_optimizer),
         description="Run the system optimizer. Input: JSON dengan 'client_id' dan 'category'."),
    Tool(name="run_app_management", func=tool_wrapper(run_app_management),
         description="Run app management tasks. Input: JSON dengan 'client_id', 'category', optional 'app_names'."),
    Tool(name="check_integrity", func=tool_wrapper(check_integrity),
         description="Check file/folder integrity. Input: JSON dengan 'client_id' dan 'path'."),
    Tool(name="get_system_info", func=tool_wrapper(get_system_info),
         description="Get current system information. Input: JSON dengan 'client_id'."),
    Tool(name="kill_background_processes", func=tool_wrapper(kill_background_processes),
         description="Kill non-critical background processes. Input: JSON dengan 'client_id' dan optional 'threshold'."),
    Tool(name="fix_system_crash", func=tool_wrapper(fix_system_crash),
         description="Attempt to recover from a system crash. Input: JSON dengan 'client_id'."),
    Tool(name="defrag_drive", func=tool_wrapper(defrag_drive),
         description="Defragment an HDD drive. Input: JSON dengan 'client_id' dan 'drive_letter'."),
    Tool(name="trim_ssd", func=tool_wrapper(trim_ssd),
         description="TRIM an SSD drive. Input: JSON dengan 'client_id' dan 'drive_letter'."),
    Tool(name="schedule_task", func=tool_wrapper(schedule_task),
         description="Schedule a task. Input: JSON dengan 'client_id', 'task_name', 'interval', 'params'."),
    Tool(name="wipe_free_space", func=tool_wrapper(wipe_free_space),
         description="Securely wipe free space on a drive. Input: JSON dengan 'client_id' dan 'drive_letter'."),
    Tool(name="scan_disk", func=tool_wrapper(scan_disk),
         description="Run chkdsk on a drive. Input: JSON dengan 'client_id', 'drive_letter', optional 'fix_errors'."),
    Tool(name="fix_boot", func=tool_wrapper(fix_boot),
         description="Repair boot records. Input: JSON dengan 'client_id'."),
    Tool(name="clear_memory_cache", func=tool_wrapper(clear_memory_cache),
         description="Clear system memory cache. Input: JSON dengan 'client_id'."),
    Tool(name="run_duplicate_finder", func=tool_wrapper(run_duplicate_finder),
         description="Find and remove duplicate files. Input: JSON dengan 'client_id', optional 'scan_method', 'scan_location', 'file_types'."),
    Tool(name="run_empty_folder_cleaner", func=tool_wrapper(run_empty_folder_cleaner),
         description="Delete empty folders. Input: JSON dengan 'client_id', optional 'scan_depth', 'exclude_folders'."),
    Tool(name="run_registry_cleaner", func=tool_wrapper(run_registry_cleaner),
         description="Clean invalid registry entries. Input: JSON dengan 'client_id', optional 'scan_categories'."),
    Tool(name="run_network_cleaner", func=tool_wrapper(run_network_cleaner),
         description="Clean network caches (DNS, ARP, etc.). Input: JSON dengan 'client_id', optional 'clean_items'."),
    Tool(name="run_visual_cache_cleaner", func=tool_wrapper(run_visual_cache_cleaner),
         description="Clean thumbnail, font, and icon caches. Input: JSON dengan 'client_id', optional 'clean_items'."),
    Tool(name="run_appx_cleaner", func=tool_wrapper(run_appx_cleaner),
         description="Clean Windows Store and AppX caches. Input: JSON dengan 'client_id', optional 'clean_items'."),
    Tool(name="run_driver_cleaner", func=tool_wrapper(run_driver_cleaner),
         description="Clean outdated or old driver versions. Input: JSON dengan 'client_id', optional 'clean_outdated', 'clean_old_versions'."),
    Tool(name="run_driver_scanner", func=tool_wrapper(run_driver_scanner),
         description="Scan for outdated drivers. Input: JSON dengan 'client_id'."),
    Tool(name="run_backup_restore", func=tool_wrapper(run_backup_restore),
         description="Perform backup or restore. Input: JSON dengan 'client_id', 'backup_type', 'params'."),
    Tool(name="smart_boost", func=tool_wrapper(smart_boost),
         description="Run a series of optimizations to boost system performance. Input: JSON dengan 'client_id'."),
    Tool(name="save_feedback", func=tool_wrapper(save_feedback),
         description="Save user feedback. Input: JSON dengan 'client_id', 'message_id', 'rating', optional 'comment'."),
    Tool(name="get_smart_advice", func=tool_wrapper(get_smart_advice),
         description="Get proactive advice to improve system performance. Input: JSON dengan 'client_id'."),
    Tool(name="web_search", func=tool_wrapper(web_search),
         description="Search the web for information. Input: JSON dengan 'client_id' dan 'query'."),
    Tool(name="check_driver_updates", func=tool_wrapper(check_driver_updates),
         description="Check for outdated drivers. Input: JSON dengan 'client_id'."),
    Tool(name="auto_backup", func=tool_wrapper(auto_backup),
         description="Create an automatic backup. Input: JSON dengan 'client_id', optional 'backup_type'."),
    Tool(name="analyze_logs", func=tool_wrapper(analyze_logs),
         description="Analyze system or application logs. Input: JSON dengan 'client_id', optional 'log_type'."),
    Tool(name="list_cleaner_categories", func=tool_wrapper(list_cleaner_categories),
         description="List all available cleaner categories. Input: JSON dengan 'client_id' (opsional)."),
    Tool(name="list_optimizer_categories", func=tool_wrapper(list_optimizer_categories),
         description="List all available optimizer categories. Input: JSON dengan 'client_id' (opsional)."),
    Tool(name="list_app_management_categories", func=tool_wrapper(list_app_management_categories),
         description="List all available app management categories. Input: JSON dengan 'client_id' (opsional)."),
]