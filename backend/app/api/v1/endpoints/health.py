from fastapi import APIRouter, Depends

from app.api.deps import get_current_client, get_repo
from app.models.schemas import (
    AuthenticatedClient,
    SystemHealthPayload,
    SystemHealthResponse,
)
from app.services.supabase_client import SupabaseRepository

router = APIRouter()


@router.post("/report", response_model=SystemHealthResponse, summary="Push health diagnostics")
def report_health(
    payload: SystemHealthPayload,
    client: AuthenticatedClient = Depends(get_current_client),
    repo: SupabaseRepository = Depends(get_repo),
) -> SystemHealthResponse:
    repo.insert_system_health(client=client, payload=payload)
    return SystemHealthResponse(status="recorded")
