"""
VoyPlan 24/7 Autonomous AI Engineering Team - Continuous Daemon

Runs an autonomous daemon loop:
1. Scans backlog and task queue by priority (P0 → P5).
2. Manages resource locks to allow safe concurrent execution.
3. Coordinates:
   R&D Agent (Full-Stack Impact) → Developer Agent → Testing Agent → QA Agent → Staging → Release Gate.
4. Auto-detects regressions and creates automatic tickets if tests break.
"""

import os
import sys
import time
import argparse
import threading
from typing import Dict, Any, Optional

from taskqueue.queue_manager import QueueManager
from agents.researcher.agent import ResearchAgent
from agents.developer.agent import DeveloperAgent
from agents.tester.agent import TestingAgent
from agents.qa.agent import QAAgent
from agents.release.agent import ReleaseAgent
from agents.researcher.autonomous_scanner import AutonomousScanner
from agents.common.workspace import resolve_workspace

class AutonomousDaemon:
    def __init__(self, workspace_path: str = None, poll_interval_seconds: int = 10):
        self.workspace_path = resolve_workspace(workspace_path)
        self.poll_interval = poll_interval_seconds
        self.queue_mgr = QueueManager()
        self.scanner = AutonomousScanner(workspace_path=self.workspace_path)
        self.running = False

        self.researcher = ResearchAgent(workspace_path=self.workspace_path)
        self.developer = DeveloperAgent(workspace_path=self.workspace_path)
        self.tester = TestingAgent(workspace_path=self.workspace_path)
        self.qa = QAAgent(workspace_path=self.workspace_path)
        self.release = ReleaseAgent(workspace_path=self.workspace_path)

    def scan_background_bugs(self):
        """Scans codebase for regressions, dependencies, and conceives new features."""
        print(" [24/7 DAEMON] Running autonomous discovery scanner (bugs & feature proposals)...")
        return self.scanner.run_all_scans()

    def process_task(self, task: Dict[str, Any], auto_deploy: bool = False):
        task_id = task["id"]
        title = task["title"]
        desc = task["description"]
        priority = task.get("priority", "P3")
        resources = task.get("locked_resources", [])

        print(f"\n=======================================================")
        print(f" [24/7 DAEMON] Processing Task #{task_id} [{priority}]: {title}")
        print(f"=======================================================")

        # 1. Acquire Resource Locks
        if not self.queue_mgr.acquire_locks(task_id, resources):
            print(f" [24/7 DAEMON] Resource conflict detected for Task #{task_id}. Re-queuing...")
            return

        try:
            # ── STAGE 1: R&D & Full-Stack Architecture Analysis ──
            self.queue_mgr.update_task_status(task_id, "RESEARCHING")
            print(f" [24/7 DAEMON] R&D Agent analyzing Task #{task_id}...")
            r_report = self.researcher.analyze_issue(task_id, title, desc)

            # ── STAGE 2: Full-Stack Development ──
            self.queue_mgr.update_task_status(task_id, "DEVELOPING")
            print(f" [24/7 DAEMON] Developer Agent implementing Task #{task_id}...")
            dev_res = self.developer.develop()
            self.queue_mgr.increment_stat("prs_created", 1)

            # ── STAGE 3: Testing ──
            self.queue_mgr.update_task_status(task_id, "TESTING")
            print(f" [24/7 DAEMON] Testing Agent executing verification suites...")
            test_res = self.tester.test()
            self.queue_mgr.increment_stat("tests_executed", test_res.get("passed_count", 4))

            # ── STAGE 4: QA ──
            self.queue_mgr.update_task_status(task_id, "QA")
            print(f" [24/7 DAEMON] QA Agent validating acceptance criteria...")
            qa_res = self.qa.evaluate(retry_count=task.get("retry_count", 0))

            if qa_res.get("status") == "PASS":
                # ── STAGE 5: Staging & Release ──
                self.queue_mgr.update_task_status(task_id, "STAGING")
                print(f" [24/7 DAEMON] Release Agent deploying to Staging...")
                rel_res = self.release.deploy(human_approved=auto_deploy, confirmation_keyword="DEPLOY" if auto_deploy else "")

                if rel_res.get("status") == "PASS":
                    self.queue_mgr.update_task_status(task_id, "RELEASED")
                    self.queue_mgr.increment_stat("completed_today", 1)
                    self.queue_mgr.increment_stat("deployments", 1)
                    print(f" [24/7 DAEMON] ✅ Task #{task_id} RELEASED to Production successfully!")
                else:
                    self.queue_mgr.update_task_status(task_id, "READY_FOR_RELEASE")
                    print(f" [24/7 DAEMON] ⏳ Task #{task_id} deployed to Staging. Waiting for human approval.")
            else:
                self.queue_mgr.update_task_status(task_id, "FAILED", error_reason=qa_res.get("reason"))
                self.queue_mgr.increment_stat("failed_today", 1)
                self.queue_mgr.increment_stat("qa_failures", 1)
                print(f" [24/7 DAEMON] ❌ Task #{task_id} QA Failed. Reason: {qa_res.get('reason')}")

        finally:
            # Release resource locks
            self.queue_mgr.release_locks(task_id)

    def run_continuous(self, auto_deploy: bool = False):
        self.running = True
        print("🚀 [24/7 DAEMON] VoyPlan Autonomous AI Engineering Team started in 24/7 continuous mode.")
        self.scan_background_bugs()
        last_scan = time.time()
        try:
            while self.running:
                # Run autonomous scanner every 120s or when idle
                if time.time() - last_scan > 120:
                    self.scan_background_bugs()
                    last_scan = time.time()

                task = self.queue_mgr.get_next_task()
                if task:
                    self.process_task(task, auto_deploy=auto_deploy)
                else:
                    time.sleep(self.poll_interval)
        except KeyboardInterrupt:
            print("\n[24/7 DAEMON] Stopping continuous engineering daemon...")
            self.running = False

def main():
    parser = argparse.ArgumentParser(description="VoyPlan 24/7 Autonomous AI Engineering Team Daemon")
    parser.add_argument("--auto-deploy", action="store_true", help="Auto-deploy to production on approval")
    parser.add_argument("--once", action="store_true", help="Process only next available task in queue and exit")
    parser.add_argument("--interval", type=int, default=10, help="Polling interval in seconds")
    args = parser.parse_args()

    daemon = AutonomousDaemon(poll_interval_seconds=args.interval)
    if args.once:
        task = daemon.queue_mgr.get_next_task()
        if task:
            daemon.process_task(task, auto_deploy=args.auto_deploy)
        else:
            print("No pending tasks in queue.")
    else:
        daemon.run_continuous(auto_deploy=args.auto_deploy)

if __name__ == "__main__":
    main()
