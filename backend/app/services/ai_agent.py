from __future__ import annotations

import json
from functools import lru_cache
from typing import Iterable
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
        self.client = (
            InferenceClient(token=self.settings.hf_token)
            if self.settings.hf_token
            else None
        )

    def handle_chat(self, payload: AIChatRequest) -> AIChatResponse:
        correlation_id = uuid4()
        client_context = (
            self.repository.get_client_context(str(payload.client_id))
            if payload.client_id
            else {}
        )
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
    ) -> str:
        prompt = self._build_prompt(message, context, planned_actions)

        if not self.client:
            return (
                "Neo AI backend aktif. HF_TOKEN belum diatur, jadi respons ini memakai fallback lokal. "
                "Tetapkan HF_TOKEN dan HF_MODEL_ID untuk mengaktifkan generasi dari Hugging Face Inference."
            )

        try:
            return self.client.text_generation(
                prompt=prompt,
                model=self.settings.hf_model_id,
                max_new_tokens=384,
                temperature=0.2,
                return_full_text=False,
            ).strip()
        except Exception as exc:
            return (
                "Model Hugging Face tidak merespons. "
                f"Fallback aktif dengan error: {exc}"
            )

    def _build_prompt(
        self,
        message: str,
        context: dict[str, object],
        planned_actions: list[PlannedAction],
    ) -> str:
        return "\n".join(
            [
                SYSTEM_PROMPT,
                "",
                f"User request: {message}",
                f"Latest client context: {json.dumps(context, default=str)}",
                "Planned actions: "
                f"{json.dumps([action.model_dump() for action in planned_actions], default=str)}",
                "",
                "Respond in Bahasa Indonesia with operational guidance and risk notes if needed.",
                "Assistant:",
            ]
        )

    @staticmethod
    def _matches_rule(message: str, keywords: Iterable[str]) -> bool:
        return any(keyword in message for keyword in keywords)


@lru_cache
def get_ai_agent() -> NeoAIAgent:
    return NeoAIAgent()
