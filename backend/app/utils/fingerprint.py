from fastapi import Request, HTTPException
import hmac
from app.services.supabase_client import get_supabase

CLIENT_API_KEY_HEADER = "X-API-Key"
HARDWARE_FINGERPRINT_HEADER = "X-Hardware-Fingerprint"

async def verify_client(request: Request) -> str:
    fingerprint = request.headers.get(HARDWARE_FINGERPRINT_HEADER)
    api_key = request.headers.get(CLIENT_API_KEY_HEADER)
    if not fingerprint or not api_key:
        raise HTTPException(status_code=401, detail="Missing authentication headers")

    supabase = get_supabase()
    resp = supabase.table("clients").select("id, client_api_key, status").eq("hardware_fingerprint", fingerprint).execute()
    if not resp.data:
        raise HTTPException(status_code=401, detail="Invalid fingerprint")

    client = resp.data[0]
    if client["status"] != "active":
        raise HTTPException(status_code=403, detail="Client is blocked")

    if not hmac.compare_digest(api_key, client["client_api_key"]):
        raise HTTPException(status_code=401, detail="Invalid API key")

    return client["id"]