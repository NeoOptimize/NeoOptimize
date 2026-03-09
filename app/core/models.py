from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from uuid import UUID

# Auth
class ClientRegisterRequest(BaseModel):
    hardware_fingerprint: str
    name: Optional[str] = None

class ClientRegisterResponse(BaseModel):
    client_id: str
    client_api_key: str

# Commands
class CommandPollResponse(BaseModel):
    id: str
    tool: str
    params: dict

class CommandResult(BaseModel):
    id: str
    result: str
    status: str = "completed"

# Telemetry
class TelemetryData(BaseModel):
    cpu_percent: Optional[float] = None
    ram_percent: Optional[float] = None
    gpu_percent: Optional[float] = None
    disk_io_read_bytes: Optional[int] = None
    disk_io_write_bytes: Optional[int] = None
    temperature_celsius: Optional[float] = None

# Health
class HealthCheckData(BaseModel):
    sfc_status: Optional[str] = None
    dism_status: Optional[str] = None
    thermal_status: Optional[str] = None
    disk_health: Optional[str] = None
    uptime_seconds: Optional[int] = None

# Feedback
class FeedbackCreate(BaseModel):
    message_id: UUID
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = None

# Chat
class ChatRequest(BaseModel):
    message: str
    client_id: Optional[str] = None

class ChatResponse(BaseModel):
    response: str
    context_used: List[str] = []