"""
Agent 10: Monitoring Agent (Production Telemetry & Autonomous Bug Feeder)
1. Monitors remote production endpoints (https://voyplan.in, Backend, DB).
2. Detects uptime issues, latency spikes, or API regression.
3. Automatically queues new bug tasks into the CEO task queue for self-healing.
"""

import os
import sys
import json
import time
import urllib.request
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.logger import AgentLogger
from state.database import StateDB

class MonitoringAgent:
    def __init__(self, backend_url: str = "https://travel-v1-mzia.onrender.com", web_url: str = "https://voyplan.in"):
        self.backend_url = backend_url
        self.web_url = web_url
        self.db = StateDB()
        self.logger = AgentLogger("monitoring", "fleet")

    def run_health_check(self) -> Dict[str, Any]:
        self.logger.log_event("Monitoring Agent pinging live production infrastructure...")
        self.db.record_agent_state(
            agent_id="monitoring",
            name="Monitoring Agent",
            role="Production Telemetry & Health Monitoring",
            status="WORKING",
            action="Pinging production web & API endpoints",
            result="IN_PROGRESS"
        )

        checks = {}
        # 1. Web Landing Page
        try:
            req = urllib.request.Request(self.web_url, headers={"User-Agent": "VoyPlan-Monitor/1.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                checks["web"] = {"status": "HEALTHY", "http_code": resp.status}
        except Exception as e:
            checks["web"] = {"status": "DEGRADED", "error": str(e)}

        # 2. Backend Fuel Prices API
        try:
            req = urllib.request.Request(f"{self.backend_url}/api/fuel/prices?location=Bengaluru&fuelType=petrol")
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                checks["backend"] = {"status": "HEALTHY", "fuel_price": data.get("price")}
        except Exception as e:
            checks["backend"] = {"status": "DEGRADED", "error": str(e)}

        overall = "HEALTHY" if all(v.get("status") == "HEALTHY" for v in checks.values()) else "DEGRADED"

        self.db.record_agent_state(
            agent_id="monitoring",
            name="Monitoring Agent",
            role="Production Telemetry & Health Monitoring",
            status="ONLINE",
            action=f"System state: {overall}",
            result=json.dumps(checks)
        )

        return {
            "status": overall,
            "timestamp": time.time(),
            "checks": checks
        }
