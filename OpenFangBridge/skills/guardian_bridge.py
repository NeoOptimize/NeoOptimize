"""
OpenFang Guardian Hand v5.0 — Production Hardened
BUG#5 FIX: TLS verify=True (no more MITM vulnerability)
ADDED: Proper session management, retry logic, Telegram alerts
"""

import os
import json
import time
import logging
import requests
from datetime import datetime
from urllib3.util.retry import Retry
from requests.adapters import HTTPAdapter

# ─── Auto-Load .env from Server ──────────────────────────────────
ENV_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "server", ".env")
if os.path.exists(ENV_PATH):
    with open(ENV_PATH, "r") as f:
        for line in f:
            if "=" in line and not line.startswith("#"):
                key, val = line.strip().split("=", 1)
                os.environ[key.strip()] = val.strip()

# ─── Configuration ────────────────────────────────────────────────
NEO_MONITOR_URL   = os.environ.get("DASHBOARD_ORIGIN", "https://neooptimize.duckdns.org")
OPENFANG_API_KEY  = os.environ.get("OPENFANG_API_KEY",  "")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
NEO_SERVICE_JWT   = os.environ.get("NEO_SERVICE_JWT",   "")
TELEGRAM_TOKEN    = os.environ.get("TELEGRAM_BOT_TOKEN","")
TELEGRAM_CHAT     = os.environ.get("TELEGRAM_CHAT_ID",  "")
POLL_INTERVAL_SEC = int(os.environ.get("POLL_INTERVAL", "30"))

logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)-8s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
log = logging.getLogger("Guardian")

# ─── HTTP Session with retry + TLS (BUG#5 FIX) ───────────────────
def build_session() -> requests.Session:
    session = requests.Session()
    retry = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504]
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("https://", adapter)
    session.mount("http://",  adapter)
    return session

SESSION = build_session()

OPENFANG_HEADERS = {
    "x-openfang-key": OPENFANG_API_KEY,
    "Content-Type":   "application/json"
}
AUTH_HEADERS = {
    "Authorization": f"Bearer {NEO_SERVICE_JWT}",
    "Content-Type":  "application/json"
}

# ─── Telegram Notification ────────────────────────────────────────
def send_telegram(text: str):
    if not TELEGRAM_TOKEN or not TELEGRAM_CHAT:
        return
    try:
        SESSION.post(
            f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT, "text": text, "parse_mode": "Markdown"},
            timeout=5,
            verify=True  # BUG#5 FIX
        )
    except Exception as e:
        log.warning(f"Telegram alert failed: {e}")

# ─── LLM Threat Analysis ─────────────────────────────────────────
def analyze_threat_with_llm(threat_data: dict, agent_hostname: str) -> dict:
    """Analyze threat with Claude LLM, Ollama (Local Free), or fall back to heuristics."""
    OLLAMA_URL = os.environ.get("OLLAMA_API_URL", "http://localhost:11434")
    OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "llama3")

    prompt = f"""You are Guardian_Neo, an elite cybersecurity AI for NeoMonitor RMM.

Endpoint: {agent_hostname}
Aegis AV Threat Report:
{json.dumps(threat_data, indent=2)}

Assess this threat and respond ONLY in valid JSON format:
{{
  "action": "AUTOIMMUNE|THREAT_SCAN|QUARANTINE|MONITOR|IGNORE",
  "reason": "brief explanation",
  "confidence": 0-100,
  "threat_class": "ransomware|fileless|rootkit|adware|false_positive|unknown"
}}"""

    # 1. Try Anthropic (Claude) if configured
    if ANTHROPIC_API_KEY:
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
            msg = client.messages.create(
                model="claude-3-5-sonnet-20240620",
                max_tokens=256,
                messages=[{"role": "user", "content": prompt}]
            )
            result = json.loads(msg.content[0].text)
            log.info(f"[CLAUDE] Analysis: {result['action']} ({result['confidence']}%) — {result['reason']}")
            return result
        except Exception as e:
            log.warning(f"Claude analysis failed: {e}. Trying local Ollama...")

    # 2. Try Local Free Lifetime LLM (Ollama)
    try:
        ollama_resp = SESSION.post(
            f"{OLLAMA_URL}/api/generate",
            json={"model": OLLAMA_MODEL, "prompt": prompt, "stream": False, "format": "json"},
            timeout=15
        )
        if ollama_resp.status_code == 200:
            result = json.loads(ollama_resp.json().get("response", "{}"))
            log.info(f"[OLLAMA] Local AI Analysis: {result.get('action', 'MONITOR')} ({result.get('confidence', 0)}%) — {result.get('reason', '')}")
            return result
    except Exception as e:
        log.warning(f"Ollama local AI failed or not running: {e}. Using heuristics.")

    # 3. Fallback to Heuristics
    return heuristic_analysis(threat_data)


def heuristic_analysis(data: dict) -> dict:
    """Rule-based fallback when LLM is unavailable."""
    risk_score      = data.get("overall_risk_score", 0)
    ps_anomalies    = data.get("powershell_anomalies", [])
    suspicious_procs= data.get("suspicious_processes", [])
    registry_mods   = data.get("registry_modifications", [])

    indicators = []
    if ps_anomalies:       indicators.extend([p.get("reason","") for p in ps_anomalies])
    if suspicious_procs:   indicators.extend([p.get("reason","") for p in suspicious_procs])
    if registry_mods:      indicators.append(f"{len(registry_mods)} registry modifications")

    if risk_score >= 70 or len(ps_anomalies) > 0:
        return {"action": "AUTOIMMUNE",  "reason": "High-risk heuristic: fileless/encoded PS", "confidence": 85, "threat_class": "fileless"}
    elif risk_score >= 40 or len(suspicious_procs) > 1:
        return {"action": "THREAT_SCAN", "reason": "Multiple suspicious processes", "confidence": 65, "threat_class": "unknown"}
    elif risk_score >= 20:
        return {"action": "MONITOR",     "reason": f"Low-risk anomaly (score={risk_score})", "confidence": 50, "threat_class": "unknown"}
    else:
        return {"action": "IGNORE",      "reason": "Below risk threshold", "confidence": 90, "threat_class": "false_positive"}


# ─── Dispatch Command to NeoMonitor ──────────────────────────────
def dispatch_command(agent_id: str, agent_hostname: str, cmd_type: str, reason: str, confidence: int) -> bool:
    """Issue autonomous command to an agent via NeoMonitor REST API."""
    url     = f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/command"
    payload = {
        "agent_id": agent_id,
        "type":     cmd_type,
        "args":     {"reason": reason, "confidence": confidence, "source": "guardian_hand_v5"},
        "priority": 10
    }
    try:
        resp = SESSION.post(
            url, json=payload, headers=OPENFANG_HEADERS,
            verify=True,   # BUG#5 FIX: TLS verification enabled
            timeout=10
        )
        resp.raise_for_status()
        log.info(f"✅ Dispatched {cmd_type} → {agent_hostname} [{agent_id[:8]}...] ({confidence}%)")

        # Notify via Telegram
        send_telegram(
            f"🤖 *AI Auto-Response*\n"
            f"Host: `{agent_hostname}`\n"
            f"Action: *{cmd_type}*\n"
            f"Reason: {reason}\n"
            f"Confidence: {confidence}%"
        )
        return True
    except Exception as e:
        log.error(f"❌ Dispatch failed for {agent_id[:8]}: {e}")
        return False


# ─── Fetch Completed THREAT_SCAN Results ─────────────────────────
def fetch_threat_results() -> list:
    """Fetch latest completed THREAT_SCAN command results from NeoMonitor."""
    try:
        resp = SESSION.get(
            f"{NEO_MONITOR_URL}/api/v1/dashboard/openfang/results",
            headers=OPENFANG_HEADERS,
            verify=True,
            timeout=10
        )
        resp.raise_for_status()
        commands = resp.json().get("commands", [])
        return commands
    except Exception as e:
        log.error(f"[FETCH] Failed to fetch threat results: {e}")
        return []


# ─── Main Guardian Loop ───────────────────────────────────────────
def main():
    log.info("═══════════════════════════════════════════════")
    log.info("  OpenFang Guardian Hand v5.0 — ACTIVE")
    log.info(f"  Server   : {NEO_MONITOR_URL}")
    log.info(f"  LLM      : {'Claude 3.5 Sonnet' if ANTHROPIC_API_KEY else 'Heuristic fallback'}")
    log.info(f"  Telegram : {'Enabled' if TELEGRAM_TOKEN else 'Disabled'}")
    log.info(f"  Interval : {POLL_INTERVAL_SEC}s")
    log.info("═══════════════════════════════════════════════")

    send_telegram("🛡️ *Guardian Hand v5.0 Online*\nAI threat monitoring active.")

    while True:
        try:
            results = fetch_threat_results()
            if results:
                log.info(f"[SCAN] Analyzing {len(results)} THREAT_SCAN result(s)...")

            for cmd in results:
                agent_id       = cmd.get("agent_id", "")
                agent_hostname = cmd.get("hostname", "unknown")
                raw_result     = cmd.get("result", {})
                threat_data    = raw_result if isinstance(raw_result, dict) else {}

                decision   = analyze_threat_with_llm(threat_data, agent_hostname)
                action     = decision.get("action", "MONITOR")
                reason     = decision.get("reason", "")
                confidence = decision.get("confidence", 50)
                threat_cls = decision.get("threat_class", "unknown")

                log.info(f"[AI] {agent_hostname}: {action} | class={threat_cls} | conf={confidence}% | {reason}")

                if action in ("AUTOIMMUNE", "THREAT_SCAN", "QUARANTINE") and agent_id:
                    dispatch_command(agent_id, agent_hostname, action, reason, confidence)
                    if action == "AUTOIMMUNE":
                        send_telegram(
                            f"🚨 *AEGIS AV AUTO-LOCKDOWN TRIGGERED*\n"
                            f"Host: `{agent_hostname}`\n"
                            f"Threat: {threat_cls}\n"
                            f"Confidence: {confidence}%"
                        )

        except KeyboardInterrupt:
            log.info("Guardian Hand stopped.")
            send_telegram("🔴 *Guardian Hand Stopped* — manual intervention may be required.")
            break
        except Exception as e:
            log.error(f"[LOOP] Unexpected error: {e}")

        time.sleep(POLL_INTERVAL_SEC)


if __name__ == "__main__":
    main()
