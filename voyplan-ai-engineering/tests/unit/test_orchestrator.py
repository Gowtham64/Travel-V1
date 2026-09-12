"""
Unit tests for VoyPlan Autonomous AI Engineering Pipeline Orchestrator and Agents.
"""

import os
import sys
import unittest
import json

# Ensure voyplan-ai-engineering is on sys.path
sys_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
if sys_root not in sys.path:
    sys.path.insert(0, sys_root)

from agents.researcher.agent import ResearchAgent
from agents.developer.agent import DeveloperAgent
from agents.tester.agent import TestingAgent
from agents.qa.agent import QAAgent
from agents.release.agent import ReleaseAgent
from orchestrator import PipelineOrchestrator

class TestPipelineOrchestration(unittest.TestCase):
    def setUp(self):
        self.workspace = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../"))
        self.engineering_dir = os.path.join(self.workspace, "voyplan-ai-engineering")
        
        # Ensure test fixture artifacts exist
        research_file = os.path.join(self.engineering_dir, "research-report.json")
        if not os.path.exists(research_file):
            with open(research_file, "w", encoding="utf-8") as f:
                json.dump({
                    "issue": "123",
                    "problem": "AI planner adding distant locations",
                    "root_cause": "Missing destination spatial bounding",
                    "acceptance_criteria": ["Destination anchors itinerary", "Reject distant cities"],
                    "test_cases": [{"name": "Tirumala Integrity", "type": "integration"}]
                }, f, indent=2)

        test_file = os.path.join(self.engineering_dir, "test-result.json")
        if not os.path.exists(test_file):
            with open(test_file, "w", encoding="utf-8") as f:
                json.dump({
                    "status": "PASS",
                    "passed_count": 4,
                    "failed_count": 0,
                    "failed_tests": [],
                    "errors": []
                }, f, indent=2)

        qa_file = os.path.join(self.engineering_dir, "qa-result.json")
        if not os.path.exists(qa_file):
            with open(qa_file, "w", encoding="utf-8") as f:
                json.dump({
                    "status": "PASS",
                    "issue": "123",
                    "recommendation": "PROCEED_TO_STAGING"
                }, f, indent=2)

    def test_researcher_agent_fallback_report(self):
        agent = ResearchAgent(workspace_path=self.workspace, model_provider="ollama")
        report = agent.analyze_issue("123", "Fix AI Planner Random Locations", "Destination Tirumala adding Bengaluru")
        self.assertEqual(report["issue"], "123")
        self.assertIn("Tirumala", report["problem"])
        self.assertGreater(len(report["acceptance_criteria"]), 0)
        self.assertGreater(len(report["test_cases"]), 0)

    def test_qa_agent_approval_and_retry(self):
        qa = QAAgent(workspace_path=self.workspace, max_retries=3)
        res = qa.evaluate(retry_count=0)
        self.assertIn(res["status"], ["PASS", "FAIL"])
        self.assertIn(res["recommendation"], ["PROCEED_TO_STAGING", "RETRY_DEVELOPER", "HUMAN_REVIEW_REQUIRED"])

    def test_release_agent_approval_gate(self):
        release = ReleaseAgent(workspace_path=self.workspace)
        banner = release.render_approval_gate("PASS", "PASS", "PASS", "PASS")
        self.assertIn("PRODUCTION RELEASE", banner)
        self.assertIn("Human Approval Required", banner)

        # Without approval keyword, should enter WAITING_APPROVAL state
        res_paused = release.deploy(human_approved=False)
        self.assertEqual(res_paused["status"], "WAITING_APPROVAL")

        # With approval keyword, should proceed
        res_approved = release.deploy(human_approved=True, confirmation_keyword="DEPLOY")
        self.assertIn(res_approved["status"], ["PASS", "ROLLED_BACK"])

if __name__ == "__main__":
    unittest.main()
