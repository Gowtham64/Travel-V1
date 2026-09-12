"""Evidence-first autonomous product testing agent for VoyPlan."""

import datetime as dt
import json
import os
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.llm_client import LLMClient
from agents.common.logger import AgentLogger
from agents.common.workspace import resolve_workspace


class TestingAgent:
    """Runs available independent checks; unavailable evidence never becomes a pass."""

    def __init__(self, workspace_path: str = None, model_provider: str = None, model_name: str = None):
        self.workspace_path = Path(resolve_workspace(workspace_path))
        self.engineering_dir = self.workspace_path / "voyplan-ai-engineering"
        self.llm = LLMClient(provider=model_provider, model=model_name)

    @staticmethod
    def _run_cmd(command: List[str], cwd: Path, timeout: int = 300) -> subprocess.CompletedProcess:
        try:
            return subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        except FileNotFoundError as exc:
            return subprocess.CompletedProcess(command, 127, "", str(exc))
        except subprocess.TimeoutExpired as exc:
            return subprocess.CompletedProcess(command, 124, exc.stdout or "", f"Timed out after {timeout}s: {exc}")

    @staticmethod
    def _evidence(command: List[str], result: subprocess.CompletedProcess, started_at: str) -> Dict[str, Any]:
        return {"timestamp": started_at, "command": " ".join(command), "exit_code": result.returncode,
                "stdout": (result.stdout or "")[-4000:], "stderr": (result.stderr or "")[-4000:]}

    def _load_development_result(self, path: Optional[str]) -> Dict[str, Any]:
        candidate = Path(path) if path else self.engineering_dir / "development-result.json"
        try:
            return json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}

    def _run_check(self, name: str, command: List[str], cwd: Path, logger: AgentLogger,
                   report: Dict[str, Any], timeout: int = 300) -> str:
        started_at = dt.datetime.now(dt.timezone.utc).isoformat()
        result = self._run_cmd(command, cwd, timeout)
        logger.record_command(" ".join(command), result.returncode, result.stdout or result.stderr)
        status = "PASS" if result.returncode == 0 else "FAIL"
        report["actions_performed"].append({"action": name, "status": status})
        report["evidence"].append(self._evidence(command, result, started_at))
        if result.returncode == 0:
            report["passed"].append(name)
            return status
        report["failed"].append(name)
        report["bugs"].append({"priority": "P1" if "Playwright" in name else "P2", "title": f"{name} failed",
                               "reproduction": " ".join(command),
                               "actual_result": (result.stderr or result.stdout or "No output")[-1000:]})
        return status

    def test(self, dev_result_path: str = None) -> Dict[str, Any]:
        dev_result = self._load_development_result(dev_result_path)
        issue_id = str(dev_result.get("issue", "adhoc"))
        logger = AgentLogger("testing", issue_id)
        session_id = f"test-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"
        backend_dir = self.workspace_path / "backend"
        e2e_dir = self.engineering_dir / "tests" / "e2e"
        report: Dict[str, Any] = {
            "session_id": session_id, "platform": "web/backend",
            "environment": os.getenv("STAGING_URL") or os.getenv("PRODUCTION_URL") or "local/unconfigured",
            "persona": "independent real-traveler exploratory tester", "pages_discovered": [],
            "features_discovered": ["backend regression suite", "web itinerary E2E"],
            "actions_performed": [], "journeys_tested": [], "passed": [], "failed": [], "blocked": [],
            "unknown": [], "bugs": [], "root_causes": [], "api_validation": [], "database_validation": [],
            "screenshots": [], "traces": [], "regression_tests_created": [], "next_actions": [], "evidence": [],
            "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        }

        if (backend_dir / "package.json").exists():
            self._run_check("Backend Jest regression suite", ["npm", "test", "--", "--runInBand", "--forceExit"], backend_dir, logger, report, 300)
            report["journeys_tested"].append("API and itinerary-rule regression coverage")
        else:
            report["blocked"].append("Backend Jest regression suite: backend/package.json is unavailable")

        e2e_spec = e2e_dir / "voyplan-itinerary.spec.js"
        playwright_bin = e2e_dir / "node_modules" / ".bin" / "playwright"
        target = os.getenv("STAGING_URL") or os.getenv("PRODUCTION_URL")
        if not e2e_spec.exists():
            report["blocked"].append("Web E2E: Playwright specification is missing")
        elif not target:
            report["blocked"].append("Web E2E: no STAGING_URL or PRODUCTION_URL was configured; no real UI was tested")
        elif not playwright_bin.exists():
            report["blocked"].append("Web E2E: Playwright dependencies are not installed in tests/e2e")
        else:
            self._run_check("Playwright real-web journey", [str(playwright_bin), "test", "--config", "playwright.config.js"], e2e_dir, logger, report, 180)
            report["journeys_tested"].append("Open app → plan Tirumala itinerary → validate itinerary response")

        report["unknown"].extend([
            "Android journey: no APK/device evidence supplied", "iOS journey: no IPA/simulator evidence supplied",
            "Database persistence: no isolated test database credentials or record identifier supplied",
        ])
        report["next_actions"] = [
            "Provide a staging URL and install Playwright browsers to execute the web journey.",
            "Attach Android and iOS device sessions for equivalent real-human journeys.",
            "Provide a disposable test account and staging database access for save/reload validation.",
        ]
        report["ended_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
        if report["failed"]:
            status, recommendation = "FAIL", "RETURN_TO_DEVELOPER"
        elif report["blocked"] or report["unknown"]:
            status, recommendation = "UNKNOWN", "COLLECT_MISSING_EVIDENCE"
        else:
            status, recommendation = "PASS", "PROCEED_TO_QA"
        report.update({
            "status": status, "branch": dev_result.get("branch", "unknown"),
            "commit": (dev_result.get("commits") or ["HEAD"])[0],
            "tests_run": [a["action"] for a in report["actions_performed"]],
            "passed_count": len(report["passed"]), "failed_count": len(report["failed"]),
            "failed_tests": report["failed"], "errors": [bug["actual_result"] for bug in report["bugs"]],
            "regressions": report["bugs"], "recommendation": recommendation,
        })
        (self.engineering_dir / "test-result.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        memory_dir = self.engineering_dir / "test-memory" / "sessions"
        memory_dir.mkdir(parents=True, exist_ok=True)
        (memory_dir / f"{session_id}.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        logger.complete(status, model_used=self.llm.model)
        return report


if __name__ == "__main__":
    print(json.dumps(TestingAgent().test(), indent=2))
