from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "NeoOptimasi AI Backend"
    app_version: str = "0.1.0"
    app_env: str = "development"
    debug: bool = False
    app_host: str = "0.0.0.0"
    app_port: int = 7860
    log_level: str = "INFO"
    allowed_origins: list[str] | str = Field(default="*")

    supabase_url: str = Field(validation_alias="SUPABASE_URL")
    supabase_service_role_key: str = Field(validation_alias="SUPABASE_SERVICE_ROLE_KEY")
    supabase_anon_key: str | None = Field(default=None, validation_alias="SUPABASE_ANON_KEY")

    hf_token: str | None = Field(default=None, validation_alias="HF_TOKEN")
    hf_model_id: str = Field(
        default="Qwen/Qwen2.5-7B-Instruct",
        validation_alias="HF_MODEL_ID",
    )

    cpu_alert_threshold: float = Field(default=85.0, validation_alias="CPU_ALERT_THRESHOLD")
    ram_alert_threshold: float = Field(default=90.0, validation_alias="RAM_ALERT_THRESHOLD")
    gpu_alert_threshold: float = Field(default=90.0, validation_alias="GPU_ALERT_THRESHOLD")
    disk_alert_threshold: float = Field(default=90.0, validation_alias="DISK_ALERT_THRESHOLD")
    websocket_heartbeat_seconds: int = Field(
        default=30,
        validation_alias="WEBSOCKET_HEARTBEAT_SECONDS",
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @field_validator("debug", mode="before")
    @classmethod
    def parse_debug(cls, value: object) -> bool:
        if isinstance(value, bool):
            return value

        normalized = str(value).strip().lower()
        if normalized in {"1", "true", "yes", "on", "debug", "development"}:
            return True
        if normalized in {"0", "false", "no", "off", "release", "production", "prod"}:
            return False
        return bool(value)

    @field_validator("allowed_origins", mode="before")
    @classmethod
    def parse_allowed_origins(cls, value: list[str] | str) -> list[str]:
        if isinstance(value, list):
            return value
        if value.strip() == "*":
            return ["*"]
        return [item.strip() for item in value.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
