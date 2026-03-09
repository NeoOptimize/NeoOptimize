import hashlib
import hmac
import secrets
from uuid import uuid4


CLIENT_ID_HEADER = "X-Client-ID"
CLIENT_API_KEY_HEADER = "X-Client-API-Key"
HARDWARE_FINGERPRINT_HEADER = "X-Hardware-Fingerprint"


def hash_hardware_fingerprint(fingerprint: str) -> str:
    return hashlib.sha256(fingerprint.strip().encode("utf-8")).hexdigest()


def hash_api_key(api_key: str) -> str:
    return hashlib.sha256(api_key.encode("utf-8")).hexdigest()


def constant_time_equals(left: str, right: str) -> bool:
    return hmac.compare_digest(left or "", right or "")


def generate_client_credentials() -> tuple[str, str, str]:
    client_id = str(uuid4())
    client_api_key = f"neo_{secrets.token_urlsafe(32)}"
    client_api_key_hash = hash_api_key(client_api_key)
    return client_id, client_api_key, client_api_key_hash
