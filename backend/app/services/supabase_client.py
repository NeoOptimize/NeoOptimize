from __future__ import annotations

from datetime import datetime, timezone
from functools import lru_cache
from typing import Any
from uuid import UUID, uuid4

from fastapi import HTTPException, status
from supabase import Client, create_client

from app.core.config import get_settings
from app.core.security import (
    constant_time_equals,
    generate_client_credentials,
    hash_api_key,
    hash_hardware_fingerprint,
)
from app.models.schemas import (
    AuthenticatedClient,
    ClientRegisterRequest,
    CommandResultRequest,
    RemoteCommandCreateRequest,
    SystemHealthPayload,
    TelemetryPayload,
)


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@lru_cache
def get_supabase() -> Client:
    settings = get_settings()
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


class SupabaseRepository:
    def __init__(self, client: Client) -> None:
        self.client = client

    def register_client(self, payload: ClientRegisterRequest) -> dict[str, Any]:
        fingerprint_hash = hash_hardware_fingerprint(payload.hardware_fingerprint)
        client_id, client_api_key, client_api_key_hash = generate_client_credentials()

        existing = (
            self.client.table("clients")
            .select("id")
            .eq("hardware_fingerprint_hash", fingerprint_hash)
            .limit(1)
            .execute()
        )

        base_record = {
            "owner_user_id": str(payload.owner_user_id) if payload.owner_user_id else None,
            "client_api_key_hash": client_api_key_hash,
            "hardware_fingerprint_hash": fingerprint_hash,
            "device_name": payload.device_name,
            "os_version": payload.os_version,
            "app_version": payload.app_version,
            "architecture": payload.architecture,
            "status": "active",
            "last_seen_at": utcnow_iso(),
            "last_heartbeat_at": utcnow_iso(),
            "metadata": payload.metadata,
        }

        if existing.data:
            client_id = existing.data[0]["id"]
            (
                self.client.table("clients")
                .update(base_record)
                .eq("id", client_id)
                .execute()
            )
        else:
            (
                self.client.table("clients")
                .insert(
                    {
                        "id": client_id,
                        **base_record,
                    }
                )
                .execute()
            )

        self.log_action(
            client_id=client_id,
            source="system",
            action_type="register_client",
            status_value="completed",
            summary="Issued client credentials",
            details={
                "device_name": payload.device_name,
                "app_version": payload.app_version,
                "os_version": payload.os_version,
            },
        )

        return {
            "client_id": client_id,
            "client_api_key": client_api_key,
            "fingerprint_hash": fingerprint_hash,
            "issued_at": datetime.now(timezone.utc),
        }

    def authenticate_client(
        self,
        *,
        client_id: str,
        api_key: str,
        hardware_fingerprint: str,
    ) -> AuthenticatedClient:
        response = (
            self.client.table("clients")
            .select("id, owner_user_id, hardware_fingerprint_hash, client_api_key_hash, status, device_name")
            .eq("id", client_id)
            .limit(1)
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Unknown client_id",
            )

        record = response.data[0]
        fingerprint_hash = hash_hardware_fingerprint(hardware_fingerprint)
        if not constant_time_equals(record["hardware_fingerprint_hash"], fingerprint_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Hardware fingerprint mismatch",
            )

        api_key_hash = hash_api_key(api_key)
        if not constant_time_equals(record["client_api_key_hash"], api_key_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid client API key",
            )

        if record["status"] not in {"active", "degraded"}:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Client status '{record['status']}' is not allowed",
            )

        (
            self.client.table("clients")
            .update(
                {
                    "last_seen_at": utcnow_iso(),
                    "last_heartbeat_at": utcnow_iso(),
                }
            )
            .eq("id", client_id)
            .execute()
        )

        return AuthenticatedClient(
            client_id=UUID(record["id"]),
            owner_user_id=UUID(record["owner_user_id"]) if record["owner_user_id"] else None,
            fingerprint_hash=fingerprint_hash,
            status=record["status"],
            device_name=record.get("device_name"),
        )

    def insert_telemetry(
        self,
        *,
        client: AuthenticatedClient,
        payload: TelemetryPayload,
        alerts: list[str],
    ) -> None:
        record = payload.model_dump()
        snapshot = record.pop("snapshot")
        top_processes = record.pop("top_processes")

        (
            self.client.table("telemetry_logs")
            .insert(
                {
                    "client_id": str(client.client_id),
                    **record,
                    "alert_state": "alert" if alerts else "normal",
                    "alert_reasons": alerts,
                    "snapshot": {
                        **snapshot,
                        "top_processes": top_processes,
                    },
                    "recorded_at": utcnow_iso(),
                }
            )
            .execute()
        )

        if alerts:
            self.log_action(
                client_id=str(client.client_id),
                source="system",
                action_type="smart_monitor_alert",
                status_value="completed",
                summary="Telemetry threshold breached",
                details={"alerts": alerts},
            )

    def insert_system_health(
        self,
        *,
        client: AuthenticatedClient,
        payload: SystemHealthPayload,
    ) -> None:
        (
            self.client.table("system_health")
            .insert(
                {
                    "client_id": str(client.client_id),
                    **payload.model_dump(),
                    "recorded_at": utcnow_iso(),
                }
            )
            .execute()
        )

        self.log_action(
            client_id=str(client.client_id),
            source="client",
            action_type="health_check",
            status_value="completed",
            summary="System health report received",
            details=payload.model_dump(),
        )

    def create_remote_command(self, payload: RemoteCommandCreateRequest) -> dict[str, Any]:
        correlation_id = payload.correlation_id or uuid4()
        response = (
            self.client.table("remote_commands")
            .insert(
                {
                    "client_id": str(payload.client_id),
                    "requested_by_user_id": (
                        str(payload.requested_by_user_id)
                        if payload.requested_by_user_id
                        else None
                    ),
                    "source": payload.source,
                    "command_name": payload.command_name,
                    "payload": payload.payload,
                    "priority": payload.priority,
                    "status": "queued",
                    "correlation_id": str(correlation_id),
                    "requested_at": utcnow_iso(),
                }
            )
            .execute()
        )

        command = response.data[0]
        self.log_action(
            client_id=str(payload.client_id),
            source=payload.source,
            action_type=payload.command_name,
            status_value="queued",
            summary=f"Queued remote command '{payload.command_name}'",
            requested_by_user_id=(
                str(payload.requested_by_user_id) if payload.requested_by_user_id else None
            ),
            correlation_id=str(correlation_id),
            details=payload.payload,
        )
        return command

    def poll_next_command(self, client_id: str) -> dict[str, Any] | None:
        response = (
            self.client.table("remote_commands")
            .select("id, command_name, payload, correlation_id, status, priority, requested_at")
            .eq("client_id", client_id)
            .in_("status", ["queued", "retry"])
            .order("priority", desc=True)
            .order("requested_at")
            .limit(1)
            .execute()
        )

        if not response.data:
            return None

        command = response.data[0]
        (
            self.client.table("remote_commands")
            .update(
                {
                    "status": "dispatched",
                    "claimed_at": utcnow_iso(),
                }
            )
            .eq("id", command["id"])
            .execute()
        )
        command["status"] = "dispatched"
        return command

    def complete_remote_command(
        self,
        *,
        client: AuthenticatedClient,
        payload: CommandResultRequest,
    ) -> str:
        response = (
            self.client.table("remote_commands")
            .select("id, client_id, command_name, correlation_id")
            .eq("id", str(payload.command_id))
            .limit(1)
            .execute()
        )

        if not response.data:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Command not found")

        command = response.data[0]
        if command["client_id"] != str(client.client_id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Command does not belong to client",
            )

        (
            self.client.table("remote_commands")
            .update(
                {
                    "status": payload.status,
                    "completed_at": utcnow_iso(),
                    "result_payload": payload.output,
                    "error_message": payload.error_message,
                }
            )
            .eq("id", str(payload.command_id))
            .execute()
        )

        self.log_action(
            client_id=str(client.client_id),
            source="client",
            action_type=command["command_name"],
            status_value=payload.status,
            summary=f"Remote command '{command['command_name']}' finished",
            correlation_id=command["correlation_id"],
            details=payload.output,
            error_message=payload.error_message,
        )
        return payload.status

    def get_client_context(self, client_id: str) -> dict[str, Any]:
        telemetry = (
            self.client.table("telemetry_logs")
            .select(
                "cpu_percent, ram_percent, gpu_percent, disk_usage_percent, "
                "temperature_celsius, alert_state, recorded_at"
            )
            .eq("client_id", client_id)
            .order("recorded_at", desc=True)
            .limit(1)
            .execute()
        )
        health = (
            self.client.table("system_health")
            .select(
                "overall_score, health_state, sfc_status, dism_status, "
                "thermal_status, integrity_status, recorded_at"
            )
            .eq("client_id", client_id)
            .order("recorded_at", desc=True)
            .limit(1)
            .execute()
        )
        return {
            "latest_telemetry": telemetry.data[0] if telemetry.data else {},
            "latest_health": health.data[0] if health.data else {},
        }

    def log_action(
        self,
        *,
        client_id: str | None,
        source: str,
        action_type: str,
        status_value: str,
        summary: str,
        requested_by_user_id: str | None = None,
        correlation_id: str | None = None,
        details: dict[str, Any] | None = None,
        error_message: str | None = None,
    ) -> None:
        self.client.table("action_logs").insert(
            {
                "client_id": client_id,
                "requested_by_user_id": requested_by_user_id,
                "source": source,
                "action_type": action_type,
                "status": status_value,
                "summary": summary,
                "correlation_id": correlation_id or str(uuid4()),
                "details": details or {},
                "error_message": error_message,
                "created_at": utcnow_iso(),
            }
        ).execute()


@lru_cache
def get_repository() -> SupabaseRepository:
    return SupabaseRepository(get_supabase())
