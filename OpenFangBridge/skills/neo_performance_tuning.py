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
    Skill: neo_performance_tuning
    Analyzes system performance telemetry and executes optimizations.
    """
    llm = context.get("llm")
    telemetry = context.get("telemetry", {})
    agent_id = context.get("agent_id", "target-agent-uuid")

    prompt = f"""
    You are Optimizer_Neo, an AI responsible for system performance tuning.
    Analyze this telemetry data:
    {json.dumps(telemetry)}

    Decide the best optimization action:
    - OPTIMIZE (run performance tuning)
    - CLEAN (clear temporary files and cache)
    - NONE (system is healthy)

    Respond in strict JSON format: {{"action": "OPTIMIZE|CLEAN|NONE", "reason": "..."}}
    """

    analysis_str = llm.generate(prompt)

    try:
        analysis = json.loads(analysis_str)
    except:
        return {"error": "LLM did not return JSON", "raw": analysis_str}

    action = analysis.get("action")
    if action in ["OPTIMIZE", "CLEAN"]:
        cmd_payload = {
            "agent_id": agent_id,
            "type": action,
            "args": {},
            "priority": 5
        }

        headers = {"x-openfang-key": OPENFANG_API_KEY, "Content-Type": "application/json"}

        try:
            resp = requests.post(f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command", json=cmd_payload, headers=headers, verify=_verify_tls())
            analysis["neo_response"] = resp.json()
        except Exception as e:
            analysis["neo_error"] = str(e)

    return analysis
