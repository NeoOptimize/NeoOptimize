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
    Skill: neo_audit_analysis
    Analyzes audit logs and triggers integrity scans if compliance drift is detected.
    """
    llm = context.get("llm")
    audit_logs = context.get("audit_logs", {})
    agent_id = context.get("agent_id", "target-agent-uuid")

    prompt = f"""
    You are Auditor_Neo, an AI for compliance and security auditing.
    Analyze the following audit logs:
    {json.dumps(audit_logs)}

    Check for configuration drift or security policy violations.
    Decide the action:
    - INTEGRITY_SCAN (if drift or unauthorized changes are detected)
    - SECURITY_SCAN (if malicious changes are suspected)
    - COMPLIANT (if everything aligns with baseline)

    Respond in strict JSON format: {{"action": "INTEGRITY_SCAN|SECURITY_SCAN|COMPLIANT", "violations": ["..."]}}
    """

    analysis_str = llm.generate(prompt)

    try:
        analysis = json.loads(analysis_str)
    except:
        return {"error": "LLM did not return JSON", "raw": analysis_str}

    action = analysis.get("action")
    if action in ["INTEGRITY_SCAN", "SECURITY_SCAN"]:
        cmd_payload = {
            "agent_id": agent_id,
            "type": action,
            "args": {},
            "priority": 7
        }

        headers = {"x-openfang-key": OPENFANG_API_KEY, "Content-Type": "application/json"}

        try:
            resp = requests.post(f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command", json=cmd_payload, headers=headers, verify=_verify_tls())
            analysis["neo_response"] = resp.json()
        except Exception as e:
            analysis["neo_error"] = str(e)

    return analysis
