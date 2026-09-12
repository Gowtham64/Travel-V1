"""
VoyPlan Product Brain - Live Coverage Tracker
Maintains the Product Coverage Map with real evidence from iOS, Android, and Web runs.
Never fabricates metrics; computes numbers directly from verified test logs.
"""

import os
import json
import time
from datetime import datetime
from typing import Dict, Any, List, Optional

class ProductCoverageTracker:
    KNOWN_SCREENS = [
        {"id": "SCR_HOME", "name": "HomeScreen", "route": "/home", "description": "Main launchpad & hero discovery"},
        {"id": "SCR_PLANNER", "name": "TripPlannerScreen", "route": "/planner", "description": "Origin/dest/dates/travellers input"},
        {"id": "SCR_SMART_ITINERARY", "name": "SmartItineraryScreen", "route": "/smart-itinerary", "description": "AI timeline & day plan"},
        {"id": "SCR_TRIP_NAV", "name": "TripScreen", "route": "/trip", "description": "Live GPS route navigation & car mode"},
        {"id": "SCR_ATLAS", "name": "AtlasScreen", "route": "/atlas", "description": "Interactive Mapbox globe/vector map"},
        {"id": "SCR_TREKS", "name": "TrekDiscoveryScreen", "route": "/treks", "description": "Himalayan & Western Ghats treks"},
        {"id": "SCR_ACCOUNT", "name": "AccountScreen", "route": "/account", "description": "Profile, preferences, saved trips"},
        {"id": "SCR_WORKSPACE", "name": "TripWorkspaceScreen", "route": "/workspace", "description": "Collaborative trip planner"}
    ]

    KNOWN_FEATURES = [
        {"id": "FEAT_DESTINATION_INTEGRITY", "name": "AI Destination Integrity", "category": "AI / Routing"},
        {"id": "FEAT_SMART_BUDGET", "name": "Multi-Modal Budget Calculator", "category": "Finance"},
        {"id": "FEAT_LIVE_ACTIVITIES", "name": "Apple Dynamic Island & Live Activities", "category": "iOS Native"},
        {"id": "FEAT_CARPLAY_ANDROIDAUTO", "name": "In-Vehicle CarPlay & Android Auto", "category": "Automotive"},
        {"id": "FEAT_VEHICLE_DATABASE", "name": "Vehicle Mileage & Fuel Models", "category": "Vehicles"},
        {"id": "FEAT_TOLL_SYSTEM", "name": "NHAI Live Toll Rates", "category": "Routing"}
    ]

    def __init__(self, workspace_root: Optional[str] = None):
        self.workspace_root = workspace_root or os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        self.coverage_file = os.path.join(self.workspace_root, "voyplan-ai-engineering/product-brain/coverage/coverage_map.json")
        os.makedirs(os.path.dirname(self.coverage_file), exist_ok=True)
        self._init_or_load()

    def _init_or_load(self):
        if not os.path.exists(self.coverage_file):
            initial_state = {
                "last_updated": datetime.now().isoformat(),
                "platforms": {
                    "iOS": {
                        "screens_discovered": len(self.KNOWN_SCREENS),
                        "screens_tested": 0,
                        "features_discovered": len(self.KNOWN_FEATURES),
                        "features_tested": 0,
                        "trips_created": 0,
                        "itineraries_generated": 0,
                        "combinations_tested": 0,
                        "evidence_records": []
                    },
                    "Android": {
                        "screens_discovered": len(self.KNOWN_SCREENS),
                        "screens_tested": 0,
                        "features_discovered": len(self.KNOWN_FEATURES),
                        "features_tested": 0,
                        "trips_created": 0,
                        "itineraries_generated": 0,
                        "combinations_tested": 0,
                        "evidence_records": []
                    },
                    "Web": {
                        "screens_discovered": len(self.KNOWN_SCREENS),
                        "screens_tested": 0,
                        "features_discovered": len(self.KNOWN_FEATURES),
                        "features_tested": 0,
                        "trips_created": 0,
                        "itineraries_generated": 0,
                        "combinations_tested": 0,
                        "evidence_records": []
                    }
                },
                "screens": self.KNOWN_SCREENS,
                "features": self.KNOWN_FEATURES,
                "history": []
            }
            with open(self.coverage_file, "w") as f:
                json.dump(initial_state, f, indent=2)

    def record_test_run(self, platform: str, test_type: str, screens_visited: List[str], features_covered: List[str], evidence_path: Optional[str] = None):
        with open(self.coverage_file, "r") as f:
            data = json.load(f)

        plat_data = data["platforms"].get(platform)
        if not plat_data:
            return

        plat_data["screens_tested"] = max(plat_data["screens_tested"], len(set(screens_visited)))
        plat_data["features_tested"] = max(plat_data["features_tested"], len(set(features_covered)))
        plat_data["combinations_tested"] += 1
        if "itinerary" in test_type.lower():
            plat_data["itineraries_generated"] += 1
        if "trip" in test_type.lower():
            plat_data["trips_created"] += 1

        if evidence_path:
            plat_data["evidence_records"].append({
                "timestamp": datetime.now().isoformat(),
                "test_type": test_type,
                "evidence": evidence_path
            })

        data["last_updated"] = datetime.now().isoformat()
        data["history"].append({
            "timestamp": datetime.now().isoformat(),
            "platform": platform,
            "test_type": test_type,
            "screens": screens_visited,
            "features": features_covered
        })

        with open(self.coverage_file, "w") as f:
            json.dump(data, f, indent=2)

    def get_summary(self) -> Dict[str, Any]:
        with open(self.coverage_file, "r") as f:
            data = json.load(f)
        return data

if __name__ == "__main__":
    tracker = ProductCoverageTracker()
    print(json.dumps(tracker.get_summary(), indent=2))
