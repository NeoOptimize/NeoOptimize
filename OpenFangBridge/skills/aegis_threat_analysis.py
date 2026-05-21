import os
import json
import requests
from typing import Dict, Any

# NeoMonitor REST API Configuration
NEO_MONITOR_URL = os.environ.get("NEO_MONITOR_URL", "https://192.168.122.1")
OPENFANG_API_KEY = os.environ.get("OPENFANG_API_KEY", "your-secure-openfang-key")

def _verify_tls() -> bool:
    return os.environ.get("OPENFANG_VERIFY_TLS", "true").lower() not in ("0", "false", "no", "off")

def run(context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Skill: aegis_threat_analysis
    Analyzes telemetry from NeoMonitor using LLM, and decides if action is needed.
    """
    llm = context.get("llm")

    # 1. Fetch latest telemetry from NeoMonitor (Using Elasticsearch/Logstash inside Security Onion or REST API)
    # For this example, we mock the threat log that Security Onion forwarded.
    threat_log = context.get("event_data", "Suspicious Process: powershell.exe -w hidden -enc JAB...")

    # 2. Analyze using OpenFang's LLM
    prompt = f"""
    You are Guardian_Neo, an elite cybersecurity AI.
    Analyze this threat log from Aegis AV / Security Onion:
    {threat_log}

    Decide the best action:
    - QUARANTINE (if it's clearly malware/ransomware like DeepLoad)
    - MONITOR (if suspicious but not critical)
    - IGNORE (if false positive)

    Respond in strict JSON format: {{"action": "QUARANTINE|MONITOR|IGNORE", "reason": "...", "confidence": 0-100}}
    """

    analysis_str = llm.generate(prompt)

    try:
        analysis = json.loads(analysis_str)
    except:
        return {"error": "LLM did not return JSON", "raw": analysis_str}

    # 3. If action is QUARANTINE, send REST API command to NeoMonitor
    if analysis.get("action") == "QUARANTINE":
        cmd_payload = {
            "agent_id": context.get("agent_id", "target-agent-uuid"),
            "type": "AUTOIMMUNE",  # Trigger L2 Lockdown via NeoOptimize Agent
            "args": {"target": "powershell.exe"},
            "priority": 10
        }

        headers = {"x-openfang-key": OPENFANG_API_KEY, "Content-Type": "application/json"}

        try:
            resp = requests.post(f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command", json=cmd_payload, headers=headers, verify=_verify_tls())
            analysis["neo_response"] = resp.json()
        except Exception as e:
            analysis["neo_error"] = str(e)

    return analysis
