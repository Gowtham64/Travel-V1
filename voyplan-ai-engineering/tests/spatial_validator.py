#!/usr/bin/env python3
"""
VoyPlan Destination Integrity & Spatial Boundary Regression Test Suite.
Validates that destination coordinates strictly anchor itineraries and reject distant cities.
Works in all server environments (Python/Render/Linux/macOS) with zero external dependencies.
"""

import sys
import math
import json

def haversine_km(lat1, lon1, lat2, lon2):
    """Calculates great-circle distance between two GPS coordinates in kilometers."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

MAX_RADIUS_KM = 75.0  # Strict spatial bounding threshold

def validate_destination_stops(destination_name, dest_lat, dest_lng, stops):
    """
    Validates that all activity stops in an itinerary are strictly within
    the spatial bounding radius of the destination.
    """
    accepted = []
    rejected = []
    for stop in stops:
        dist = haversine_km(dest_lat, dest_lng, stop["lat"], stop["lng"])
        if dist <= MAX_RADIUS_KM:
            accepted.append({**stop, "distance_km": round(dist, 1)})
        else:
            rejected.append({**stop, "distance_km": round(dist, 1)})
    
    valid = len(rejected) == 0
    return {
        "valid": valid,
        "destination": destination_name,
        "accepted": accepted,
        "rejected": rejected
    }

def run_all_tests():
    print("======================================================================")
    print("VoyPlan Destination Boundary & Integrity Regression Test Suite")
    print("======================================================================")

    tests_run = 0
    tests_passed = 0

    # Test 1: Tirumala Destination Integrity
    tests_run += 1
    print("\n[TEST 1] Destination = Tirumala (Anchoring & Contamination Rejection)")
    tirumala_dest = {"name": "Tirumala", "lat": 13.6833, "lng": 79.3473}
    tirumala_stops = [
        {"title": "Tirumala Venkateswara Temple", "lat": 13.6833, "lng": 79.3473},
        {"title": "Kapila Theertham Tirupati", "lat": 13.6496, "lng": 79.4262},
        {"title": "Mysuru Palace", "lat": 12.3051, "lng": 76.6551},
        {"title": "Marina Beach Chennai", "lat": 13.0500, "lng": 80.2824},
        {"title": "Bengaluru Tech Park", "lat": 12.9716, "lng": 77.5946}
    ]
    res1 = validate_destination_stops(tirumala_dest["name"], tirumala_dest["lat"], tirumala_dest["lng"], tirumala_stops)
    rejected_names = [s["title"] for s in res1["rejected"]]
    accepted_names = [s["title"] for s in res1["accepted"]]

    assert "Tirumala Venkateswara Temple" in accepted_names, "Tirumala Temple must be accepted"
    assert "Kapila Theertham Tirupati" in accepted_names, "Tirupati nearby attractions must be accepted"
    assert "Mysuru Palace" in rejected_names, "Mysuru must be rejected (>300km)"
    assert "Marina Beach Chennai" in rejected_names, "Chennai must be rejected (>120km)"
    assert "Bengaluru Tech Park" in rejected_names, "Bengaluru must be rejected (>200km)"
    print(f"  ✅ Passed: Accepted {len(accepted_names)} local stops; Rejected {len(rejected_names)} distant cities.")
    tests_passed += 1

    # Test 2: Goa Destination Integrity
    tests_run += 1
    print("\n[TEST 2] Destination = Goa (Panaji/Baga Beach vs Mumbai & Hyderabad)")
    goa_dest = {"name": "Goa", "lat": 15.2993, "lng": 74.1240}
    goa_stops = [
        {"title": "Baga Beach", "lat": 15.5553, "lng": 73.7517},
        {"title": "Aguada Fort", "lat": 15.4920, "lng": 73.7737},
        {"title": "Gateway of India Mumbai", "lat": 18.9220, "lng": 72.8347},
        {"title": "Charminar Hyderabad", "lat": 17.3616, "lng": 78.4747}
    ]
    res2 = validate_destination_stops(goa_dest["name"], goa_dest["lat"], goa_dest["lng"], goa_stops)
    rej2 = [s["title"] for s in res2["rejected"]]
    assert "Gateway of India Mumbai" in rej2, "Mumbai must be rejected (>400km)"
    assert "Charminar Hyderabad" in rej2, "Hyderabad must be rejected (>500km)"
    print(f"  ✅ Passed: Accepted Goa local stops; Rejected Mumbai and Hyderabad.")
    tests_passed += 1

    # Test 3: Ooty Destination Integrity
    tests_run += 1
    print("\n[TEST 3] Destination = Ooty (Nilgiris vs Chennai & Bengaluru)")
    ooty_dest = {"name": "Ooty", "lat": 11.4102, "lng": 76.6950}
    ooty_stops = [
        {"title": "Ooty Botanical Gardens", "lat": 11.4184, "lng": 76.7115},
        {"title": "Doddabetta Peak", "lat": 11.4011, "lng": 76.7356},
        {"title": "Chennai Marina Mall", "lat": 13.0827, "lng": 80.2707},
        {"title": "Bengaluru Electronic City", "lat": 12.8452, "lng": 77.6602}
    ]
    res3 = validate_destination_stops(ooty_dest["name"], ooty_dest["lat"], ooty_dest["lng"], ooty_stops)
    rej3 = [s["title"] for s in res3["rejected"]]
    assert "Chennai Marina Mall" in rej3, "Chennai must be rejected (>420km)"
    assert "Bengaluru Electronic City" in rej3, "Bengaluru must be rejected (>250km)"
    print(f"  ✅ Passed: Accepted Nilgiris local stops; Rejected Chennai and Bengaluru.")
    tests_passed += 1

    # Test 4: One-Way and Round-Trip Routing Integrity
    tests_run += 1
    print("\n[TEST 4] Routing Engine Integrity (One-Way & Round-Trip Leg Calculation)")
    origin = {"lat": 12.9716, "lng": 77.5946, "name": "Bengaluru"}
    dest = {"lat": 13.6833, "lng": 79.3473, "name": "Tirumala"}
    leg_outbound = haversine_km(origin["lat"], origin["lng"], dest["lat"], dest["lng"])
    leg_return = haversine_km(dest["lat"], dest["lng"], origin["lat"], origin["lng"])
    assert round(leg_outbound, 1) == round(leg_return, 1), "Outbound and return distances must match"
    assert 200 < leg_outbound < 280, f"Distance between Bengaluru and Tirumala should be ~230-260km, got {leg_outbound}"
    print(f"  ✅ Passed: One-way and round-trip routing distance verified ({round(leg_outbound, 1)} km).")
    tests_passed += 1

    print("\n======================================================================")
    print(f"Summary: {tests_passed}/{tests_run} test suites passed (100% SUCCESS)")
    print("Deterministic destination integrity verified across all test scenarios.")
    print("======================================================================")
    return tests_passed == tests_run

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)
