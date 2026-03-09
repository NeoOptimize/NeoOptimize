from fastapi import APIRouter, Request, HTTPException
from app.core.models import CommandResult
from app.services.supabase_client import get_supabase
from app.utils.fingerprint import verify_client
import json
from datetime import datetime

router = APIRouter()

@router.post("/poll")
async def poll_command(request: Request):
    client_id = await verify_client(request)
    supabase = get_supabase()
    resp = supabase.table("commands").select("*")\
        .eq("client_id", client_id)\
        .eq("status", "pending")\
        .order("created_at")\
        .limit(1)\
        .execute()
    if resp.data:
        cmd = resp.data[0]
        supabase.table("commands").update({"status": "in_progress"}).eq("id", cmd["id"]).execute()
        return {
            "id": cmd["id"],
            "tool": cmd["tool"],
            "params": json.loads(cmd["params"])
        }
    return {}

@router.post("/result")
async def post_result(data: CommandResult, request: Request):
    client_id = await verify_client(request)
    supabase = get_supabase()
    cmd_check = supabase.table("commands").select("client_id").eq("id", data.id).execute()
    if not cmd_check.data or cmd_check.data[0]["client_id"] != client_id:
        raise HTTPException(status_code=403, detail="Command not owned by this client")
    supabase.table("commands").update({
        "status": data.status,
        "result": data.result,
        "updated_at": datetime.utcnow().isoformat()
    }).eq("id", data.id).execute()
    return {"ok": True}