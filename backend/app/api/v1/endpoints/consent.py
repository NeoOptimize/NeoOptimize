from fastapi import APIRouter, Depends

from app.api.deps import get_current_client, get_repo
from app.models.schemas import AuthenticatedClient, ConsentUpdateRequest, ConsentUpdateResponse
from app.services.supabase_client import SupabaseRepository

router = APIRouter()


@router.post("/update", response_model=ConsentUpdateResponse, summary="Update client consent")
def update_consent(
    payload: ConsentUpdateRequest,
    client: AuthenticatedClient = Depends(get_current_client),
    repo: SupabaseRepository = Depends(get_repo),
) -> ConsentUpdateResponse:
    repo.update_client_consent(client=client, payload=payload)
    return ConsentUpdateResponse(status="recorded")
