"""
NeoCortex hybrid ML core for NeoOptimize.

The model is intentionally local, deterministic, and dependency-light. It learns
robust baselines from authorized telemetry history, flags anomalies, scores
endpoint health, and proposes safe optimizer actions without collecting secrets
or sensitive media.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from math import isfinite
from statistics import median
from typing import Any, Dict, Iterable, List, Optional


MODEL_NAME = "neocortex-hybrid-v1"
SAFE_COMMANDS = {
    "OPTIMIZE",
    "CLEAN",
    "DEEP_SCAN",
    "UPDATES",
    "PRIVACY",
    "POWER",
    "SERVICES",
    "SECURITY_SCAN",
    "SYSTEM_DIAGNOSTICS",
    "NETWORK_TEST",
    "COLLECT",
    "SYSINFO",
    "PING",
}


def _num(*values: Any) -> Optional[float]:
    for value in values:
        if value is None or value == "":
            continue
        try:
            parsed = float(value)
        except (TypeError, ValueError):
            continue
        if isfinite(parsed):
            return parsed
    return None


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _mad(values: Iterable[float], center: float) -> Optional[float]:
    deviations = [abs(value - center) for value in values if isfinite(value)]
    if not deviations:
        return None
    value = median(deviations)
    return value if value > 0 else None


def _score_higher_bad(value: Optional[float], warn: float, critical: float) -> float:
    if value is None:
        return 100
    if value <= warn:
        return 100
    if value >= critical:
        return 35
    return _clamp(100 - ((value - warn) / (critical - warn)) * 65, 35, 100)


def _score_lower_bad(value: Optional[float], warn: float, critical: float) -> float:
    if value is None:
        return 100
    if value >= warn:
        return 100
    if value <= critical:
        return 35
    return _clamp(35 + ((value - critical) / (warn - critical)) * 65, 35, 100)


def normalize_telemetry(sample: Dict[str, Any], agent: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    agent = agent or {}
    ram_used_mb = _num(sample.get("ram_used_mb"), sample.get("r"), sample.get("ram_mb"))
    ram_total_mb = _num(agent.get("ram_mb"), sample.get("ram_total_mb"), sample.get("total_ram_mb"))
    ram_pct = _num(sample.get("ram_pct"), sample.get("memory_usage"), sample.get("memory_pct"))
    if ram_pct is None and ram_used_mb is not None and ram_total_mb:
        ram_pct = (ram_used_mb / ram_total_mb) * 100

    return {
        "ts": sample.get("ts") or sample.get("timestamp") or datetime.now(timezone.utc).isoformat(),
        "cpu_pct": _num(sample.get("cpu_pct"), sample.get("c"), sample.get("cpu_usage")),
        "ram_used_mb": ram_used_mb,
        "ram_pct": ram_pct,
        "disk_free_gb": _num(sample.get("disk_free_gb"), sample.get("d"), sample.get("free_disk_gb")),
        "disk_used_pct": _num(sample.get("disk_used_pct"), sample.get("disk_usage")),
        "net_rx_kbps": _num(sample.get("net_rx_kbps"), sample.get("rx")),
        "net_tx_kbps": _num(sample.get("net_tx_kbps"), sample.get("tx")),
        "gpu_pct": _num(sample.get("gpu_pct"), sample.get("g")),
        "gpu_temp_c": _num(sample.get("gpu_temp_c"), sample.get("gt")),
        "cpu_temp_c": _num(sample.get("cpu_temp_c"), sample.get("ct")),
    }


@dataclass(frozen=True)
class Feature:
    key: str
    label: str


class NeoCortexModel:
    """Robust baseline anomaly detector plus health/recommendation layer."""

    features = (
        Feature("cpu_pct", "CPU"),
        Feature("ram_pct", "RAM"),
        Feature("disk_free_gb", "Disk free"),
        Feature("net_rx_kbps", "Network RX"),
        Feature("net_tx_kbps", "Network TX"),
        Feature("gpu_pct", "GPU"),
        Feature("gpu_temp_c", "GPU temperature"),
        Feature("cpu_temp_c", "CPU temperature"),
    )

    def analyze(
        self,
        latest: Dict[str, Any],
        history: Optional[List[Dict[str, Any]]] = None,
        alerts: Optional[List[Dict[str, Any]]] = None,
        agent: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        agent = agent or {}
        normalized_latest = normalize_telemetry(latest, agent)
        normalized_history = [normalize_telemetry(row, agent) for row in history or []]
        alerts = alerts or []

        anomaly = self._detect_anomaly(normalized_latest, normalized_history)
        components = self._components(normalized_latest, alerts, anomaly["score"])
        score = round(
            components["cpu"] * 0.20
            + components["ram"] * 0.16
            + components["disk"] * 0.20
            + components["thermal"] * 0.12
            + components["security"] * 0.18
            + components["stability"] * 0.14
        )
        risk = self._risk_level(score, anomaly["score"])
        recommendations = self._recommend(normalized_latest, alerts, anomaly["signals"])

        confidence = _clamp(0.35 + min(len(normalized_history), 96) * 0.005 + 0.15, 0.35, 0.95)
        return {
            "model": MODEL_NAME,
            "mode": "local_telemetry_only",
            "agent_id": agent.get("id"),
            "hostname": agent.get("hostname"),
            "health_score": int(score),
            "risk_level": risk,
            "anomaly_score": anomaly["score"],
            "confidence": round(confidence, 2),
            "components": {key: int(round(value)) for key, value in components.items()},
            "latest": normalized_latest,
            "signals": anomaly["signals"][:8],
            "recommendations": recommendations[:5],
            "command_plan": [
                {"command": rec["command"], "priority": rec["priority"], "reason": rec["reason"]}
                for rec in recommendations
                if rec.get("command")
            ],
            "summary": f"{risk.upper()} risk, {int(score)}/100 health, {anomaly['score']}/100 anomaly score.",
            "guardrails": {
                "autonomous_actions": False,
                "allowed_commands": sorted(SAFE_COMMANDS),
                "data_policy": "Uses performance, inventory, alert, and opt-in telemetry only; no camera, microphone, biometric, or secret collection.",
            },
        }

    def _detect_anomaly(self, latest: Dict[str, Any], history: List[Dict[str, Any]]) -> Dict[str, Any]:
        signals: List[Dict[str, Any]] = []

        for feature in self.features:
            current = latest.get(feature.key)
            if current is None:
                continue
            values = [row.get(feature.key) for row in history if isinstance(row.get(feature.key), (int, float))]
            if len(values) < 8:
                continue
            center = median(values)
            spread = _mad(values, center)
            if not spread:
                continue
            z_score = abs(current - center) / (spread * 1.4826)
            if z_score < 2.5:
                continue
            signals.append(
                {
                    "metric": feature.key,
                    "label": feature.label,
                    "value": round(current, 2),
                    "baseline": round(center, 2),
                    "z_score": round(z_score, 2),
                    "severity": self._severity(z_score),
                    "direction": "above_baseline" if current > center else "below_baseline",
                    "message": f"{feature.label} is {'above' if current > center else 'below'} its learned baseline",
                }
            )

        score = round(max([_clamp(signal["z_score"] * 18, 0, 100) for signal in signals] or [0]))
        return {"score": score, "signals": signals}

    def _components(self, latest: Dict[str, Any], alerts: List[Dict[str, Any]], anomaly_score: int) -> Dict[str, float]:
        disk_score = (
            _score_lower_bad(latest.get("disk_free_gb"), 20, 5)
            if latest.get("disk_free_gb") is not None
            else _score_higher_bad(latest.get("disk_used_pct"), 82, 96)
        )
        alert_weights = {"critical": 25, "high": 14, "medium": 7, "low": 3}
        security_penalty = sum(alert_weights.get(str(alert.get("severity", "")).lower(), 0) for alert in alerts)
        return {
            "cpu": _score_higher_bad(latest.get("cpu_pct"), 75, 95),
            "ram": _score_higher_bad(latest.get("ram_pct"), 78, 94),
            "disk": disk_score,
            "thermal": min(
                _score_higher_bad(latest.get("cpu_temp_c"), 76, 92),
                _score_higher_bad(latest.get("gpu_temp_c"), 76, 92),
            ),
            "security": _clamp(100 - security_penalty, 25, 100),
            "stability": _clamp(100 - anomaly_score * 0.45, 35, 100),
        }

    def _recommend(self, latest: Dict[str, Any], alerts: List[Dict[str, Any]], signals: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        recommendations: List[Dict[str, Any]] = []

        def add(title: str, command: Optional[str], priority: str, confidence: float, reason: str, safety: str = "safe") -> None:
            if command is not None and command not in SAFE_COMMANDS:
                return
            if any(item.get("command") == command and item["title"] == title for item in recommendations):
                return
            recommendations.append(
                {
                    "title": title,
                    "command": command,
                    "priority": priority,
                    "confidence": confidence,
                    "reason": reason,
                    "safety_level": safety,
                }
            )

        if latest.get("disk_free_gb") is not None and latest["disk_free_gb"] < 10:
            add("Deep scan storage pressure", "DEEP_SCAN", "critical" if latest["disk_free_gb"] < 5 else "high", 0.92, "Free disk space is below the operational threshold; scan junk, cache, package, and residual candidates before cleanup.")
        if latest.get("cpu_pct") is not None and latest["cpu_pct"] > 82:
            add("Reduce CPU load", "OPTIMIZE", "critical" if latest["cpu_pct"] > 92 else "high", 0.88, "CPU pressure is high enough to affect endpoint responsiveness.")
        if latest.get("ram_pct") is not None and latest["ram_pct"] > 84:
            add("Release memory pressure", "CLEAN", "critical" if latest["ram_pct"] > 92 else "high", 0.86, "RAM usage is above the learned healthy range.")
        if any(str(alert.get("severity", "")).lower() in {"critical", "high"} for alert in alerts):
            add("Validate security posture", "SECURITY_SCAN", "high", 0.82, "Recent unresolved high-severity security alerts are present.", "moderate")
        if any(signal["metric"] in {"cpu_pct", "ram_pct", "net_rx_kbps", "net_tx_kbps"} for signal in signals):
            add("Run local system diagnostics", "SYSTEM_DIAGNOSTICS", "medium", 0.78, "Telemetry deviates from the endpoint baseline; inspect boot, driver, event, and Windows health signals.")
        if not recommendations:
            add("Keep observing baseline", None, "low", 0.72, "No immediate remediation is required from current telemetry.")
        return recommendations

    @staticmethod
    def _risk_level(score: int, anomaly_score: int) -> str:
        if score < 45 or anomaly_score >= 85:
            return "critical"
        if score < 65 or anomaly_score >= 70:
            return "high"
        if score < 82 or anomaly_score >= 45:
            return "medium"
        return "low"

    @staticmethod
    def _severity(z_score: float) -> str:
        if z_score >= 5:
            return "critical"
        if z_score >= 3.5:
            return "high"
        if z_score >= 2.5:
            return "medium"
        return "low"
