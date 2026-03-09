from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class ClientRegisterRequest(BaseModel):
    owner_user_id: UUID | None = None
    device_name: str | None = None
    os_version: str | None = None
    app_version: str | None = None
    architecture: str | None = None
    hardware_fingerprint: str = Field(min_length=16, max_length=512)
    metadata: dict[str, Any] = Field(default_factory=dict)


class ClientRegisterResponse(BaseModel):
    client_id: UUID
    client_api_key: str
    fingerprint_hash: str
    issued_at: datetime


class AuthenticatedClient(BaseModel):
    client_id: UUID
    owner_user_id: UUID | None = None
    fingerprint_hash: str
    status: str
    device_name: str | None = None


class TelemetryPayload(BaseModel):
    cpu_percent: float | None = Field(default=None, ge=0, le=100)
    ram_percent: float | None = Field(default=None, ge=0, le=100)
    gpu_percent: float | None = Field(default=None, ge=0, le=100)
    disk_usage_percent: float | None = Field(default=None, ge=0, le=100)
    disk_read_mbps: float | None = Field(default=None, ge=0)
    disk_write_mbps: float | None = Field(default=None, ge=0)
    temperature_celsius: float | None = None
    process_count: int | None = Field(default=None, ge=0)
    top_processes: list[dict[str, Any]] = Field(default_factory=list)
    snapshot: dict[str, Any] = Field(default_factory=dict)


class TelemetryIngestResponse(BaseModel):
    status: Literal["recorded"]
    alerts: list[str] = Field(default_factory=list)


class SystemHealthPayload(BaseModel):
    overall_score: int | None = Field(default=None, ge=0, le=100)
    health_state: Literal["healthy", "warning", "critical"] = "healthy"
    sfc_status: str | None = None
    dism_status: str | None = None
    thermal_status: str | None = None
    integrity_status: str | None = None
    issues: list[dict[str, Any]] = Field(default_factory=list)
    recommendations: list[str] = Field(default_factory=list)
    report: dict[str, Any] = Field(default_factory=dict)


class SystemHealthResponse(BaseModel):
    status: Literal["recorded"]


class RemoteCommandCreateRequest(BaseModel):
    client_id: UUID
    requested_by_user_id: UUID | None = None
    source: Literal["ai", "user", "system"] = "ai"
    command_name: str = Field(min_length=3, max_length=100)
    payload: dict[str, Any] = Field(default_factory=dict)
    priority: int = Field(default=50, ge=0, le=100)
    correlation_id: UUID | None = None


class RemoteCommandQueuedResponse(BaseModel):
    command_id: UUID
    status: Literal["queued"]
    correlation_id: UUID


class RemoteCommandPollResponse(BaseModel):
    status: Literal["idle", "pending"]
    command_id: UUID | None = None
    command_name: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    correlation_id: UUID | None = None


class CommandResultRequest(BaseModel):
    command_id: UUID
    status: Literal["completed", "failed", "cancelled"]
    output: dict[str, Any] = Field(default_factory=dict)
    error_message: str | None = None


class PlannedAction(BaseModel):
    command_name: str
    reason: str
    payload: dict[str, Any] = Field(default_factory=dict)
    priority: int = Field(default=50, ge=0, le=100)
    dispatched: bool = False


class AIChatRequest(BaseModel):
    message: str | None = None
    voice_transcript: str | None = None
    client_id: UUID | None = None
    user_id: UUID | None = None
    dispatch_actions: bool = False
    context: dict[str, Any] = Field(default_factory=dict)

    @model_validator(mode="after")
    def validate_message(self) -> "AIChatRequest":
        if not (self.message or self.voice_transcript):
            raise ValueError("message atau voice_transcript wajib diisi")
        return self

    @property
    def effective_message(self) -> str:
        return (self.voice_transcript or self.message or "").strip()


class AIChatResponse(BaseModel):
    reply: str
    correlation_id: UUID
    planned_actions: list[PlannedAction] = Field(default_factory=list)
    context_summary: dict[str, Any] = Field(default_factory=dict)
