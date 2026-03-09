from __future__ import annotations

import hashlib
import json
import math
import re
from functools import lru_cache
from typing import Any, Iterable
from uuid import uuid4

from huggingface_hub import InferenceClient

from app.core.config import get_settings
from app.models.schemas import (
    AIChatRequest,
    AIChatResponse,
    AIFeedbackRequest,
    AIFeedbackResponse,
    MemoryMatch,
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
        "keywords": ("boost", "booster", "optimize", "lag", "slow", "lemot", "lambat", "startup"),
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
        "keywords": ("health check", "diagnostic", "sfc", "dism", "integrity", "cek kesehatan", "scan", "rusak"),
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

TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_]+", re.ASCII)
EMBEDDING_DIMENSION = 384


class NeoAIAgent:
    def __init__(self) -> None:
        self.settings = get_settings()
        self.repository = get_repository()
        self.client = InferenceClient(token=self.settings.hf_token) if self.settings.hf_token else None

    def handle_chat(self, payload: AIChatRequest) -> AIChatResponse:
        correlation_id = uuid4()
        client_id = str(payload.client_id) if payload.client_id else None
        user_id = str(payload.user_id) if payload.user_id else None
        message = payload.effective_message
        query_embedding = self._build_embedding(message)
        memory_hits_raw = self.repository.search_memory(
            query_embedding=query_embedding,
            client_id=client_id,
        )
        memory_hits = [self._to_memory_match(item) for item in memory_hits_raw]
        client_context = self.repository.get_client_context(client_id) if client_id else {}
        planned_actions = self.plan_actions(message)

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
            message=message,
            context=client_context,
            memory_hits=memory_hits,
            planned_actions=planned_actions,
            dispatch_actions=payload.dispatch_actions,
        )
        memory_id = self.repository.store_memory(
            user_message=message,
            ai_response=reply,
            embedding=query_embedding,
            client_id=client_id,
        )

        context_summary = {
            **client_context,
            "memory_match_count": len(memory_hits),
            "memory_matches": [
                {
                    "message_id": str(match.message_id),
                    "similarity": match.similarity,
                    "user_message": match.user_message,
                }
                for match in memory_hits
            ],
        }

        self.repository.log_action(
            client_id=client_id,
            source="ai",
            action_type="chat",
            status_value="completed",
            summary="Processed Neo AI chat request",
            requested_by_user_id=user_id,
            correlation_id=str(correlation_id),
            details={
                "message": message,
                "dispatch_actions": payload.dispatch_actions,
                "planned_actions": [action.model_dump() for action in planned_actions],
                "memory_id": memory_id,
                "memory_match_count": len(memory_hits),
            },
        )

        return AIChatResponse(
            reply=reply,
            correlation_id=correlation_id,
            memory_id=memory_id,
            planned_actions=planned_actions,
            memory_hits=memory_hits,
            context_summary=context_summary,
        )

    def record_feedback(self, payload: AIFeedbackRequest) -> AIFeedbackResponse:
        feedback = self.repository.store_feedback(
            message_id=str(payload.message_id),
            rating=payload.rating,
            comment=(payload.comment or "").strip() or None,
            client_id=str(payload.client_id) if payload.client_id else None,
            requested_by_user_id=str(payload.user_id) if payload.user_id else None,
        )
        return AIFeedbackResponse(status="recorded", feedback_id=feedback["id"])

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
        memory_hits: list[MemoryMatch],
        planned_actions: list[PlannedAction],
        dispatch_actions: bool,
    ) -> str:
        if self.client:
            try:
                response = self.client.chat_completion(
                    model=self.settings.hf_model_id,
                    messages=self._build_messages(message, context, memory_hits, planned_actions, dispatch_actions),
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
                    memory_hits=memory_hits,
                    planned_actions=planned_actions,
                    dispatch_actions=dispatch_actions,
                    failure_reason=str(exc),
                )

        return self._generate_local_reply(
            message=message,
            context=context,
            memory_hits=memory_hits,
            planned_actions=planned_actions,
            dispatch_actions=dispatch_actions,
            failure_reason=None,
        )

    def _build_messages(
        self,
        message: str,
        context: dict[str, object],
        memory_hits: list[MemoryMatch],
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
                        "Memori interaksi relevan: "
                        f"{json.dumps([self._memory_to_prompt(item) for item in memory_hits], default=str)}",
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
        memory_hits: list[MemoryMatch],
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

        memory_note = self._summarize_memory_hits(memory_hits)
        if memory_note:
            observations.append(memory_note)

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

    def _build_embedding(self, text: str) -> list[float]:
        normalized_text = text.lower().strip()
        tokens = TOKEN_PATTERN.findall(normalized_text)
        char_window_source = re.sub(r"\s+", " ", normalized_text)
        features: list[str] = list(tokens)
        features.extend(f"{left}_{right}" for left, right in zip(tokens, tokens[1:]))
        features.extend(
            char_window_source[index : index + 3]
            for index in range(max(0, len(char_window_source) - 2))
            if char_window_source[index : index + 3].strip()
        )

        if not features:
            features = [normalized_text or "neooptimize"]

        vector = [0.0] * EMBEDDING_DIMENSION
        for feature in features:
            digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=32).digest()
            for offset in range(0, 24, 3):
                bucket = int.from_bytes(digest[offset : offset + 2], "big") % EMBEDDING_DIMENSION
                sign = 1.0 if digest[offset + 2] % 2 == 0 else -1.0
                weight = 1.5 if offset == 0 and "_" not in feature else 1.0
                vector[bucket] += sign * weight

        magnitude = math.sqrt(sum(value * value for value in vector))
        if magnitude == 0:
            vector[0] = 1.0
            magnitude = 1.0

        return [round(value / magnitude, 6) for value in vector]

    def _summarize_memory_hits(self, memory_hits: list[MemoryMatch]) -> str:
        if not memory_hits:
            return ""

        top_hits = memory_hits[:2]
        summaries = []
        for hit in top_hits:
            snippet = (hit.ai_response or hit.user_message or "").strip().replace("\n", " ")
            if len(snippet) > 120:
                snippet = snippet[:117] + "..."
            similarity = f"{(hit.similarity or 0.0):.2f}"
            summaries.append(f"similarity {similarity}: {snippet}")
        return "Pola serupa dari memori Neo AI: " + " | ".join(summaries)

    @staticmethod
    def _to_memory_match(value: dict[str, Any]) -> MemoryMatch:
        return MemoryMatch(
            message_id=value["id"],
            user_message=value.get("user_message"),
            ai_response=value.get("ai_response"),
            similarity=(round(float(value["similarity"]), 4) if value.get("similarity") is not None else None),
        )

    @staticmethod
    def _memory_to_prompt(value: MemoryMatch) -> dict[str, Any]:
        return {
            "message_id": str(value.message_id),
            "user_message": value.user_message,
            "ai_response": value.ai_response,
            "similarity": value.similarity,
        }

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
