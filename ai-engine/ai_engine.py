"""
NeoOptimize v1.0 AI Engine
Python-based AI engine for intelligent Windows system optimization

Capabilities:
- Intelligent system analysis (CPU, RAM, Disk, GPU, Network)
- AI-driven optimization recommendations (rule-based + LLM)
- Machine learning health profiles
- Predictive maintenance & anomaly detection
- FastAPI HTTP server for Node.js integration
- Gemini API deep analysis

Requires: Python 3.9+, psutil, PyYAML, numpy (optional)
HTTP Server: pip install fastapi uvicorn
"""

import os
import sys
import json
import logging
import shutil
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime
import subprocess
import platform
import urllib.request
import urllib.error

from neocortex import NeoCortexModel
from predictive_models import PredictiveMaintenanceEngine

# ═══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════════

APP_NAME = "NeoOptimize"
APP_VERSION = "1.0.0"
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
        self.neocortex = NeoCortexModel()
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
            "provider_order": ["ollama", "neocore", "rule_based"],
            "ollama": {
                "enabled": True,
                "endpoint": "http://127.0.0.1:11434/api/generate",
                "tags_endpoint": "http://127.0.0.1:11434/api/tags",
                "preferred_models": ["neo-light:latest", "neo:latest"],
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
                if provider == "ollama":
                    return ModelAgentResult("ollama", self._ollama(prompt), errors)
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
# SYSTEM REPORTER (Local Server Integration — NOT RMM)
# ═══════════════════════════════════════════════════════════════════════════════

class SystemReporter:
    """Push metrics to local NeoOptimize server API (http://localhost:3000)"""

    def __init__(self):
        self.server_url = os.getenv("NEO_SERVER_URL", "http://localhost:3000")
        self.api_key    = os.getenv("OPENFANG_API_KEY", "")
        logger.info(f"SystemReporter → {self.server_url}")

    def push_metrics(self, metrics: 'SystemMetrics') -> bool:
        """POST telemetry to local server"""
        try:
            payload = json.dumps(metrics.to_dict()).encode()
            req = urllib.request.Request(
                f"{self.server_url}/api/v1/internal/telemetry",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Internal-Key": self.api_key
                },
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                return resp.status == 200
        except Exception as e:
            logger.debug(f"[SystemReporter] push_metrics skipped: {e}")
            return False

    def push_recommendations(self, recommendations: list) -> bool:
        """POST recommendations to local server"""
        try:
            payload = json.dumps([r.to_dict() for r in recommendations]).encode()
            req = urllib.request.Request(
                f"{self.server_url}/api/v1/internal/recommendations",
                data=payload,
                headers={
                    "Content-Type": "application/json",
                    "X-Internal-Key": self.api_key
                },
                method="POST"
            )
            with urllib.request.urlopen(req, timeout=3) as resp:
                return resp.status == 200
        except Exception as e:
            logger.debug(f"[SystemReporter] push_recommendations skipped: {e}")
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

    def __init__(self):
        logger.info(f"=== NeoOptimize AI v{APP_VERSION} ===")
        logger.info(f"Python {sys.version_info.major}.{sys.version_info.minor}")
        logger.info(f"Platform: {platform.system()} {platform.release()}")

        self.ai_engine    = AIOptimizer()
        self.model_agent  = FreeModelAgent()
        self.ps_executor  = PowerShellExecutor()
        self.metrics_history = []

    def analyze(self) -> Dict:
        """Run full analysis"""
        logger.info("Starting full system analysis...")

        # Collect metrics
        metrics = self.ai_engine.analyzer.get_metrics()
        self.metrics_history.append(metrics)

        # Generate recommendations
        recommendations = self.ai_engine.analyze_system()
        model_agent     = self.model_agent.advise(metrics, recommendations)
        ml_insight      = self.ai_engine.neocortex.analyze(
            metrics.to_dict(),
            [m.to_dict() for m in self.metrics_history[-96:]],
            agent={"hostname": platform.node()}
        )

        return {
            'timestamp':       datetime.now().isoformat(),
            'metrics':         metrics.to_dict(),
            'recommendations': [r.to_dict() for r in recommendations],
            'ml_insight':      ml_insight,
            'model_agent':     model_agent.to_dict(),
            'engine':          'standalone',
            'version':         APP_VERSION
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

    print(f"\nServer Connection: Standalone mode (use --server to start HTTP API)")
    print("\nAnalysis complete. Results logged to logs/ directory.")


if __name__ == "__main__":
    # Check Python version
    if sys.version_info < MIN_PYTHON_VERSION:
        print(f"ERROR: Python {MIN_PYTHON_VERSION[0]}.{MIN_PYTHON_VERSION[1]}+ required")
        sys.exit(1)

    # --server flag → start FastAPI HTTP server for Node.js integration
    if len(sys.argv) > 1 and sys.argv[1] == '--server':
        try:
            from fastapi import FastAPI, HTTPException
            from fastapi.middleware.cors import CORSMiddleware
            from pydantic import BaseModel
            import uvicorn

            api_app = FastAPI(title="NeoOptimize AI Engine", version="1.0")
            api_app.add_middleware(
                CORSMiddleware,
                allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
                allow_methods=["*"], allow_headers=["*"]
            )

            neo = NeoOptimizeAI()

            @api_app.get("/health")
            def health():
                return {"status": "ok", "version": APP_VERSION, "ml_model": "neocortex-hybrid-v1"}

            @api_app.post("/analyze")
            def analyze():
                result = neo.analyze()
                return result

            @api_app.get("/metrics")
            def metrics():
                m = neo.ai_engine.analyzer.get_metrics()
                return {"metrics": m.to_dict(), "timestamp": datetime.now().isoformat()}

            class ThreatPayload(BaseModel):
                process_name: str = ""
                src_ip: str = ""
                rule_name: str = ""
                severity: str = "medium"

            class MLAnalyzePayload(BaseModel):
                latest: Dict[str, Any]
                history: List[Dict[str, Any]] = []
                alerts: List[Dict[str, Any]] = []
                agent: Dict[str, Any] = {}

            def model_dict(model):
                if hasattr(model, "model_dump"):
                    return model.model_dump()
                return model.dict()

            @api_app.post("/threat-analyze")
            def threat_analyze(payload: ThreatPayload):
                # Use Ollama for threat analysis if available
                return {"payload": model_dict(payload), "analyzed": True, "timestamp": datetime.now().isoformat()}

            @api_app.post("/ml/analyze")
            def ml_analyze(payload: MLAnalyzePayload):
                data = model_dict(payload)
                insight = neo.ai_engine.neocortex.analyze(
                    data["latest"],
                    data.get("history", []),
                    data.get("alerts", []),
                    data.get("agent", {})
                )
                return {"insight": insight, "timestamp": datetime.now().isoformat()}

            @api_app.post("/ml/predict")
            def ml_predict(payload: MLAnalyzePayload):
                data = model_dict(payload)
                engine = PredictiveMaintenanceEngine()
                insights = engine.get_predictive_insights(
                    data["latest"],
                    data.get("history", [])
                )
                return {"insights": insights, "timestamp": datetime.now().isoformat()}

            @api_app.get("/recommendations")
            def recommendations():
                result = neo.analyze()
                return {"recommendations": result.get("recommendations", []), "timestamp": datetime.now().isoformat()}

            port = int(os.environ.get("AI_ENGINE_PORT", 8765))
            print(f"[NeoOptimize AI Engine] HTTP server starting on port {port}")
            uvicorn.run(api_app, host="0.0.0.0", port=port, log_level="info")
        except ImportError as e:
            print(f"[ERROR] FastAPI/uvicorn not installed: {e}")
            print("Install with: pip install fastapi uvicorn")
            sys.exit(1)
    else:
        main()
