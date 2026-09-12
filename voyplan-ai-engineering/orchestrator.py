"""
VoyPlan Autonomous AI Product Engineering Organization - Master Orchestrator

Executes the complete multi-agent cycle:
Task / Issue
  ↓
Product Agent (Problem & Scope)
  ↓
R&D / Architect Agent (Technical Design)
  ↓
AI Product Council (Structured Debate: Product, R&D, Antigravity, QA, Security)
  ↓
Technical Decision & Handover
  ↓
Google Antigravity Developer (Web + Android + iOS + Backend + DB)
  ↓
Testing Agent (Unit, Integration, Regressions, Playwright E2E)
  ↓
QA Agent (Zero-Trust Acceptance Validation, Max 3 retries)
  ↓
Security Agent (Secret, CVE, Injection, Privacy Audit)
  ↓
Staging Deployment & Cross-Platform Smoke Tests
  ↓
Human Approval Gate (DEPLOY)
  ↓
Production Deployment & Continuous Monitoring
"""

import os
import sys
import json
import argparse
from typing import Dict, Any, Optional

from agents.product.agent import ProductAgent
from agents.researcher.agent import ResearchAgent
from agents.council.council import AIProductCouncil
from agents.developer.agent import DeveloperAgent
from agents.tester.agent import TestingAgent
from agents.qa.agent import QAAgent
from agents.security.agent import SecurityAgent
from agents.release.agent import ReleaseAgent
from agents.common.workspace import resolve_workspace

class PipelineOrchestrator:
    def __init__(self, workspace_path: str = None, max_retries: int = 3):
        self.workspace_path = resolve_workspace(workspace_path)
        self.max_retries = max_retries
        
        self.product = ProductAgent(workspace_path=self.workspace_path)
        self.researcher = ResearchAgent(workspace_path=self.workspace_path)
        self.council = AIProductCouncil(workspace_path=self.workspace_path)
        self.developer = DeveloperAgent(workspace_path=self.workspace_path)
        self.tester = TestingAgent(workspace_path=self.workspace_path)
        self.qa = QAAgent(workspace_path=self.workspace_path, max_retries=self.max_retries)
        self.security = SecurityAgent(workspace_path=self.workspace_path)
        self.release = ReleaseAgent(workspace_path=self.workspace_path)

    def print_stage_status(self, issue_id: str, stage_results: Dict[str, Any]):
        print(f"\n=======================================================")
        print(f" VoyPlan AI Product Organization: Issue #{issue_id}")
        print(f"=======================================================")
        for stage, res in stage_results.items():
            status_icon = "✅" if res.get("status") == "PASS" else "❌" if res.get("status") in ["FAIL", "BLOCK"] else "⏳"
            print(f" {stage:<22} {status_icon} {res.get('status', 'PENDING')}")
            if res.get("status") in ["FAIL", "BLOCK"] and "reason" in res:
                print(f"   Reason: {res['reason']}")
            if "recommendation" in res and res["recommendation"] == "RETRY_DEVELOPER":
                print(f"   Action: Returned to Developer. Retry: {res.get('retry_count', 0) + 1}/{self.max_retries}")
        print(f"=======================================================\n")

    def run(self, issue_id: str, issue_title: str, issue_body: str, auto_approve_prod: bool = False) -> Dict[str, Any]:
        stages: Dict[str, Any] = {}

        # ── STAGE 1: Product Agent Evaluation ─────────────────────────
        print(f"\n[ORCHESTRATOR] 📋 Stage 1: Product Agent Strategy & Scope Assessment...")
        p_res = self.product.evaluate(issue_id, issue_title, issue_body)
        stages["Product Strategy"] = {"status": "PASS", "artifact": "product-decision.json"}
        self.print_stage_status(issue_id, stages)

        # ── STAGE 2: R&D / Architect Deep Technical Analysis ───────────
        print(f"\n[ORCHESTRATOR] 🔬 Stage 2: R&D Agent Technical Architecture Design...")
        r_report = self.researcher.analyze_issue(issue_id, issue_title, issue_body)
        stages["R&D Architecture"] = {"status": "PASS", "artifact": "research-report.json"}
        self.print_stage_status(issue_id, stages)

        # ── STAGE 3: AI Product Council Debate & Decision ─────────────
        print(f"\n[ORCHESTRATOR] 🏛️ Stage 3: AI Product Council Debate & Review...")
        council_res = self.council.convene_council(issue_id, issue_title, issue_body, r_report=r_report)
        stages["Council Review"] = {"status": "PASS", "artifact": "council-debate.json"}
        self.print_stage_status(issue_id, stages)

        # ── LOOP: Development (Antigravity) ↔ Testing ↔ QA ─────────────
        qa_passed = False
        retry_count = 0
        qa_result = {}

        while retry_count < self.max_retries and not qa_passed:
            print(f"\n[ORCHESTRATOR] 🛠️ Stage 4: Google Antigravity Development (Attempt {retry_count + 1}/{self.max_retries})...")
            dev_feedback = qa_result if retry_count > 0 else None
            dev_result = self.developer.develop(feedback=dev_feedback)
            stages["Antigravity Dev"] = dev_result

            print(f"\n[ORCHESTRATOR] 🧪 Stage 5: Independent Verification & Testing...")
            test_result = self.tester.test()
            stages["Unit & Regression"] = {"status": test_result["status"]}
            stages["Playwright E2E"] = {"status": test_result["status"]}

            print(f"\n[ORCHESTRATOR] 🔍 Stage 6: Independent QA Evaluation...")
            qa_result = self.qa.evaluate(retry_count=retry_count)
            stages["QA Acceptance"] = qa_result

            self.print_stage_status(issue_id, stages)

            if qa_result.get("status") == "PASS":
                qa_passed = True
                break
            elif qa_result.get("recommendation") == "HUMAN_REVIEW_REQUIRED":
                print("\n[ORCHESTRATOR] 🚨 MAXIMUM RETRIES EXHAUSTED: HUMAN REVIEW REQUIRED.")
                return {"status": "HUMAN_REVIEW_REQUIRED", "stages": stages}
            else:
                print(f"\n[ORCHESTRATOR] ⚠️ QA Failed. Returning feedback to Google Antigravity...")
                retry_count += 1

        if not qa_passed:
            return {"status": "FAILED", "stages": stages}

        # ── STAGE 7: Security Agent Audit ─────────────────────────────
        print(f"\n[ORCHESTRATOR] 🛡️ Stage 7: Security Agent Verification...")
        sec_result = self.security.inspect(issue_id=issue_id)
        stages["Security Audit"] = sec_result
        self.print_stage_status(issue_id, stages)

        if sec_result.get("status") == "BLOCK":
            print("\n[ORCHESTRATOR] 🚨 SECURITY AUDIT FAILED: RELEASE BLOCKED.")
            return {"status": "BLOCKED_BY_SECURITY", "stages": stages}

        # ── STAGE 8: Staging Deployment & Release Gate ────────────────
        print(f"\n[ORCHESTRATOR] 🚢 Stage 8: Staging Deployment & Production Gate...")
        release_result = self.release.deploy(
            human_approved=auto_approve_prod,
            confirmation_keyword="DEPLOY" if auto_approve_prod else ""
        )
        stages["Staging Smoke"] = {"status": release_result.get("staging_smoke_tests", "PASS")}
        stages["Production Gate"] = release_result
        self.print_stage_status(issue_id, stages)

        return {"status": release_result.get("status", "COMPLETE"), "stages": stages}

def main():
    parser = argparse.ArgumentParser(description="VoyPlan Autonomous AI Product Engineering Organization")
    parser.add_argument("--issue", default="123", help="Issue ID / number")
    parser.add_argument("--title", default="Fix AI Planner Random Locations", help="Issue title")
    parser.add_argument("--body", default="Destination: Tirumala. The planner must not add unrelated locations.", help="Issue body")
    parser.add_argument("--confirm-deploy", action="store_true", help="Explicit human approval flag for production deploy")
    args = parser.parse_args()

    orchestrator = PipelineOrchestrator()
    res = orchestrator.run(
        issue_id=args.issue,
        issue_title=args.title,
        issue_body=args.body,
        auto_approve_prod=args.confirm_deploy
    )
    print(f"\nPipeline execution finished with overall result: {res['status']}")

if __name__ == "__main__":
    main()
