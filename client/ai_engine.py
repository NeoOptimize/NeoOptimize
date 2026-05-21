"""
NeoOptimize v1.0 AI Integration Layer
Python-based AI engine for intelligent system optimization

This module provides optional compatibility helpers for:
- Intelligent system analysis
- AI-driven optimization recommendations
- Machine learning profiles
- RMM integration
- Predictive health monitoring

Requires: Python 3.9+, psutil, PyYAML, numpy (optional)
"""

import os
import sys
import json
import logging
import shutil
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
from datetime import datetime
import subprocess
import platform
import urllib.request
import urllib.error
import urllib.parse

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

APP_NAME = "NeoOptimize"
APP_VERSION = "1.0-neocore"
MIN_PYTHON_VERSION = (3, 9)
LOG_DIR = os.path.join(os.path.dirname(__file__), "logs")
CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config", "neooptimize_ai.json")

# Ensure log directory exists
os.makedirs(LOG_DIR, exist_ok=True)

# ═══════════════════════════════════════════════════════════════════════════════
# LOGGER SETUP
# ═══════════════════════════════════════════════════════════════════════════════

logger = logging.getLogger(APP_NAME)
logger.setLevel(logging.DEBUG)

handler = logging.FileHandler(os.path.join(LOG_DIR, f"neooptimize_ai_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"))
handler.setLevel(logging.DEBUG)
formatter = logging.Formatter('[%(asctime)s] %(levelname)s: %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

console_handler = logging.StreamHandler()
console_handler.setLevel(logging.INFO)
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)

# ═══════════════════════════════════════════════════════════════════════════════
# DATA STRUCTURES
# ═══════════════════════════════════════════════════════════════════════════════

@dataclass
class SystemMetrics:
    """Current system performance metrics"""
    cpu_usage: float
    memory_usage: float
    disk_usage: float
    cpu_temp: Optional[float] = None
    disk_temp: Optional[float] = None
    uptime_hours: float = 0
    process_count: int = 0
    service_count: int = 0
    timestamp: str = None

    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now().isoformat()

    def to_dict(self) -> Dict:
        return {
            'cpu_usage': self.cpu_usage,
            'memory_usage': self.memory_usage,
            'disk_usage': self.disk_usage,
            'cpu_temp': self.cpu_temp,
            'disk_temp': self.disk_temp,
            'uptime_hours': self.uptime_hours,
            'process_count': self.process_count,
            'service_count': self.service_count,
            'timestamp': self.timestamp
        }


@dataclass
class OptimizationRecommendation:
    """AI-generated optimization recommendation"""
    module_id: str
    module_name: str
    priority: str  # 'critical', 'high', 'medium', 'low'
    confidence: float  # 0.0 - 1.0
    description: str
    estimated_impact: str
    safety_level: str  # 'safe', 'moderate', 'risky'
    reasoning: str
    ps1_module: str  # PowerShell module to execute

    def to_dict(self) -> Dict:
        return {
            'module_id': self.module_id,
            'module_name': self.module_name,
            'priority': self.priority,
            'confidence': self.confidence,
            'description': self.description,
            'estimated_impact': self.estimated_impact,
            'safety_level': self.safety_level,
            'reasoning': self.reasoning,
            'ps1_module': self.ps1_module
        }


@dataclass
class ModelAgentResult:
    """Free/local model advisor output"""
    provider: str
    response: str
    errors: List[str]

    def to_dict(self) -> Dict:
        return {
            'provider': self.provider,
            'response': self.response,
            'errors': self.errors
        }


# ═══════════════════════════════════════════════════════════════════════════════
# SYSTEM ANALYZER
# ═══════════════════════════════════════════════════════════════════════════════

class SystemAnalyzer:
    """Analyzes Windows system using PowerShell queries"""

    def __init__(self):
        self.ps1_dir = os.path.dirname(__file__)
        logger.info("SystemAnalyzer initialized")

    def get_metrics(self) -> SystemMetrics:
        """Collect current system metrics via PowerShell"""
        try:
            # PowerShell query for system metrics
            ps_script = """
            $cpu = Get-WmiObject Win32_Processor
            $mem = Get-WmiObject Win32_OperatingSystem
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceName='C:'"
            $processes = Get-Process | Measure-Object
            $services = Get-Service | Measure-Object

            @{
                'cpu_usage' = [math]::Round((Get-WmiObject Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" | Select -ExpandProperty PercentProcessorTime), 2);
                'memory_usage' = [math]::Round(($mem.TotalVisibleMemorySize - $mem.FreePhysicalMemory) / $mem.TotalVisibleMemorySize * 100, 2);
                'disk_usage' = [math]::Round($disk.UsedSpace / $disk.Size * 100, 2);
                'uptime_hours' = [math]::Round((New-TimeSpan -Start ([System.Management.ManagementDateTimeConverter]::ToDateTime((Get-WmiObject Win32_OperatingSystem | Select -ExpandProperty InstallDate))).ToUniversalTime() -End (Get-Date).ToUniversalTime()).TotalHours, 1);
                'process_count' = $processes.Count;
                'service_count' = $services.Count;
            } | ConvertTo-Json
            """

            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=10
            )

            if result.returncode == 0:
                data = json.loads(result.stdout)
                metrics = SystemMetrics(**data)
                logger.info(f"System metrics collected: CPU={metrics.cpu_usage}% MEM={metrics.memory_usage}% DISK={metrics.disk_usage}%")
                return metrics
            else:
                logger.error(f"PowerShell error: {result.stderr}")
                return self._get_fallback_metrics()

        except Exception as e:
            logger.error(f"Error collecting metrics: {e}")
            return self._get_fallback_metrics()

    def _get_fallback_metrics(self) -> SystemMetrics:
        """Fallback metrics using psutil if available"""
        try:
            import psutil
            return SystemMetrics(
                cpu_usage=psutil.cpu_percent(interval=1),
                memory_usage=psutil.virtual_memory().percent,
                disk_usage=psutil.disk_usage('/').percent,
                process_count=len(psutil.pids()),
                service_count=0
            )
        except ImportError:
            logger.warning("psutil not available, using default metrics")
            return SystemMetrics(
                cpu_usage=0.0,
                memory_usage=0.0,
                disk_usage=0.0
            )


# ═══════════════════════════════════════════════════════════════════════════════
# AI ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

class AIOptimizer:
    """AI-driven optimization engine."""

    def __init__(self):
        self.analyzer = SystemAnalyzer()
        self.recommendations = []
        self.profile = "balanced"  # balanced, aggressive, conservative, gaming
        logger.info("AIOptimizer engine initialized")

    def analyze_system(self) -> List[OptimizationRecommendation]:
        """Analyze system and generate AI recommendations"""
        logger.info("Starting system analysis...")
        metrics = self.analyzer.get_metrics()

        recommendations = []

        # Rule 1: High CPU usage → Performance optimization
        if metrics.cpu_usage > 80:
            recommendations.append(OptimizationRecommendation(
                module_id="02",
                module_name="Performance Optimizer",
                priority="critical",
                confidence=0.95,
                description="CPU usage critically high - system performance severely impacted",
                estimated_impact="15-30% CPU reduction",
                safety_level="safe",
                reasoning=f"Detected sustained CPU usage at {metrics.cpu_usage}%. Multiple background processes likely consuming resources.",
                ps1_module="02_Performance.ps1"
            ))

        # Rule 2: High memory usage → Memory cleanup
        if metrics.memory_usage > 85:
            recommendations.append(OptimizationRecommendation(
                module_id="01",
                module_name="System Cleaner",
                priority="high",
                confidence=0.90,
                description="Memory usage very high - cleanup recommended",
                estimated_impact="10-20% memory reduction",
                safety_level="safe",
                reasoning=f"Memory pressure at {metrics.memory_usage}%. Temp files and caches can be safely removed.",
                ps1_module="01_Cleaner.ps1"
            ))

        # Rule 3: High disk usage → Cleanup
        if metrics.disk_usage > 90:
            recommendations.append(OptimizationRecommendation(
                module_id="01",
                module_name="System Cleaner",
                priority="critical",
                confidence=0.98,
                description="Disk critically full - system stability at risk",
                estimated_impact="5-15% disk space freed",
                safety_level="safe",
                reasoning=f"Disk usage at {metrics.disk_usage}%. Low disk space impacts Windows Update and overall stability.",
                ps1_module="01_Cleaner.ps1"
            ))

        # Rule 4: Many processes → Services review
        if metrics.process_count > 250:
            recommendations.append(OptimizationRecommendation(
                module_id="06",
                module_name="Services Manager",
                priority="medium",
                confidence=0.85,
                description="Too many background processes - optimization opportunity",
                estimated_impact="5-10% performance improvement",
                safety_level="moderate",
                reasoning=f"Running {metrics.process_count} processes. Many are likely unnecessary services.",
                ps1_module="06_Services.ps1"
            ))

        # Rule 5: High uptime → Updates likely pending
        if metrics.uptime_hours > 720:  # 30 days
            recommendations.append(OptimizationRecommendation(
                module_id="07",
                module_name="Update Manager",
                priority="medium",
                confidence=0.80,
                description="System uptime very high - updates likely pending",
                estimated_impact="Security & stability patches",
                safety_level="safe",
                reasoning=f"System running {metrics.uptime_hours:.0f} hours. Windows/driver updates likely pending.",
                ps1_module="07_Updates.ps1"
            ))

        # Always recommend privacy optimization
        recommendations.append(OptimizationRecommendation(
            module_id="03",
            module_name="Privacy Optimizer",
            priority="low",
            confidence=0.75,
            description="Routine telemetry and privacy configuration",
            estimated_impact="Reduced data collection",
            safety_level="safe",
            reasoning="Proactive privacy hardening - no system impact",
            ps1_module="03_Privacy.ps1"
        ))

        self.recommendations = recommendations
        logger.info(f"Generated {len(recommendations)} recommendations")
        return recommendations

    def get_profile_recommendations(self, profile: str) -> List[OptimizationRecommendation]:
        """Get recommendations filtered by user profile"""
        self.profile = profile
        recommendations = self.analyze_system()

        if profile == "aggressive":
            # Keep all recommendations, higher safety threshold
            filtered = [r for r in recommendations if r.safety_level in ["safe", "moderate"]]
        elif profile == "conservative":
            # Only safe recommendations
            filtered = [r for r in recommendations if r.safety_level == "safe"]
        elif profile == "gaming":
            # Focus on performance + network
            filtered = [r for r in recommendations if r.module_id in ["02", "04", "08"]]
        else:  # balanced
            filtered = recommendations

        return filtered


# ═══════════════════════════════════════════════════════════════════════════════
# LOCAL MODEL AGENT PROVIDERS
# ═══════════════════════════════════════════════════════════════════════════════

class FreeModelAgent:
    """Advisory-only local/free model layer.

    Provider order is configured in config/NeoOptimize.ModelAgent.json.
    Supported providers:
    - Ollama local HTTP API
    - OpenAI-compatible chat completion APIs
    - Hugging Face Inference API
    - Gemini generateContent API
    - NullClaw CLI, when installed and configured
    - deterministic rule-based fallback
    """

    def __init__(self):
        self.config_path = os.path.join(os.path.dirname(__file__), "config", "NeoOptimize.ModelAgent.json")
        self.config = self._load_config()
        logger.info("FreeModelAgent initialized")

    def _load_config(self) -> Dict:
        default = {
            "enabled": True,
            "mode": "advisory_only",
            "provider_order": ["neocore", "ollama", "openai_compatible", "huggingface", "gemini", "nullclaw", "rule_based"],
            "ollama": {
                "enabled": True,
                "endpoint": "http://127.0.0.1:11434/api/generate",
                "tags_endpoint": "http://127.0.0.1:11434/api/tags",
                "preferred_models": ["qwen2.5:3b-instruct", "llama3.2:3b", "phi3:mini", "gemma2:2b"],
                "temperature": 0.2,
                "num_predict": 900,
                "timeout_seconds": 30
            },
            "nullclaw": {
                "enabled": True,
                "command": "nullclaw",
                "arguments": ["agent", "-m"],
                "timeout_seconds": 75,
                "max_prompt_chars": 6000
            },
            "openai_compatible": {
                "enabled": False,
                "endpoint": "https://api.openai.com/v1/chat/completions",
                "model": "gpt-4.1-mini",
                "api_key": "",
                "timeout_seconds": 60,
                "max_tokens": 1200,
                "temperature": 0.2
            },
            "huggingface": {
                "enabled": False,
                "model": "",
                "api_key": "",
                "timeout_seconds": 60,
                "max_new_tokens": 900,
                "temperature": 0.2
            },
            "gemini": {
                "enabled": False,
                "model": "gemini-1.5-flash",
                "api_key": "",
                "timeout_seconds": 60,
                "max_output_tokens": 1200,
                "temperature": 0.2
            },
            "rule_based": {"enabled": True}
        }

        if not os.path.exists(self.config_path):
            return default
        try:
            with open(self.config_path, "r", encoding="utf-8") as fh:
                loaded = json.load(fh)
            return {**default, **loaded}
        except Exception as exc:
            logger.warning(f"Failed to load model agent config: {exc}")
            return default

    def build_prompt(self, metrics: SystemMetrics, recommendations: List[OptimizationRecommendation]) -> str:
        payload = {
            "metrics": metrics.to_dict(),
            "recommendations": [r.to_dict() for r in recommendations],
            "available_modules": [
                "Cleaner", "Performance", "Privacy", "Network", "Security",
                "Services", "Updates", "Power", "AgentAudit"
            ]
        }
        return (
            "You are NeoCore, the NeoOptimize local AI advisor. Analyze this authorized Windows endpoint.\n"
            "Rules: advisory only; do not execute tools; do not request secrets, tokens, "
            "camera, microphone, or biometric data. Prefer safe remediation and restore "
            "point first. Return concise Markdown with health score, top risks, "
            "recommended module order, and cautions.\n\n"
            f"Payload JSON:\n{json.dumps(payload, ensure_ascii=False, indent=2)}"
        )

    def advise(self, metrics: SystemMetrics, recommendations: List[OptimizationRecommendation]) -> ModelAgentResult:
        if not self.config.get("enabled", True):
            return ModelAgentResult("disabled", "Model agent disabled in config.", [])

        prompt = self.build_prompt(metrics, recommendations)
        errors = []

        for provider in self.config.get("provider_order", ["ollama", "nullclaw", "rule_based"]):
            try:
                if provider == "neocore":
                    return ModelAgentResult("neocore", self._rule_based(metrics, recommendations), errors)
                if provider == "ollama":
                    return ModelAgentResult("ollama", self._ollama(prompt), errors)
                if provider == "openai_compatible":
                    return ModelAgentResult("openai_compatible", self._openai_compatible(prompt), errors)
                if provider == "huggingface":
                    return ModelAgentResult("huggingface", self._huggingface(prompt), errors)
                if provider == "gemini":
                    return ModelAgentResult("gemini", self._gemini(prompt), errors)
                if provider == "nullclaw":
                    return ModelAgentResult("nullclaw", self._nullclaw(prompt), errors)
                if provider == "rule_based":
                    return ModelAgentResult("rule_based", self._rule_based(metrics, recommendations), errors)
            except Exception as exc:
                errors.append(f"{provider}: {exc}")
                logger.info(f"Provider {provider} unavailable: {exc}")

        return ModelAgentResult("rule_based", self._rule_based(metrics, recommendations), errors)

    def _ollama_model(self) -> Optional[str]:
        cfg = self.config.get("ollama", {})
        if not cfg.get("enabled", True):
            raise RuntimeError("Ollama provider disabled")

        req = urllib.request.Request(cfg.get("tags_endpoint", "http://127.0.0.1:11434/api/tags"))
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        installed = [m.get("name") for m in data.get("models", []) if m.get("name")]
        for preferred in cfg.get("preferred_models", []):
            if preferred in installed:
                return preferred
        return installed[0] if installed else None

    def _ollama(self, prompt: str) -> str:
        cfg = self.config.get("ollama", {})
        model = self._ollama_model()
        if not model:
            raise RuntimeError("Ollama is not running or no local model is installed")

        body = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": float(cfg.get("temperature", 0.2)),
                "num_predict": int(cfg.get("num_predict", 900))
            }
        }
        encoded = json.dumps(body).encode("utf-8")
        req = urllib.request.Request(
            cfg.get("endpoint", "http://127.0.0.1:11434/api/generate"),
            data=encoded,
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=int(cfg.get("timeout_seconds", 30))) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        answer = data.get("response")
        if not answer:
            raise RuntimeError("Ollama returned empty output")
        return f"Provider: Ollama ({model})\n\n{answer}"

    def _post_json(self, url: str, body: Dict, headers: Dict, timeout: int) -> Dict:
        encoded = json.dumps(body).encode("utf-8")
        request_headers = {"Content-Type": "application/json", **headers}
        req = urllib.request.Request(url, data=encoded, headers=request_headers, method="POST")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _openai_compatible(self, prompt: str) -> str:
        cfg = self.config.get("openai_compatible", {})
        if not cfg.get("enabled", False):
            raise RuntimeError("OpenAI-compatible provider disabled")
        endpoint = cfg.get("endpoint", "https://api.openai.com/v1/chat/completions")
        model = cfg.get("model", "gpt-4.1-mini")
        if not endpoint or not model:
            raise RuntimeError("OpenAI-compatible endpoint or model is empty")
        api_key = cfg.get("api_key") or os.environ.get("NEOOPTIMIZE_OPENAI_API_KEY", "")
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        body = {
            "model": model,
            "messages": [
                {
                    "role": "system",
                    "content": "You are NeoOptimize AI Doctor. Advisory only. Do not request or expose secrets."
                },
                {"role": "user", "content": prompt}
            ],
            "temperature": float(cfg.get("temperature", 0.2)),
            "max_tokens": int(cfg.get("max_tokens", 1200))
        }
        data = self._post_json(endpoint, body, headers, int(cfg.get("timeout_seconds", 60)))
        text = ""
        choices = data.get("choices") or []
        if choices:
            text = (choices[0].get("message") or {}).get("content") or choices[0].get("text") or ""
        if not text:
            raise RuntimeError("OpenAI-compatible provider returned empty output")
        return f"Provider: OpenAI-compatible ({model})\n\n{text}"

    def _huggingface(self, prompt: str) -> str:
        cfg = self.config.get("huggingface", {})
        if not cfg.get("enabled", False):
            raise RuntimeError("Hugging Face provider disabled")
        model = cfg.get("model", "")
        if not model:
            raise RuntimeError("Hugging Face model or endpoint is empty")
        endpoint = model if model.startswith(("http://", "https://")) else f"https://api-inference.huggingface.co/models/{model}"
        api_key = cfg.get("api_key") or os.environ.get("NEOOPTIMIZE_HF_TOKEN", "")
        headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
        body = {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens": int(cfg.get("max_new_tokens", 900)),
                "temperature": float(cfg.get("temperature", 0.2)),
                "return_full_text": False
            },
            "options": {"wait_for_model": True}
        }
        data = self._post_json(endpoint, body, headers, int(cfg.get("timeout_seconds", 60)))
        text = ""
        if isinstance(data, list) and data:
            text = data[0].get("generated_text") or data[0].get("summary_text") or ""
        elif isinstance(data, dict):
            text = data.get("generated_text") or ""
        if not text:
            raise RuntimeError("Hugging Face provider returned empty output")
        return f"Provider: Hugging Face ({model})\n\n{text}"

    def _gemini(self, prompt: str) -> str:
        cfg = self.config.get("gemini", {})
        if not cfg.get("enabled", False):
            raise RuntimeError("Gemini provider disabled")
        api_key = cfg.get("api_key") or os.environ.get("NEOOPTIMIZE_GEMINI_API_KEY", "")
        if not api_key:
            raise RuntimeError("Gemini API key is empty")
        model = (cfg.get("model") or "gemini-1.5-flash").replace("models/", "", 1)
        endpoint = (
            "https://generativelanguage.googleapis.com/v1beta/models/"
            f"{urllib.parse.quote(model)}:generateContent?key={urllib.parse.quote(api_key)}"
        )
        body = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {
                            "text": (
                                "You are NeoOptimize AI Doctor. Advisory only. "
                                "Do not request secrets. Return Markdown with health score, risks, module order, and cautions.\n\n"
                                f"{prompt}"
                            )
                        }
                    ]
                }
            ],
            "generationConfig": {
                "temperature": float(cfg.get("temperature", 0.2)),
                "maxOutputTokens": int(cfg.get("max_output_tokens", 1200))
            }
        }
        data = self._post_json(endpoint, body, {}, int(cfg.get("timeout_seconds", 60)))
        text = ""
        candidates = data.get("candidates") or []
        if candidates:
            parts = ((candidates[0].get("content") or {}).get("parts") or [])
            if parts:
                text = parts[0].get("text") or ""
        if not text:
            raise RuntimeError("Gemini provider returned empty output")
        return f"Provider: Gemini ({model})\n\n{text}"

    def _nullclaw(self, prompt: str) -> str:
        cfg = self.config.get("nullclaw", {})
        if not cfg.get("enabled", True):
            raise RuntimeError("NullClaw provider disabled")

        command = cfg.get("command", "nullclaw")
        binary = shutil.which(command)
        if not binary:
            raise RuntimeError("NullClaw CLI not found in PATH")

        max_chars = int(cfg.get("max_prompt_chars", 6000))
        prompt = prompt[:max_chars]
        args = list(cfg.get("arguments", ["agent", "-m"])) + [prompt]
        result = subprocess.run(
            [binary] + args,
            capture_output=True,
            text=True,
            timeout=int(cfg.get("timeout_seconds", 75))
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or "NullClaw returned non-zero exit")
        output = result.stdout.strip()
        if not output:
            raise RuntimeError("NullClaw returned empty output")
        return output

    def _rule_based(self, metrics: SystemMetrics, recommendations: List[OptimizationRecommendation]) -> str:
        score = 100
        risks = []

        if metrics.disk_usage > 90:
            score -= 25
            risks.append(f"Critical disk pressure: {metrics.disk_usage}% used.")
        elif metrics.disk_usage > 82:
            score -= 12
            risks.append(f"Disk usage is elevated: {metrics.disk_usage}% used.")

        if metrics.memory_usage > 90:
            score -= 18
            risks.append(f"High memory pressure: {metrics.memory_usage}% used.")
        elif metrics.memory_usage > 80:
            score -= 8
            risks.append(f"Memory usage is elevated: {metrics.memory_usage}% used.")

        if metrics.cpu_usage > 85:
            score -= 15
            risks.append(f"High CPU usage: {metrics.cpu_usage}%.")

        if metrics.process_count > 250:
            score -= 8
            risks.append(f"High process count: {metrics.process_count}.")

        if metrics.uptime_hours > 336:
            score -= 6
            risks.append(f"Long uptime: {metrics.uptime_hours:.0f} hours.")

        if score < 0:
            score = 0
        if not risks:
            risks.append("No critical issue detected from current metrics.")

        module_order = []
        for rec in recommendations:
            if rec.module_name not in module_order:
                module_order.append(rec.module_name)
        if "NeoOptimize Agent Audit" not in module_order:
            module_order.append("NeoOptimize Agent Audit")

        risk_md = "\n".join(f"- {risk}" for risk in risks)
        order_md = "\n".join(f"- {module}" for module in module_order)
        return (
            "Provider: NeoOptimize rule-based advisor\n\n"
            f"# NeoOptimize AI Advisor\n\nHealth score: {score}/100\n\n"
            f"## Top risks\n{risk_md}\n\n"
            f"## Recommended module order\n{order_md}\n\n"
            "## Cautions\n"
            "- Create a restore point before remediation.\n"
            "- Review Security and Services changes on production endpoints.\n"
            "- This advisor does not collect secrets, camera, microphone, or biometric data.\n"
        )


# ═══════════════════════════════════════════════════════════════════════════════
# RMM CONNECTOR (Enterprise Integration)
# ═══════════════════════════════════════════════════════════════════════════════

class RMMConnector:
    """Integrates with NeoOptimize RMM for enterprise management"""

    def __init__(self, rmm_url: str = None):
        self.rmm_url = rmm_url or os.getenv("NEOOPTIMIZE_RMM_URL")
        self.connected = False
        logger.info(f"RMMConnector initialized - RMM URL: {self.rmm_url}")

    def connect(self) -> bool:
        """Connect to RMM server"""
        if not self.rmm_url:
            logger.warning("RMM URL not configured")
            return False

        try:
            # Placeholder for RMM connection logic
            logger.info(f"Connecting to RMM: {self.rmm_url}")
            self.connected = True
            return True
        except Exception as e:
            logger.error(f"RMM connection failed: {e}")
            return False

    def send_metrics(self, metrics: SystemMetrics) -> bool:
        """Send system metrics to RMM server"""
        if not self.connected:
            logger.warning("RMM not connected")
            return False

        try:
            # Placeholder for sending metrics
            logger.info(f"Sending metrics to RMM: {metrics.to_dict()}")
            return True
        except Exception as e:
            logger.error(f"Failed to send metrics: {e}")
            return False

    def send_recommendations(self, recommendations: List[OptimizationRecommendation]) -> bool:
        """Send recommendations to RMM dashboard"""
        if not self.connected:
            return False

        try:
            data = [r.to_dict() for r in recommendations]
            logger.info(f"Sending {len(data)} recommendations to RMM")
            return True
        except Exception as e:
            logger.error(f"Failed to send recommendations: {e}")
            return False


# ═══════════════════════════════════════════════════════════════════════════════
# POWERSHELL EXECUTOR (Bridge to PS modules)
# ═══════════════════════════════════════════════════════════════════════════════

class PowerShellExecutor:
    """Execute PowerShell modules from Python"""

    def __init__(self, ps1_root: str = None):
        self.ps1_root = ps1_root or os.path.join(os.path.dirname(__file__), ".")
        logger.info(f"PowerShellExecutor initialized - Root: {self.ps1_root}")

    def execute_module(self, module_name: str, **kwargs) -> Tuple[bool, str]:
        """Execute a PowerShell module"""
        module_path = os.path.join(self.ps1_root, "modules", module_name)

        if not os.path.exists(module_path):
            logger.error(f"Module not found: {module_path}")
            return False, "Module not found"

        try:
            # Build PowerShell parameters
            args = " ".join([f"-{k} ${v}" for k, v in kwargs.items()])
            ps_command = f". '{module_path}'; {args}"

            result = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps_command],
                capture_output=True,
                text=True,
                timeout=600  # 10 minute timeout per module
            )

            if result.returncode == 0:
                logger.info(f"Module executed successfully: {module_name}")
                return True, result.stdout
            else:
                logger.error(f"Module failed: {module_name}\n{result.stderr}")
                return False, result.stderr

        except subprocess.TimeoutExpired:
            logger.error(f"Module timeout: {module_name}")
            return False, "Timeout"
        except Exception as e:
            logger.error(f"Module execution error: {e}")
            return False, str(e)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN ORCHESTRATOR
# ═══════════════════════════════════════════════════════════════════════════════

class NeoOptimizeAI:
    """Main AI orchestrator - connects everything together"""

    def __init__(self, rmm_url: str = None):
        logger.info(f"=== NeoOptimize AI v{APP_VERSION} ===")
        logger.info(f"Python {sys.version_info.major}.{sys.version_info.minor}")
        logger.info(f"Platform: {platform.system()} {platform.release()}")

        self.ai_engine = AIOptimizer()
        self.model_agent = FreeModelAgent()
        self.ps_executor = PowerShellExecutor()
        self.rmm = RMMConnector(rmm_url)
        self.metrics_history = []

    def analyze(self) -> Dict:
        """Run full analysis"""
        logger.info("Starting full system analysis...")

        # Collect metrics
        metrics = self.ai_engine.analyzer.get_metrics()
        self.metrics_history.append(metrics)

        # Generate recommendations
        recommendations = self.ai_engine.analyze_system()
        model_agent = self.model_agent.advise(metrics, recommendations)

        # Send to RMM if connected
        if self.rmm.connect():
            self.rmm.send_metrics(metrics)
            self.rmm.send_recommendations(recommendations)

        return {
            'timestamp': datetime.now().isoformat(),
            'metrics': metrics.to_dict(),
            'recommendations': [r.to_dict() for r in recommendations],
            'model_agent': model_agent.to_dict(),
            'rmm_connected': self.rmm.connected
        }

    def execute_recommendations(self, recommendation: OptimizationRecommendation) -> bool:
        """Execute a specific optimization recommendation"""
        logger.info(f"Executing recommendation: {recommendation.module_name}")
        success, output = self.ps_executor.execute_module(recommendation.ps1_module)
        logger.info(f"Module result: {success} - {output[:200]}")
        return success


# ═══════════════════════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    """CLI entry point"""
    print(f"\n{APP_NAME} AI Engine v{APP_VERSION}")
    print("=" * 60)

    # Initialize
    ai = NeoOptimizeAI()

    # Run analysis
    print("\nAnalyzing system...")
    result = ai.analyze()

    print(f"\nSystem Metrics (timestamp: {result['timestamp']}):")
    print(f"  CPU Usage: {result['metrics']['cpu_usage']}%")
    print(f"  Memory Usage: {result['metrics']['memory_usage']}%")
    print(f"  Disk Usage: {result['metrics']['disk_usage']}%")
    print(f"  Uptime: {result['metrics']['uptime_hours']} hours")

    print(f"\nRecommendations ({len(result['recommendations'])} found):")
    for rec in result['recommendations']:
        print(f"  [{rec['priority'].upper()}] {rec['module_name']}: {rec['description']}")

    print(f"\nFree Model Agent: {result['model_agent']['provider']}")
    first_lines = result['model_agent']['response'].splitlines()[:12]
    for line in first_lines:
        print(f"  {line}")

    print(f"\nRMM Connection: {'Connected' if result['rmm_connected'] else 'Not connected'}")
    print("\nAnalysis complete. Results logged to logs/ directory.")


if __name__ == "__main__":
    # Check Python version
    if sys.version_info < MIN_PYTHON_VERSION:
        print(f"ERROR: Python {MIN_PYTHON_VERSION[0]}.{MIN_PYTHON_VERSION[1]}+ required")
        sys.exit(1)

    main()
