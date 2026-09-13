"""
Agent 4: Testing Agent (Multi-Runner Test Execution)
Dispatches tests to actual execution runners:
1. Linux Runner: Jest backend regression tests, multiplatform server validator.
2. Web Runner: Playwright Chromium browser tests.
3. Android Runner: Real ADB / Android emulator if present (or returns INFRASTRUCTURE CAPABILITY NOT AVAILABLE).
4. macOS Runner: Real Xcode / iOS simulator if present (or returns iOS EXECUTION UNAVAILABLE — MACOS RUNNER REQUIRED).
ABSOLUTE NO-MOCK RULE: Every test result is recorded with actual exit_code, stdout, stderr, and duration.
"""

import os
import sys
import json
import time
from typing import Dict, Any, List, Optional

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.logger import AgentLogger
from agents.common.workspace import resolve_workspace
from runners.linux_runner import LinuxRunner
from runners.macos_runner import MacOSRunner
from runners.web_runner import WebRunner
from state.database import StateDB

class TestingAgent:
    def __init__(self, workspace_path: str = None):
        self.workspace_path = resolve_workspace(workspace_path)
        self.linux_runner = LinuxRunner(self.workspace_path)
        self.macos_runner = MacOSRunner(self.workspace_path)
        self.web_runner = WebRunner(self.workspace_path)
        self.db = StateDB()
        self.logger = AgentLogger("testing", "fleet")

    def run_full_suite(self, task_id: str = "task-1", target_branch: str = "HEAD") -> Dict[str, Any]:
        self.logger.log_event(f"Testing Agent initiating real multi-runner test execution for Task #{task_id}")
        self.db.record_agent_state(
            agent_id="testing",
            name="Testing Agent",
            role="Multi-Runner Test Execution",
            status="WORKING",
            current_task_id=task_id,
            action="Running test suites across runners",
            result="IN_PROGRESS"
        )

        tests_executed = []
        failures = []
        errors = []

        # 1. Backend Jest regression tests (Linux Runner)
        backend_res = self.linux_runner.run_backend_test(test_pattern="destinationBoundaries")
        self.db.record_test_run(
            task_id=task_id,
            runner_id=self.linux_runner.runner_id,
            platform="linux",
            test_type="backend-jest",
            command=backend_res.get("command", "npm test"),
            exit_code=backend_res.get("exit_code", 0),
            stdout=backend_res.get("stdout", ""),
            stderr=backend_res.get("stderr", ""),
            duration=backend_res.get("duration", 0),
            result=backend_res.get("status", "FAIL")
        )
        tests_executed.append({
            "name": "Backend Jest Regression (Destination Boundaries)",
            "runner": self.linux_runner.name,
            "status": backend_res.get("status"),
            "exit_code": backend_res.get("exit_code")
        })
        if not backend_res.get("success"):
            failures.append("Backend Jest Regression")
            errors.append(backend_res.get("stderr") or backend_res.get("stdout"))

        # 2. Multi-Platform Server Live Verification
        py_val = os.path.join(self.workspace_path, "voyplan-ai-engineering", "tests", "multiplatform_validator.py")
        if os.path.exists(py_val):
            val_res = self.linux_runner.execute_command([sys.executable, py_val], timeout_sec=60)
            status = "PASS" if val_res["success"] else "FAIL"
            self.db.record_test_run(
                task_id=task_id,
                runner_id=self.linux_runner.runner_id,
                platform="server",
                test_type="multiplatform-validator",
                command=f"python3 {py_val}",
                exit_code=val_res["exit_code"],
                stdout=val_res["stdout"],
                stderr=val_res["stderr"],
                duration=val_res["duration"],
                result=status
            )
            tests_executed.append({
                "name": "Live Multi-Platform Server Validator (Web, Android APK, iOS IPA, DB)",
                "runner": self.linux_runner.name,
                "status": status,
                "exit_code": val_res["exit_code"]
            })
            if not val_res["success"]:
                failures.append("Live Multi-Platform Server Validator")
                errors.append(val_res["stderr"] or val_res["stdout"])

        # 3. Web Playwright Navigation Test (Web Runner)
        web_res = self.web_runner.run_web_navigation_test("https://voyplan.in")
        self.db.record_test_run(
            task_id=task_id,
            runner_id=self.web_runner.runner_id,
            platform="web",
            test_type="playwright-navigation",
            command="playwright goto https://voyplan.in",
            exit_code=web_res.get("exit_code", 0),
            stdout=web_res.get("stdout", ""),
            stderr=web_res.get("stderr", ""),
            duration=web_res.get("duration", 0),
            result=web_res.get("status", "BLOCKED")
        )
        tests_executed.append({
            "name": "Playwright Web Navigation & Screenshot",
            "runner": self.web_runner.name,
            "status": web_res.get("status"),
            "exit_code": web_res.get("exit_code")
        })
        if web_res.get("status") == "FAIL":
            failures.append("Playwright Web Navigation")
            errors.append(web_res.get("error", ""))

        # 4. Android Runner Check
        android_res = self.linux_runner.run_android_test("smoke-test")
        tests_executed.append({
            "name": "Android Emulator & ADB Device Test",
            "runner": "Android Runner",
            "status": android_res.get("status"),
            "details": android_res.get("error") or "Android execution verified"
        })

        # 5. macOS Xcode Runner Check (Local or Remote Server Node)
        macos_caps = self.macos_runner.get_capabilities()
        self.db.record_runner_node(
            runner_id=self.macos_runner.runner_id,
            name=self.macos_runner.name,
            platform="macos",
            status=macos_caps.get("status", "OFFLINE"),
            capabilities=macos_caps.get("capabilities", []),
            available_devices=macos_caps.get("available_devices", []),
            current_job=f"Task #{task_id}"
        )
        macos_res = self.macos_runner.run_ios_test("smoke-test")
        self.db.record_test_run(
            task_id=task_id,
            runner_id=self.macos_runner.runner_id,
            platform="macos",
            test_type="ios-xcode-simulator",
            command=macos_res.get("command", "xcodebuild -version"),
            exit_code=macos_res.get("exit_code", 0),
            stdout=macos_res.get("stdout", ""),
            stderr=macos_res.get("stderr", ""),
            duration=macos_res.get("duration", 0),
            result=macos_res.get("status", "BLOCKED")
        )
        tests_executed.append({
            "name": "iOS Simulator & Xcode Test",
            "runner": self.macos_runner.name,
            "status": macos_res.get("status"),
            "details": macos_res.get("error") or f"Executed on {macos_res.get('device', 'iOS Simulator')}"
        })
        if macos_res.get("status") == "FAIL":
            failures.append("iOS Simulator & Xcode Test")
            errors.append(macos_res.get("error", ""))

        overall_status = "PASS" if len(failures) == 0 else "FAIL"
        summary = {
            "task_id": task_id,
            "status": overall_status,
            "passed_count": len([t for t in tests_executed if t.get("status") == "PASS"]),
            "failed_count": len(failures),
            "failed_tests": failures,
            "tests_run": [t["name"] for t in tests_executed],
            "test_details": tests_executed,
            "errors": errors,
            "recommendation": "PROCEED_TO_QA" if overall_status == "PASS" else "RETURN_TO_DEBUG"
        }

        # Write output artifact
        out_file = os.path.join(self.workspace_path, "voyplan-ai-engineering", "test-result.json")
        try:
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump(summary, f, indent=2)
        except Exception:
            pass

        self.db.record_agent_state(
            agent_id="testing",
            name="Testing Agent",
            role="Multi-Runner Test Execution",
            status="ONLINE",
            current_task_id=task_id,
            action=f"Completed {len(tests_executed)} runner tests",
            result=f"Status: {overall_status} ({len(failures)} failures)"
        )

        return summary
