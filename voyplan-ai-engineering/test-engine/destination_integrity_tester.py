"""
VoyPlan Destination Integrity & Adversarial AI Tester
Continuously validates that itinerary generation is locked to the target destination
and isolates root causes across geocoding, POI search, candidate filtering, and AI generation.
"""

import os
import sys
import json
import time
import math
import requests
from datetime import datetime
from typing import Dict, Any, List, Optional

class DestinationIntegrityTester:
    DEFAULT_BACKEND = "https://travel-v1-mzia.onrender.com"

    HIGH_RISK_TEST_PAIRS = [
        {
            "origin": "Bengaluru",
            "destination": "Tirumala",
            "categories": ["Temples", "Culture"],
            "expected_lat": 13.68,
            "expected_lng": 79.35,
            "max_radius_km": 45,
            "forbidden_keywords": ["bengaluru", "bangalore", "mysuru", "chennai", "hyderabad", "coorg", "ooty"]
        },
        {
            "origin": "Bengaluru",
            "destination": "Tirupati",
            "categories": ["Temples", "Nature"],
            "expected_lat": 13.63,
            "expected_lng": 79.42,
            "max_radius_km": 50,
            "forbidden_keywords": ["bengaluru", "bangalore", "cubbon", "lalbagh", "mysore palace"]
        },
        {
            "origin": "Chennai",
            "destination": "Pondicherry",
            "categories": ["Beach", "Heritage"],
            "expected_lat": 11.94,
            "expected_lng": 79.80,
            "max_radius_km": 35,
            "forbidden_keywords": ["chennai", "marina beach", "mahabalipuram", "bengaluru"]
        }
    ]

    def __init__(self, backend_url: Optional[str] = None, workspace_root: Optional[str] = None):
        self.backend_url = (backend_url or os.environ.get("BACKEND_URL") or self.DEFAULT_BACKEND).rstrip("/")
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        self.reports_dir = os.path.join(self.workspace_root, "voyplan-ai-engineering/reports")
        os.makedirs(self.reports_dir, exist_ok=True)

    @staticmethod
    def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        R = 6371.0
        dlat = math.radians(lat2 - lat1)
        dlon = math.radians(lon2 - lon1)
        a = math.sin(dlat / 2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return R * c

    def test_pair(self, test_case: Dict[str, Any]) -> Dict[str, Any]:
        origin = test_case["origin"]
        dest = test_case["destination"]
        categories = test_case.get("categories", ["Temples"])
        max_radius = test_case.get("max_radius_km", 45)
        forbidden = test_case.get("forbidden_keywords", [])
        expected_lat = test_case.get("expected_lat")
        expected_lng = test_case.get("expected_lng")

        print(f"\n[INTEGRITY TESTER] 🎯 Testing Destination Integrity: {origin} ➔ {dest}...")
        t0 = time.time()

        # Step 1: Call Smart Itinerary Endpoint
        url = f"{self.backend_url}/api/ai/smart-itinerary"
        payload = {
            "startLocation": origin,
            "destination": dest,
            "durationDays": 1,
            "selectedCategories": categories
        }

        try:
            res = requests.post(url, json=payload, timeout=60)
            status_code = res.status_code
            data = res.json() if res.ok else {}
        except Exception as e:
            return {
                "pair": f"{origin} ➔ {dest}",
                "status": "FAIL",
                "layer_failure": "NETWORK_API",
                "reason": f"Connection error: {str(e)}",
                "confidence": "HIGH"
            }

        duration = round(time.time() - t0, 2)
        if status_code != 200:
            return {
                "pair": f"{origin} ➔ {dest}",
                "status": "FAIL",
                "status_code": status_code,
                "layer_failure": "BACKEND_SERVICE",
                "reason": data.get("error", "Non-200 HTTP response"),
                "duration_s": duration
            }

        # Step 2: Layered Inspection of Stops
        days = data.get("days", [])
        if not days:
            return {
                "pair": f"{origin} ➔ {dest}",
                "status": "FAIL",
                "layer_failure": "ITINERARY_STRUCTURE",
                "reason": "Backend returned 0 days in itinerary.",
                "duration_s": duration
            }

        inspected_stops = []
        violations = []
        dest_centroid = data.get("destinationCoordinates") or {}
        dest_lat = dest_centroid.get("lat") or expected_lat
        dest_lng = dest_centroid.get("lng") or expected_lng

        for day_idx, day in enumerate(days):
            for block in day.get("blocks", []):
                title = block.get("title", "")
                place_name = block.get("place", "")
                full_text = f"{title} {place_name}".lower()
                lat = block.get("lat")
                lng = block.get("lng")

                # Skip origin departure / return blocks from destination-only checks
                is_origin_leg = (
                    "start from" in full_text or 
                    "return to" in full_text or 
                    "head back" in full_text or
                    "drive to destination" in full_text
                )
                if is_origin_leg:
                    inspected_stops.append({
                        "title": title,
                        "lat": lat,
                        "lng": lng,
                        "type": "transit_leg"
                    })
                    continue

                # Keyword violation check
                for word in forbidden:
                    if word in full_text:
                        violations.append({
                            "type": "FORBIDDEN_KEYWORD",
                            "stop": title,
                            "keyword": word,
                            "day": day_idx + 1
                        })

                # Geographic distance violation check
                dist_km = None
                if lat and lng and dest_lat and dest_lng:
                    dist_km = round(self.haversine_km(dest_lat, dest_lng, lat, lng), 1)
                    if dist_km > max_radius:
                        violations.append({
                            "type": "EXCESSIVE_DISTANCE",
                            "stop": title,
                            "distance_km": dist_km,
                            "max_allowed_km": max_radius,
                            "day": day_idx + 1
                        })

                inspected_stops.append({
                    "title": title,
                    "lat": lat,
                    "lng": lng,
                    "dist_from_dest_km": dist_km
                })

        is_valid = len(violations) == 0
        status = "PASS" if is_valid else "FAIL"

        layer_failure = None
        if not is_valid:
            # Determine earliest failed layer
            has_geo_outlier = any(v["type"] == "EXCESSIVE_DISTANCE" for v in violations)
            has_name_outlier = any(v["type"] == "FORBIDDEN_KEYWORD" for v in violations)
            if has_name_outlier:
                layer_failure = "GEMINI_OR_POI_CANDIDATE_FILTER"
            elif has_geo_outlier:
                layer_failure = "GEO_VALIDATION_RADIUS"

        print(f"[INTEGRITY TESTER] {'✅ PASS' if is_valid else '❌ FAIL'}: {len(inspected_stops)} stops evaluated, {len(violations)} violations.")

        return {
            "pair": f"{origin} ➔ {dest}",
            "status": status,
            "duration_s": duration,
            "stops_count": len(inspected_stops),
            "violations": violations,
            "layer_failure": layer_failure,
            "stops": inspected_stops
        }

    def run_suite(self) -> Dict[str, Any]:
        print("\n=======================================================")
        print(f" [DESTINATION INTEGRITY AUDITOR] Running High-Risk Test Matrix")
        print(f" Target Backend: {self.backend_url}")
        print("=======================================================")

        results = []
        all_passed = True

        for case in self.HIGH_RISK_TEST_PAIRS:
            res = self.test_pair(case)
            results.append(res)
            if res["status"] != "PASS":
                all_passed = False

        summary = {
            "task_id": f"integrity_audit_{int(time.time())}",
            "agent": "DESTINATION_INTEGRITY_AUDITOR",
            "timestamp": datetime.now().isoformat(),
            "overall_status": "PASS" if all_passed else "FAIL",
            "backend_url": self.backend_url,
            "tests_run": len(results),
            "tests_passed": sum(1 for r in results if r["status"] == "PASS"),
            "results": results
        }

        out_file = os.path.join(self.reports_dir, "destination-integrity-report.json")
        with open(out_file, "w") as f:
            json.dump(summary, f, indent=2)

        print(f"\n[DESTINATION INTEGRITY AUDITOR] Suite Complete: {'✅ ALL PASSED' if all_passed else '❌ DEFECTS DETECTED'}")
        print(f" Report saved to: {out_file}\n")
        return summary

if __name__ == "__main__":
    tester = DestinationIntegrityTester()
    res = tester.run_suite()
    print(json.dumps(res, indent=2))
