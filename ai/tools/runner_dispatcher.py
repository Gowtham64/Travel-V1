"""
Unified Server Execution Runner Dispatcher
Exposes a single control-plane interface to the Central AI Orchestrator.
Routes jobs to the appropriate execution runner node:
- Linux Runner Node: Web (Playwright Chromium), Backend API (Node 20), Android (SDK/Gradle)
- macOS Runner Node: iOS (Xcode 15 / xcrun simctl iOS Simulator)
"""

import os
import sys
from typing import Dict, Any

from ai.tools.tests import run_backend_tests, run_web_tests, run_mobile_tests
from ai.tools.mobile import run_ios_simulator_cycle, run_android_emulator_cycle

class ServerRunnerDispatcher:
    def __init__(self):
        self.capabilities = {
            "linux_runner": ["web", "backend", "android"],
            "macos_runner": ["ios"]
        }

    def run_target(self, target: str, root_dir: str = ".") -> Dict[str, Any]:
        """
        Dispatches test execution to the specialized server node.
        From the AI's perspective, this behaves as a single unified server testing system.
        """
        target = target.lower()
        if target == "web":
            print("[CONTROL PLANE -> LINUX RUNNER] Dispatching Web Chromium / Playwright suite...")
            return run_web_tests(cwd=root_dir)

        elif target == "backend":
            print("[CONTROL PLANE -> LINUX RUNNER] Dispatching Backend API & Jest suites...")
            return run_backend_tests(cwd=f"{root_dir}/backend" if root_dir != "." else "backend")

        elif target == "android":
            print("[CONTROL PLANE -> LINUX RUNNER] Dispatching Android SDK, ADB & Flutter suites...")
            unit_res = run_mobile_tests(test_path="test/vehicle_database_test.dart test/toll_test.dart", cwd=f"{root_dir}/mobile" if root_dir != "." else "mobile")
            emu_res = run_android_emulator_cycle()
            return {
                "runner": "linux",
                "platform": "android",
                "unit_tests": unit_res,
                "emulator_cycle": emu_res,
                "success": unit_res["success"]
            }

        elif target == "ios":
            print("[CONTROL PLANE -> macOS RUNNER] Dispatching iOS Xcode & Simulator (simctl) suite...")
            sim_res = run_ios_simulator_cycle()
            return {
                "runner": "macos",
                "platform": "ios",
                "simulator_cycle": sim_res,
                "success": sim_res["success"]
            }

        else:
            raise ValueError(f"Unknown execution target: {target}")

    def run_unified_matrix(self, root_dir: str = ".") -> Dict[str, Any]:
        """Runs the entire multi-runner suite and unifies evidence into one report."""
        print("\n" + "=" * 70)
        print("🧠 CENTRAL AI CONTROL PLANE: DISPATCHING UNIFIED MULTI-RUNNER TEST MATRIX")
        print("=" * 70)

        # 1. Linux Runner executions
        backend_res = self.run_target("backend", root_dir)
        web_res = self.run_target("web", root_dir)
        android_res = self.run_target("android", root_dir)

        # 2. macOS Runner execution
        ios_res = self.run_target("ios", root_dir)

        all_passed = (
            backend_res.get("success", True) and
            web_res.get("success", True) and
            android_res.get("success", True) and
            ios_res.get("success", True)
        )

        return {
            "control_plane": "VoyPlan AI Orchestrator v1.0",
            "all_passed": all_passed,
            "runners": {
                "linux_node": {
                    "backend": backend_res,
                    "web": web_res,
                    "android": android_res
                },
                "macos_node": {
                    "ios": ios_res
                }
            },
            "failures": (backend_res.get("failed_files", []) if not backend_res.get("success") else [])
        }

runner_dispatcher = ServerRunnerDispatcher()
