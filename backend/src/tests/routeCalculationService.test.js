const { calculateTripRoute, normalizeLocation } = require("../services/routeCalculationService");

describe("routeCalculationService", () => {
  const bengaluru = { lat: 12.9716, lng: 77.5946, name: "Bengaluru" };
  const tirumala = { lat: 13.6833, lng: 79.3473, name: "Tirumala" };
  const temple = { lat: 13.6833, lng: 79.3473, name: "Lord Venkateswara Temple", type: "activity" };
  const museum = { lat: 13.6822, lng: 79.3496, name: "Srivari Museum", type: "activity" };

  test("normalizes location correctly", () => {
    const loc = normalizeLocation(bengaluru, "Bengaluru", "origin", 0);
    expect(loc).toBeDefined();
    expect(loc.latitude).toBe(12.9716);
    expect(loc.longitude).toBe(77.5946);
    expect(loc.name).toBe("Bengaluru");
    expect(loc.placeId).toBeDefined();
  });

  test("computes authoritative route and budget for Bengaluru -> Tirumala around-trip", async () => {
    const res = await calculateTripRoute({
      origin: bengaluru,
      destination: tirumala,
      stops: [temple, museum],
      vehicle: { type: "car", efficiencyKmPerLiter: 15 },
      tripType: "around",
      durationDays: 2,
      travellers: 2,
      routeVersion: 1,
    });

    expect(res).toBeDefined();
    expect(res.route).toBeDefined();
    expect(res.route.distanceKm).toBeGreaterThan(100);
    expect(res.route.distanceMeters).toBeGreaterThan(100000);
    expect(res.route.durationSeconds).toBeGreaterThan(3600);
    expect(res.route.coordinates.length).toBeGreaterThan(10);
    expect(res.budget).toBeDefined();
    expect(res.budget.fuel).toBeGreaterThan(0);
    expect(res.budget.total).toBeGreaterThan(res.budget.fuel);
    expect(res.navigationRoute).toBeDefined();
    expect(res.navigationRoute.waypoints.length).toBeGreaterThanOrEqual(1);
    expect(res.routeVersion).toBe(1);
  }, 25000);
});
