from __future__ import annotations

import json
from functools import lru_cache
from typing import Any, Iterable
from uuid import uuid4

from huggingface_hub import InferenceClient

from app.core.config import get_settings
from app.models.schemas import (
    AIChatRequest,
    AIChatResponse,
    PlannedAction,
    RemoteCommandCreateRequest,
)
from app.services.supabase_client import get_repository

SYSTEM_PROMPT = """You are Neo AI, an expert Windows optimization copilot.
You can analyze telemetry, propose safe actions, and help operators manage remote Windows clients.
Keep answers concise, operational, and focused on Windows 10/11/12 performance, repair, and integrity."""

ACTION_RULES = (
    {
        "command_name": "smart_booster",
        "keywords": ("boost", "booster", "optimize", "lag", "slow", "lemot"),
        "reason": "Run RAM cleanup, DNS flush, temp cleanup, and process reprioritization.",
        "payload": {"profile": "balanced"},
        "priority": 70,
    },
    {
        "command_name": "flush_dns",
        "keywords": ("dns", "flush dns"),
        "reason": "Flush DNS cache to resolve network or name-resolution issues.",
        "payload": {},
        "priority": 60,
    },
    {
        "command_name": "health_check",
        "keywords": ("health check", "diagnostic", "sfc", "dism", "integrity"),
        "reason": "Run OS diagnostics including SFC, DISM, and integrity validation.",
        "payload": {"deep_scan": True},
        "priority": 80,
    },
    {
        "command_name": "clear_temp_files",
        "keywords": ("temp", "cache", "cleanup", "bersihkan"),
        "reason": "Remove temp files and stale cache to reclaim disk and reduce I/O overhead.",
        "payload": {"scope": "user_and_system"},
        "priority": 65,
    },
)


class NeoAIAgent:
    def __init__(self) -> None:
        self.settings = get_settings()
        self.repository = get_repository()
        self.client = InferenceClient(token=self.settings.hf_token) if self.settings.hf_token else None

    def handle_chat(self, payload: AIChatRequest) -> AIChatResponse:
        correlation_id = uuid4()
        client_context = self.repository.get_client_context(str(payload.client_id)) if payload.client_id else {}
        planned_actions = self.plan_actions(payload.effective_message)

        if payload.dispatch_actions and payload.client_id:
            for action in planned_actions:
                self.repository.create_remote_command(
                    RemoteCommandCreateRequest(
                        client_id=payload.client_id,
                        requested_by_user_id=payload.user_id,
                        source="ai",
                        command_name=action.command_name,
                        payload=action.payload,
                        priority=action.priority,
                        correlation_id=correlation_id,
                    )
                )
                action.dispatched = True

        reply = self.generate_reply(
            message=payload.effective_message,
            context=client_context,
            planned_actions=planned_actions,
            dispatch_actions=payload.dispatch_actions,
        )

        self.repository.log_action(
            client_id=str(payload.client_id) if payload.client_id else None,
            source="ai",
            action_type="chat",
            status_value="completed",
            summary="Processed Neo AI chat request",
            requested_by_user_id=str(payload.user_id) if payload.user_id else None,
            correlation_id=str(correlation_id),
            details={
                "message": payload.effective_message,
                "dispatch_actions": payload.dispatch_actions,
                "planned_actions": [action.model_dump() for action in planned_actions],
            },
        )

        return AIChatResponse(
            reply=reply,
            correlation_id=correlation_id,
            planned_actions=planned_actions,
            context_summary=client_context,
        )

    def plan_actions(self, message: str) -> list[PlannedAction]:
        normalized = message.lower()
        actions: list[PlannedAction] = []

        for rule in ACTION_RULES:
            if self._matches_rule(normalized, rule["keywords"]):
                actions.append(
                    PlannedAction(
                        command_name=rule["command_name"],
                        reason=rule["reason"],
                        payload=rule["payload"],
                        priority=rule["priority"],
                    )
                )

        return actions

    def generate_reply(
        self,
        *,
        message: str,
        context: dict[str, object],
        planned_actions: list[PlannedAction],
        dispatch_actions: bool,
    ) -> str:
        if self.client:
            try:
                response = self.client.chat_completion(
                    model=self.settings.hf_model_id,
                    messages=self._build_messages(message, context, planned_actions, dispatch_actions),
                    max_tokens=384,
                    temperature=0.2,
                )
                content = response.choices[0].message.content if response.choices else ""
                if content:
                    return content.strip()
            except Exception as exc:
                return self._generate_local_reply(
                    message=message,
                    context=context,
                    planned_actions=planned_actions,
                    dispatch_actions=dispatch_actions,
                    failure_reason=str(exc),
                )

        return self._generate_local_reply(
            message=message,
            context=context,
            planned_actions=planned_actions,
            dispatch_actions=dispatch_actions,
            failure_reason=None,
        )

    def _build_messages(
        self,
        message: str,
        context: dict[str, object],
        planned_actions: list[PlannedAction],
        dispatch_actions: bool,
    ) -> list[dict[str, str]]:
        return [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "user",
                "content": "\n".join(
                    [
                        f"Permintaan pengguna: {message}",
                        f"Konteks klien terbaru: {json.dumps(context, default=str)}",
                        "Planned actions: "
                        f"{json.dumps([action.model_dump() for action in planned_actions], default=str)}",
                        f"Dispatch actions sekarang: {dispatch_actions}",
                        "Balas dalam Bahasa Indonesia dengan analisis ringkas, langkah aman, dan catatan risiko bila perlu.",
                    ]
                ),
            },
        ]

    def _generate_local_reply(
        self,
        *,
        message: str,
        context: dict[str, object],
        planned_actions: list[PlannedAction],
        dispatch_actions: bool,
        failure_reason: str | None,
    ) -> str:
        telemetry = self._coerce_dict(context.get("latest_telemetry"))
        health = self._coerce_dict(context.get("latest_health"))
        observations: list[str] = []
        recommendations: list[str] = []

        cpu = self._safe_float(telemetry.get("cpu_percent"))
        ram = self._safe_float(telemetry.get("ram_percent"))
        disk = self._safe_float(telemetry.get("disk_usage_percent"))
        temp = self._safe_float(telemetry.get("temperature_celsius"))
        health_state = str(health.get("health_state") or health.get("disk_health") or "unknown")
        integrity_status = str(health.get("integrity_status") or "unknown")

        if cpu is not None:
            observations.append(f"CPU terakhir {cpu:.1f}%.")
            if cpu >= 85:
                recommendations.append("CPU tinggi. Jalankan Smart Booster dan cek proses latar belakang paling berat.")
        if ram is not None:
            observations.append(f"RAM terakhir {ram:.1f}%.")
            if ram >= 90:
                recommendations.append("RAM sudah kritis. Tutup proses non-esensial dan lakukan cleanup temp/cache.")
        if disk is not None:
            observations.append(f"Disk usage {disk:.1f}%.")
            if disk >= 90:
                recommendations.append("Storage hampir penuh. Bersihkan temp files dan audit folder terbesar.")
        if temp is not None:
            observations.append(f"Temperatur {temp:.1f}C.")
            if temp >= 80:
                recommendations.append("Temperatur tinggi. Kurangi beban proses dan cek pendingin perangkat.")

        if health_state != "unknown":
            observations.append(f"Status kesehatan sistem: {health_state}.")
        if integrity_status != "unknown":
            observations.append(f"Status integritas: {integrity_status}.")

        if not observations:
            observations.append("Belum ada telemetry lengkap, jadi analisis memakai sinyal terbatas dari permintaan pengguna.")

        if planned_actions:
            if dispatch_actions:
                recommendations.append(
                    "Tindakan sudah diantrikan: "
                    + ", ".join(action.command_name for action in planned_actions)
                    + "."
                )
            else:
                recommendations.append(
                    "Tindakan yang layak dijalankan: "
                    + ", ".join(action.command_name for action in planned_actions)
                    + "."
                )

        if not recommendations:
            recommendations.append("Lakukan Health Check jika gejala berulang, lalu cek log action terbaru untuk pola error.")

        note = ""
        if failure_reason:
            note = " Mode AI cloud tidak tersedia, jadi Neo AI memakai analisis lokal operasional."

        return " ".join(
            [
                f"Analisis Neo AI untuk permintaan '{message}':",
                " ".join(observations),
                "Rekomendasi utama: " + " ".join(recommendations),
                note,
            ]
        ).strip()

    @staticmethod
    def _matches_rule(message: str, keywords: Iterable[str]) -> bool:
        return any(keyword in message for keyword in keywords)

    @staticmethod
    def _coerce_dict(value: Any) -> dict[str, Any]:
        return value if isinstance(value, dict) else {}

    @staticmethod
    def _safe_float(value: Any) -> float | None:
        try:
            return None if value is None else float(value)
        except (TypeError, ValueError):
            return None


@lru_cache
def get_ai_agent() -> NeoAIAgent:
    return NeoAIAgent()
