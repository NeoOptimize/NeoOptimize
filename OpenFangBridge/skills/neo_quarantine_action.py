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
    Skill: neo_quarantine_action
    Executes quarantine or block actions on the target NeoOptimize agent.
    """
    action = context.get("action", "QUARANTINE")
    target = context.get("target", "unknown")
    agent_id = context.get("agent_id", "target-agent-uuid")

    cmd_payload = {
        "agent_id": agent_id,
        "type": "AUTOIMMUNE",  # Trigger Autoimmune response
        "args": {"target": target, "action": action},
        "priority": 10
    }

    headers = {"x-openfang-key": OPENFANG_API_KEY, "Content-Type": "application/json"}

    try:
        resp = requests.post(f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command", json=cmd_payload, headers=headers, verify=_verify_tls())
        return {"status": "success", "neo_response": resp.json()}
    except Exception as e:
        return {"status": "failed", "error": str(e)}
