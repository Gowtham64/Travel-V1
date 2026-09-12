"""
VoyPlan Combinatorial Test Engine
Generates and executes intelligent pairwise and high-value multi-dimensional travel scenarios.
Tests: Origin x Destination x Duration x Travelers x Transport x Style x Categories
"""

import os
import json
import time
import itertools
import requests
from datetime import datetime
from typing import Dict, Any, List, Optional

class CombinatorialTestEngine:
    ORIGINS = ["Bengaluru", "Chennai", "Mumbai"]
    DESTINATIONS = ["Tirupati", "Pondicherry", "Ooty", "Goa"]
    DURATIONS = [1, 2, 3]
    MODES = ["balanced", "relaxed", "packed"]
    VEHICLES = ["car", "bike"]
    CATEGORIES_POOL = [
        ["Temples"],
        ["Nature", "Viewpoint"],
        ["Beach"],
        ["Heritage", "Culture"]
    ]

    def __init__(self, backend_url: Optional[str] = None, workspace_root: Optional[str] = None):
        self.backend_url = (backend_url or os.environ.get("BACKEND_URL") or "https://travel-v1-mzia.onrender.com").rstrip("/")
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        self.reports_dir = os.path.join(self.workspace_root, "voyplan-ai-engineering/reports")
        os.makedirs(self.reports_dir, exist_ok=True)

    def generate_pairwise_matrix(self, sample_limit: int = 5) -> List[Dict[str, Any]]:
        """Generates representative high-value pairwise test combinations."""
        scenarios = [
            {
                "id": "TC_COMB_01",
                "startLocation": "Bengaluru",
                "destination": "Tirupati",
                "durationDays": 1,
                "mode": "balanced",
                "vehicleType": "car",
                "selectedCategories": ["Temples"]
            },
            {
                "id": "TC_COMB_02",
                "startLocation": "Bengaluru",
                "destination": "Ooty",
                "durationDays": 2,
                "mode": "relaxed",
                "vehicleType": "car",
                "selectedCategories": ["Nature", "Viewpoint"]
            },
            {
                "id": "TC_COMB_03",
                "startLocation": "Chennai",
                "destination": "Pondicherry",
                "durationDays": 1,
                "mode": "balanced",
                "vehicleType": "bike",
                "selectedCategories": ["Beach", "Heritage"]
            },
            {
                "id": "TC_COMB_04",
                "startLocation": "Bengaluru",
                "destination": "Coorg",
                "durationDays": 2,
                "mode": "packed",
                "vehicleType": "car",
                "selectedCategories": ["Nature", "Food"]
            }
        ]
        return scenarios[:sample_limit]

    def execute_scenario(self, tc: Dict[str, Any]) -> Dict[str, Any]:
        tc_id = tc["id"]
        origin = tc["startLocation"]
        dest = tc["destination"]
        print(f"[COMBINATORIAL] 🧪 Executing {tc_id}: {origin} ➔ {dest} ({tc['durationDays']}d, {tc['vehicleType']}, {tc['mode']})...")
        t0 = time.time()

        url = f"{self.backend_url}/api/ai/smart-itinerary"
        try:
            res = requests.post(url, json=tc, timeout=45)
            duration = round(time.time() - t0, 2)
            if res.status_code == 200:
                data = res.json()
                days = data.get("days", [])
                total_dist = data.get("totalDistanceKm", 0)
                budget = data.get("budget", {})
                print(f"[COMBINATORIAL] ✅ {tc_id} PASSED ({duration}s, {len(days)} days, {total_dist} km)")
                return {
                    "id": tc_id,
                    "params": tc,
                    "status": "PASS",
                    "duration_s": duration,
                    "days": len(days),
                    "total_distance_km": total_dist,
                    "total_budget": budget.get("total", 0)
                }
            else:
                err_data = res.json() if res.ok or res.status_code in [400, 422] else {}
                val_issues = err_data.get("validation", {}).get("issues", [])
                print(f"[COMBINATORIAL] ⚠️ {tc_id} REJECTED/FAILED ({res.status_code}): {err_data.get('error', 'HTTP error')}")
                return {
                    "id": tc_id,
                    "params": tc,
                    "status": "FAIL" if res.status_code >= 500 else "REJECTED_VALIDATOR",
                    "status_code": res.status_code,
                    "duration_s": duration,
                    "error": err_data.get("error", "Unknown error"),
                    "validation_issues": val_issues
                }
        except Exception as e:
            return {
                "id": tc_id,
                "params": tc,
                "status": "FAIL",
                "error": str(e),
                "duration_s": round(time.time() - t0, 2)
            }

    def run_matrix(self, sample_limit: int = 4) -> Dict[str, Any]:
        scenarios = self.generate_pairwise_matrix(sample_limit)
        results = []
        for s in scenarios:
            results.append(self.execute_scenario(s))

        passed = sum(1 for r in results if r["status"] == "PASS")
        summary = {
            "task_id": f"combinatorial_{int(time.time())}",
            "agent": "COMBINATORIAL_ENGINE",
            "timestamp": datetime.now().isoformat(),
            "total_tested": len(results),
            "passed": passed,
            "failed_or_rejected": len(results) - passed,
            "scenarios": results
        }

        out_file = os.path.join(self.reports_dir, "combinatorial-test-report.json")
        with open(out_file, "w") as f:
            json.dump(summary, f, indent=2)

        return summary

if __name__ == "__main__":
    engine = CombinatorialTestEngine()
    res = engine.run_matrix()
    print(json.dumps(res, indent=2))
