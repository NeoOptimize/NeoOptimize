from fastapi import APIRouter, HTTPException
from app.core.models import ClientRegisterRequest, ClientRegisterResponse
from app.services.supabase_client import get_supabase
import uuid
import hashlib
from datetime import datetime

router = APIRouter()

@router.post("/register", response_model=ClientRegisterResponse)
async def register_client(req: ClientRegisterRequest):
    supabase = get_supabase()
    existing = supabase.table("clients").select("id").eq("hardware_fingerprint", req.hardware_fingerprint).execute()
    if existing.data:
        client = existing.data[0]
        supabase.table("clients").update({
            "name": req.name,
            "last_seen": datetime.utcnow().isoformat()
        }).eq("id", client["id"]).execute()
        api_key = supabase.table("clients").select("client_api_key").eq("id", client["id"]).execute().data[0]["client_api_key"]
        return ClientRegisterResponse(client_id=client["id"], client_api_key=api_key)
    else:
        client_id = str(uuid.uuid4())
        api_key = hashlib.sha256(f"{client_id}-{req.hardware_fingerprint}-{uuid.uuid4()}".encode()).hexdigest()
        data = {
            "id": client_id,
            "client_api_key": api_key,
            "hardware_fingerprint": req.hardware_fingerprint,
            "name": req.name,
            "status": "active",
            "last_seen": datetime.utcnow().isoformat()
        }
        supabase.table("clients").insert(data).execute()
        return ClientRegisterResponse(client_id=client_id, client_api_key=api_key)