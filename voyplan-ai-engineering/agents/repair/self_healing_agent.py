"""
VoyPlan Root-Cause & Self-Healing Repair Agent
Analyzes confirmed test defects, performs layered root-cause analysis,
generates structured bug reports, fix specifications, and coordinates Antigravity repairs.
Enforces the strict max 3 retries limit.
"""

import os
import json
import time
from datetime import datetime
from typing import Dict, Any, List, Optional

class SelfHealingAgent:
    MAX_REPAIR_ATTEMPTS = 3

    def __init__(self, workspace_root: Optional[str] = None):
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
        self.reports_dir = os.path.join(self.workspace_root, "voyplan-ai-engineering/reports")
        self.artifacts_dir = os.path.join(self.workspace_root, "voyplan-ai-engineering/artifacts")
        os.makedirs(self.reports_dir, exist_ok=True)
        os.makedirs(self.artifacts_dir, exist_ok=True)

    def diagnose_defect(self, defect_data: Dict[str, Any], attempt: int = 1) -> Dict[str, Any]:
        """Performs structured root-cause diagnosis on any reported failure."""
        timestamp = datetime.now().isoformat()
        bug_id = f"BUG-{int(time.time())}"
        title = defect_data.get("title") or defect_data.get("pair") or "Automated Test Anomaly"
        platform = defect_data.get("platform", "Cross-Platform")
        layer = defect_data.get("layer_failure", "UNKNOWN_LAYER")
        reason = defect_data.get("reason", "Validation failure")
        evidence = defect_data.get("evidence", [])

        # Determine confidence and root-cause explanation
        confidence = "HIGH" if layer != "UNKNOWN_LAYER" else "MEDIUM"
        
        root_cause_map = {
            "GEMINI_OR_POI_CANDIDATE_FILTER": "Out-of-boundary candidate was admitted into the prompt or unconstrained Gemini suggested stops outside destination radius.",
            "GEO_VALIDATION_RADIUS": "Geographic distance threshold exceeded the configured destination perimeter.",
            "BACKEND_SERVICE": "Backend validator rejected generated itinerary after 3 cycles due to incompatible constraints (e.g. missing requested category stops in single day).",
            "NETWORK_API": "Connection timeout or unreachable backend endpoint.",
            "LIFECYCLE_CRASH": "Mobile process terminated unexpectedly during backgrounding or resume."
        }
        root_cause_explanation = root_cause_map.get(layer, reason)

        bug_report = {
            "bug_id": bug_id,
            "title": title,
            "platform": platform,
            "severity": "P1" if "destination" in title.lower() or "crash" in title.lower() else "P2",
            "attempt": attempt,
            "max_attempts": self.MAX_REPAIR_ATTEMPTS,
            "steps": defect_data.get("steps", ["Execute automated test journey", "Assert boundary constraints"]),
            "expected": defect_data.get("expected", "All stops within destination boundary and HTTP 200 approved"),
            "actual": reason,
            "evidence": evidence,
            "root_cause": root_cause_explanation,
            "confidence": confidence,
            "affected_layer": layer,
            "impact": "High - degraded itinerary reliability or user friction",
            "status": "OPEN" if attempt <= self.MAX_REPAIR_ATTEMPTS else "HUMAN_REVIEW_REQUIRED",
            "timestamp": timestamp
        }

        # Save bug report
        bug_file = os.path.join(self.reports_dir, f"bug-report-{bug_id}.json")
        with open(bug_file, "w") as f:
            json.dump(bug_report, f, indent=2)

        # Generate fix specification
        solution_spec = {
            "task_id": f"fix_{bug_id}",
            "agent": "ROOT_CAUSE_AND_REPAIR",
            "bug_id": bug_id,
            "target_layer": layer,
            "proposed_fix": f"Tune validation threshold or candidate filter in {layer}",
            "verification_command": "python3 voyplan-ai-engineering/test-engine/destination_integrity_tester.py",
            "requires_human": attempt > self.MAX_REPAIR_ATTEMPTS,
            "timestamp": timestamp
        }

        sol_file = os.path.join(self.artifacts_dir, "solution.json")
        with open(sol_file, "w") as f:
            json.dump(solution_spec, f, indent=2)

        print(f"\n[SELF-HEALING AGENT] 🩺 Diagnosed Defect {bug_id} ({confidence} confidence):")
        print(f" Layer: {layer} | Cause: {root_cause_explanation}")
        if attempt > self.MAX_REPAIR_ATTEMPTS:
            print("[SELF-HEALING AGENT] ⚠️ Max 3 repair attempts reached. Flagging for HUMAN_REVIEW_REQUIRED.")
        else:
            print(f"[SELF-HEALING AGENT] 🛠️ Fix specification prepared (Attempt {attempt}/{self.MAX_REPAIR_ATTEMPTS}).")

        return bug_report

if __name__ == "__main__":
    agent = SelfHealingAgent()
    sample = {
        "title": "Chennai to Pondicherry 422 Category Rejection",
        "platform": "Backend AI Engine",
        "layer_failure": "BACKEND_SERVICE",
        "reason": "Itinerary validator rejected draft due to missing category stops in single day transit",
        "evidence": ["reports/destination-integrity-report.json"]
    }
    rep = agent.diagnose_defect(sample)
    print(json.dumps(rep, indent=2))
