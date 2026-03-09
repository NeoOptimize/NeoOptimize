import json
import logging
from typing import List, Optional
from datetime import datetime

from app.services.supabase_client import get_supabase_client

logger = logging.getLogger("Cleaner")

CATEGORIES = [
    "CAT_TEMP_FILES", "CAT_PREFETCH", "CAT_RECYCLE_BIN",
    "CAT_BROWSER_CACHE_CHROME", "CAT_BROWSER_CACHE_EDGE",
    "CAT_LOG_SYSTEM", "CAT_WINDOWS_UPDATE_CLEANUP",
    "CAT_APP_CACHE", "CAT_THUMBNAILS"
]

def run_cleaner(category: str, subcategory: str = None) -> str:
    """Execute cleaner tool via database command"""
    supabase = get_supabase_client()
    
    try:
        cmd_id = str(datetime.now().strftime("%Y%m%d%H%M%S"))
        data = {
            "id": cmd_id,
            "tool": "cleaner",
            "params": json.dumps({"category": category, "subcategory": subcategory}),
            "status": "pending",
            "created_at": datetime.utcnow().isoformat()
        }
        supabase.table("commands").insert(data).execute()
        
        result = wait_for_result(cmd_id, timeout=120)
        return f"✅ Cleaner Completed: {result}"
        
    except Exception as e:
        logger.exception(f"Cleaner error: {e}")
        return f"❌ Error: {str(e)}"

def list_cleaner_categories() -> str:
    """Return available cleaner categories"""
    return "\n".join(CATEGORIES)

def wait_for_result(cmd_id: str, timeout: int = 60) -> str:
    """Poll for command result from database"""
    supabase = get_supabase_client()
    start_time = datetime.now()
    
    while (datetime.now() - start_time).total_seconds() < timeout:
        try:
            resp = supabase.table("commands").select("*").eq("id", cmd_id).execute()
            if resp.data and len(resp.data) > 0:
                row = resp.data[0]
                if row.get("status") == "completed":
                    return row.get("result", "")
        except Exception as e:
            logger.error(f"Wait error: {e}")
        
        time.sleep(1)
    
    return "Timeout waiting for command completion."