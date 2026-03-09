from fastapi import APIRouter, Depends, status

from app.api.deps import get_repo
from app.models.schemas import ClientRegisterRequest, ClientRegisterResponse
from app.services.supabase_client import SupabaseRepository

router = APIRouter()


@router.post(
    "/register",
    response_model=ClientRegisterResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register or rotate a Windows client credential",
)
def register_client(
    payload: ClientRegisterRequest,
    repo: SupabaseRepository = Depends(get_repo),
) -> ClientRegisterResponse:
    data = repo.register_client(payload)
    return ClientRegisterResponse(**data)
