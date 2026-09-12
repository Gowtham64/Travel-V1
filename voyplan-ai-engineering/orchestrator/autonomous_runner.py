"""
VoyPlan Master Autonomous Engineering & Testing Runner
Coordinates all permanent agents in a continuous autonomous cycle:
DISCOVER ➔ TEST (iOS + Android + Web + AI + Maps) ➔ COMPARE ➔ DIAGNOSE ➔ REPORT ➔ HEAL
"""

import os
import sys
import json
import time
from datetime import datetime
from typing import Dict, Any

# Add voyplan-ai-engineering to sys.path
BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from device_lab.ios_device_tester import IOSDeviceTester
from device_lab.android_device_tester import AndroidDeviceTester
from test_engine.destination_integrity_tester import DestinationIntegrityTester
from test_engine.combinatorial_engine import CombinatorialTestEngine
from test_engine.cross_platform_comparator import CrossPlatformComparator
from product_brain.coverage_tracker import ProductCoverageTracker
from agents.repair.self_healing_agent import SelfHealingAgent

class AutonomousEngineeringRunner:
    def __init__(self, workspace_root: str = None):
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(BASE_DIR, ".."))
        self.reports_dir = os.path.join(BASE_DIR, "reports")
        os.makedirs(self.reports_dir, exist_ok=True)

        self.coverage_tracker = ProductCoverageTracker(workspace_root=self.workspace_root)
        self.ios_tester = IOSDeviceTester(workspace_root=self.workspace_root)
        self.android_tester = AndroidDeviceTester(workspace_root=self.workspace_root)
        self.integrity_tester = DestinationIntegrityTester(workspace_root=self.workspace_root)
        self.combinatorial_engine = CombinatorialTestEngine(workspace_root=self.workspace_root)
        self.comparator = CrossPlatformComparator(workspace_root=self.workspace_root)
        self.healer = SelfHealingAgent(workspace_root=self.workspace_root)

    def run_campaign(self) -> Dict[str, Any]:
        campaign_id = f"CMP-{int(time.time())}"
        print(f"\n=======================================================")
        print(f" 🚀 STARTING VOYPLAN AUTONOMOUS AI ENGINEERING CAMPAIGN: {campaign_id}")
        print(f" Timestamp: {datetime.now().isoformat()}")
        print(f"=======================================================")

        campaign_results = {
            "campaign_id": campaign_id,
            "timestamp": datetime.now().isoformat(),
            "stages": {}
        }

        # ── 1. iOS Human Testing on Real Device / Simulator ──
        print("\n[CAMPAIGN STAGE 1/5] 📱 Running iOS Human Tester...")
        ios_result = self.ios_tester.run_human_journey()
        campaign_results["stages"]["ios_testing"] = ios_result
        if ios_result.get("status") == "PASS":
            self.coverage_tracker.record_test_run(
                platform="iOS",
                test_type="LIFECYCLE_JOURNEY",
                screens_visited=["SCR_HOME", "SCR_PLANNER"],
                features_covered=["FEAT_DESTINATION_INTEGRITY"],
                evidence_path=ios_result.get("evidence", [None])[0] if ios_result.get("evidence") else None
            )

        # ── 2. Android Human Testing via ADB ──
        print("\n[CAMPAIGN STAGE 2/5] 🤖 Running Android Human Tester...")
        android_result = self.android_tester.run_human_journey()
        campaign_results["stages"]["android_testing"] = android_result
        if android_result.get("status") == "PASS":
            self.coverage_tracker.record_test_run(
                platform="Android",
                test_type="LIFECYCLE_JOURNEY",
                screens_visited=["SCR_HOME"],
                features_covered=["FEAT_DESTINATION_INTEGRITY"]
            )

        # ── 3. AI Destination & Route Integrity Audit ──
        print("\n[CAMPAIGN STAGE 3/5] 🛡️ Running Adversarial Destination Integrity Suite...")
        integrity_result = self.integrity_tester.run_suite()
        campaign_results["stages"]["destination_integrity"] = integrity_result

        # ── 4. Combinatorial Travel Matrix ──
        print("\n[CAMPAIGN STAGE 4/5] 🧪 Running Multi-Dimensional Combinatorial Engine...")
        comb_result = self.combinatorial_engine.run_matrix(sample_limit=3)
        campaign_results["stages"]["combinatorial_matrix"] = comb_result

        # ── 5. Cross-Platform Parity Evaluation ──
        print("\n[CAMPAIGN STAGE 5/5] ⚖️ Running Cross-Platform Parity Comparison...")
        comp_result = self.comparator.compare_runs(ios_run=ios_result, android_run=android_result)
        campaign_results["stages"]["cross_platform_parity"] = comp_result

        # ── Diagnosis & Defect Management ──
        defects_found = []
        for case in integrity_result.get("results", []):
            if case.get("status") != "PASS":
                defects_found.append({
                    "title": f"Integrity Defect: {case.get('pair')}",
                    "layer_failure": case.get("layer_failure", "UNKNOWN"),
                    "reason": case.get("reason", "Validation failure"),
                    "evidence": ["reports/destination-integrity-report.json"]
                })

        diagnoses = []
        if defects_found:
            print(f"\n[CAMPAIGN] 🚨 {len(defects_found)} Defect(s) Identified. Handing over to Root-Cause & Self-Healing Agent...")
            for d in defects_found:
                rep = self.healer.diagnose_defect(d, attempt=1)
                diagnoses.append(rep)
        else:
            print("\n[CAMPAIGN] ✨ Zero unhandled critical defects identified in this campaign run.")

        campaign_results["defects"] = diagnoses

        # Save Executive Summary
        summary_file = os.path.join(self.reports_dir, f"campaign-executive-summary.json")
        with open(summary_file, "w") as f:
            json.dump(campaign_results, f, indent=2)

        print("\n=======================================================")
        print(f" 🏁 VOYPLAN CAMPAIGN {campaign_id} COMPLETE")
        print(f" Executive Summary saved to: {summary_file}")
        print("=======================================================\n")
        return campaign_results

if __name__ == "__main__":
    runner = AutonomousEngineeringRunner()
    res = runner.run_campaign()
