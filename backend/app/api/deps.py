from typing import Annotated

from fastapi import Header, HTTPException, status

from app.core.security import (
    CLIENT_API_KEY_HEADER,
    CLIENT_ID_HEADER,
    HARDWARE_FINGERPRINT_HEADER,
)
from app.models.schemas import AuthenticatedClient
from app.services.supabase_client import SupabaseRepository, get_repository


def get_repo() -> SupabaseRepository:
    return get_repository()


def get_current_client(
    x_client_id: Annotated[str | None, Header(alias=CLIENT_ID_HEADER)] = None,
    x_client_api_key: Annotated[str | None, Header(alias=CLIENT_API_KEY_HEADER)] = None,
    x_hardware_fingerprint: Annotated[str | None, Header(alias=HARDWARE_FINGERPRINT_HEADER)] = None,
) -> AuthenticatedClient:
    if not x_client_id or not x_client_api_key or not x_hardware_fingerprint:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing client authentication headers",
        )

    repo = get_repository()
    return repo.authenticate_client(
        client_id=x_client_id,
        api_key=x_client_api_key,
        hardware_fingerprint=x_hardware_fingerprint,
    )
