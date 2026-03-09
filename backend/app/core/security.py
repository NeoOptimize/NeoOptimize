from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from functools import wraps
import hashlib
import hmac
from typing import Optional

class SecurityService:
    """Handles authentication and hardware fingerprinting."""

    @staticmethod
    def verify_client_auth(request_headers: dict, api_key: str) -> bool:
        """Verify X-API-Key header matches configured key."""
        provided_key = request_headers.get("X-API-Key", "")
        # Simple timing-safe comparison could be added here
        if provided_key != api_key:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid Client API Key"
            )
        return True

    @staticmethod
    def generate_fingerprint(hardware_info: dict) -> str:
        """Generate a unique hash from hardware details."""
        data = f"{hardware_info.get('cpu_id', '')}{hardware_info.get('mac', '')}"
        return hashlib.sha256(data.encode()).hexdigest()

    @staticmethod
    async def extract_bearer_token(token: str) -> Optional[str]:
        """Extract token from Bearer header."""
        if token.startswith("Bearer "):
            return token[7:]
        return None

    @staticmethod
    def validate_command_params(params: dict, allowed_keys: list) -> dict:
        """Sanitize incoming parameters against allowed keys."""
        cleaned = {}
        for key in params:
            if key in allowed_keys:
                cleaned[key] = params[key]
        return cleaned