from fastapi import APIRouter, Depends, Request

from app.api.deps import get_current_client, get_repo
from app.core.config import get_settings
from app.models.schemas import (
    AuthenticatedClient,
    TelemetryIngestResponse,
    TelemetryPayload,
)
from app.services.supabase_client import SupabaseRepository

router = APIRouter()


def build_alerts(payload: TelemetryPayload) -> list[str]:
    settings = get_settings()
    alerts: list[str] = []

    if payload.cpu_percent is not None and payload.cpu_percent >= settings.cpu_alert_threshold:
        alerts.append(f"CPU usage crossed {settings.cpu_alert_threshold}%")
    if payload.ram_percent is not None and payload.ram_percent >= settings.ram_alert_threshold:
        alerts.append(f"RAM usage crossed {settings.ram_alert_threshold}%")
    if payload.gpu_percent is not None and payload.gpu_percent >= settings.gpu_alert_threshold:
        alerts.append(f"GPU usage crossed {settings.gpu_alert_threshold}%")
    if (
        payload.disk_usage_percent is not None
        and payload.disk_usage_percent >= settings.disk_alert_threshold
    ):
        alerts.append(f"Disk usage crossed {settings.disk_alert_threshold}%")

    return alerts


@router.post("/push", response_model=TelemetryIngestResponse, summary="Push telemetry snapshot")
def push_telemetry(
    payload: TelemetryPayload,
    request: Request,
    client: AuthenticatedClient = Depends(get_current_client),
    repo: SupabaseRepository = Depends(get_repo),
) -> TelemetryIngestResponse:
    alerts = build_alerts(payload)
    client_ip = request.client.host if request.client else None
    repo.insert_telemetry(client=client, payload=payload, alerts=alerts, client_ip=client_ip)
    return TelemetryIngestResponse(status="recorded", alerts=alerts)
