import os
import json
import requests
from typing import Dict, Any

NEO_MONITOR_URL = os.environ.get("NEO_MONITOR_URL", "https://192.168.122.1")
OPENFANG_API_KEY = os.environ.get("OPENFANG_API_KEY", "your-secure-openfang-key")

def _verify_tls() -> bool:
    return os.environ.get("OPENFANG_VERIFY_TLS", "true").lower() not in ("0", "false", "no", "off")

def run(context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Skill: neo_anomaly_forecasting
    Predicts hardware failure, memory leaks, or zero-day threats using historical telemetry.
    """
    llm = context.get("llm")
    history = context.get("historical_telemetry", [])
    agent_id = context.get("agent_id", "target-agent-uuid")

    prompt = f"""
    You are Predictor_Neo, an AI predicting system anomalies and security zero-days.
    Analyze this historical telemetry trend:
    {json.dumps(history)}

    Predict potential future issues (e.g., disk failure, memory leak, ransomware staging).
    Decide the best preemptive action:
    - THREAT_SCAN (if suspicious trends indicate an incoming attack)
    - BACKUP_OPS (if hardware failure or ransomware is predicted)
    - NONE (if healthy)

    Respond in strict JSON format: {{"action": "THREAT_SCAN|BACKUP_OPS|NONE", "prediction": "...", "confidence_score": 0-100}}
    """

    analysis_str = llm.generate(prompt)

    try:
        analysis = json.loads(analysis_str)
    except:
        return {"error": "LLM did not return JSON", "raw": analysis_str}

    action = analysis.get("action")
    if action in ["THREAT_SCAN", "BACKUP_OPS"]:
        cmd_payload = {
            "agent_id": agent_id,
            "type": action,
            "args": {},
            "priority": 8
        }

        headers = {"x-openfang-key": OPENFANG_API_KEY, "Content-Type": "application/json"}

        try:
            resp = requests.post(f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command", json=cmd_payload, headers=headers, verify=_verify_tls())
            analysis["neo_response"] = resp.json()
        except Exception as e:
            analysis["neo_error"] = str(e)

    return analysis
