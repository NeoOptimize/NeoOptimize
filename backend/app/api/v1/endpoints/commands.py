from fastapi import APIRouter, Depends, status

from app.api.deps import get_current_client, get_repo
from app.models.schemas import (
    AuthenticatedClient,
    CommandResultRequest,
    RemoteCommandCreateRequest,
    RemoteCommandPollResponse,
    RemoteCommandQueuedResponse,
)
from app.services.supabase_client import SupabaseRepository

router = APIRouter()


@router.post(
    "/enqueue",
    response_model=RemoteCommandQueuedResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Queue a remote command for a client",
)
def enqueue_command(
    payload: RemoteCommandCreateRequest,
    repo: SupabaseRepository = Depends(get_repo),
) -> RemoteCommandQueuedResponse:
    command = repo.create_remote_command(payload)
    return RemoteCommandQueuedResponse(
        command_id=command["id"],
        status=command["status"],
        correlation_id=command["correlation_id"],
    )


@router.post("/poll", response_model=RemoteCommandPollResponse, summary="Poll next command")
def poll_command(
    client: AuthenticatedClient = Depends(get_current_client),
    repo: SupabaseRepository = Depends(get_repo),
) -> RemoteCommandPollResponse:
    command = repo.poll_next_command(str(client.client_id))
    if not command:
        return RemoteCommandPollResponse(status="idle")

    return RemoteCommandPollResponse(
        status="pending",
        command_id=command["id"],
        command_name=command["command_name"],
        payload=command.get("payload") or {},
        correlation_id=command["correlation_id"],
    )


@router.post("/result", summary="Post command execution result")
def submit_command_result(
    payload: CommandResultRequest,
    client: AuthenticatedClient = Depends(get_current_client),
    repo: SupabaseRepository = Depends(get_repo),
) -> dict[str, str]:
    status_value = repo.complete_remote_command(client=client, payload=payload)
    return {
        "command_id": str(payload.command_id),
        "status": status_value,
    }
