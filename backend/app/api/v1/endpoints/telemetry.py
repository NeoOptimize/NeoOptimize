from fastapi import APIRouter, Request
from app.core.models import TelemetryData
from app.services.supabase_client import get_supabase
from app.utils.fingerprint import verify_client
from datetime import datetime

router = APIRouter()

@router.post("/push")
async def push_telemetry(data: TelemetryData, request: Request):
    client_id = await verify_client(request)
    supabase = get_supabase()
    supabase.table("telemetry_logs").insert({
        "client_id": client_id,
        "cpu_percent": data.cpu_percent,
        "ram_percent": data.ram_percent,
        "gpu_percent": data.gpu_percent,
        "disk_io_read_bytes": data.disk_io_read_bytes,
        "disk_io_write_bytes": data.disk_io_write_bytes,
        "temperature_celsius": data.temperature_celsius,
        "logged_at": datetime.utcnow().isoformat()
    }).execute()
    return {"status": "ok"}