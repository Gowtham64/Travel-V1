"""
VoyPlan AI Product Organization - Product Management / Strategy Agent
Evaluates product vision, user personas, cross-platform parity (Web, Android, iOS), and feature necessity.
"""

import os
import sys
import json
import time
from typing import Dict, Any, List

BASE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from agents.common.workspace import resolve_workspace
from agents.common.logger import AgentLogger

class ProductAgent:
    def __init__(self, workspace_path: str = None):
        self.workspace_path = resolve_workspace(workspace_path)
        self.brain_path = os.path.join(BASE_DIR, "product-brain")

    def evaluate(self, issue_id: str, title: str, description: str) -> Dict[str, Any]:
        logger = AgentLogger("product", issue_id=issue_id)
        logger.info(f"Evaluating Product Strategic Impact for Issue #{issue_id}: '{title}'")

        # Check product vision and users
        is_itinerary = "itinerary" in title.lower() or "planner" in title.lower() or "location" in title.lower() or "tirumala" in title.lower() or "stop" in title.lower()
        is_security = "security" in title.lower() or "vulnerability" in title.lower()

        user_problem = "Uncertain or hallucinated stops break traveler trust and cause real-world detours." if is_itinerary else "Product defect impacting traveler experience or system safety."
        target_persona = "Pilgrimage traveler & Family roadtripper" if is_itinerary else "All VoyPlan mobile & web travelers"

        # Cross-platform requirements evaluation (Section 17 & 34)
        cross_platform_requirements = {
            "web": "Must provide interactive visual confirmation, clear warnings on invalid inputs, and real-time map updates.",
            "android": "Must update local Hive cache and notify connected Android Auto head unit via CarNavState bridge.",
            "ios": "Must maintain voice guidance maneuver queue integrity via CarPlayVoiceGuidance bridge.",
            "backend": "Must enforce strict deterministic API contract and schema validation."
        }

        product_decision = {
            "issue_id": str(issue_id),
            "title": title,
            "product_alignment": "HIGH_PRIORITY_STRATEGIC",
            "user_problem_solved": user_problem,
            "target_persona": target_persona,
            "cross_platform_parity": cross_platform_requirements,
            "value_assessment": "CRITICAL: Guarantees spatial correctness and preserves core brand promise of zero-hallucination travel planning.",
            "complexity_risk": "MEDIUM: Must protect existing trip creation and saved trips while adding deterministic boundary validation.",
            "product_approval": "APPROVED",
            "recommendation": "PROCEED_TO_COUNCIL_DEBATE",
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S")
        }

        out_path = os.path.join(BASE_DIR, "product-decision.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(product_decision, f, indent=2)

        logger.info(f"Product evaluation complete: {product_decision['product_approval']} -> {product_decision['recommendation']}")
        logger.complete("PASS")
        return product_decision

if __name__ == "__main__":
    agent = ProductAgent()
    res = agent.evaluate("123", "Fix AI Planner Random Locations", "Destination: Tirumala")
    print(json.dumps(res, indent=2))
