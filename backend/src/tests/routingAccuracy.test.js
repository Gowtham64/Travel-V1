const {
  validateRouteStartEnd,
  buildCanonicalRouteResult,
  haversineMeters,
  haversineKm,
} = require("../services/routingService");

describe("Routing Accuracy & Canonical RouteResult Tests", () => {
  const start = { lat: 12.9716, lng: 77.5946, name: "Bengaluru" };
  const stopA = { lat: 12.2958, lng: 76.6394, name: "Mysuru" };
  const stopB = { lat: 11.4102, lng: 76.6950, name: "Ooty" };
  const end = { lat: 11.0168, lng: 76.9558, name: "Coimbatore" };

  describe("Haversine calculations", () => {
    it("calculates accurate distance between Bengaluru and Mysuru (~128-140 km crow-flies)", () => {
      const distKm = haversineKm(start, stopA);
      expect(distKm).toBeGreaterThan(120);
      expect(distKm).toBeLessThan(145);
    });

    it("returns 0 for identical points", () => {
      expect(haversineMeters(start, start)).toBe(0);
    });
  });

  describe("validateRouteStartEnd", () => {
    it("validates a route starting and ending near requested points", () => {
      const coords = [
        { lat: 12.9718, lng: 77.5948 }, // ~30m from start
        { lat: 12.5000, lng: 77.0000 },
        { lat: 11.0170, lng: 76.9560 }, // ~30m from end
      ];
      const res = validateRouteStartEnd(start, end, coords, 2500);
      expect(res.valid).toBe(true);
      expect(res.startDelta).toBeLessThan(100);
      expect(res.endDelta).toBeLessThan(100);
    });

    it("rejects a route starting far (> 2500m) from requested origin", () => {
      const coords = [
        { lat: 13.0500, lng: 77.6500 }, // ~10 km away
        { lat: 11.0168, lng: 76.9558 },
      ];
      const res = validateRouteStartEnd(start, end, coords, 2500);
      expect(res.valid).toBe(false);
      expect(res.startDelta).toBeGreaterThan(2500);
    });

    it("rejects an Around Trip if the final coordinate does not return to origin", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 12.2958, lng: 76.6394 }, // stops at Mysuru without returning
      ];
      const res = validateRouteStartEnd(start, start, coords, 2500);
      expect(res.valid).toBe(false);
      expect(res.reason).toContain("Around Trip did not return to origin");
    });

    it("accepts an Around Trip that completes full circle back to start", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 12.2958, lng: 76.6394 },
        { lat: 12.9717, lng: 77.5947 }, // returned to start (~15m)
      ];
      const res = validateRouteStartEnd(start, start, coords, 2500);
      expect(res.valid).toBe(true);
    });
  });

  describe("buildCanonicalRouteResult", () => {
    it("constructs full canonical object with authoritative meters, geometry, legs", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 12.2958, lng: 76.6394 },
      ];
      const legs = [
        {
          legIndex: 0,
          distanceMeters: 145200,
          durationSeconds: 10800,
          steps: [
            {
              instruction: "Turn right onto NH275",
              distanceMeters: 145200,
              durationSeconds: 10800,
              roadName: "NH275",
              maneuverType: "turn",
            },
          ],
        },
      ];

      const result = buildCanonicalRouteResult({
        origin: start,
        destination: stopA,
        waypoints: [],
        coordinates: coords,
        distanceMeters: 145200,
        durationSeconds: 10800,
        legs,
        steps: legs[0].steps,
        maneuvers: ["Turn right onto NH275"],
        avoidedMotorways: false,
        provider: "Mapbox",
      });

      expect(result.distanceMeters).toBe(145200);
      expect(result.distanceKm).toBe(145.2);
      expect(result.durationSeconds).toBe(10800);
      expect(result.durationMin).toBe(180);
      expect(result.geometry.type).toBe("LineString");
      expect(result.geometry.coordinates).toHaveLength(2);
      expect(result.geometry.coordinates[0]).toEqual([77.5946, 12.9716]);
      expect(result.legs).toHaveLength(1);
      expect(result.steps).toHaveLength(1);
      expect(result.maneuvers).toEqual(["Turn right onto NH275"]);
    });

    it("falls back to haversine sum if engine returns 0 distance with valid coordinates", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 12.2958, lng: 76.6394 },
      ];
      const result = buildCanonicalRouteResult({
        origin: start,
        destination: stopA,
        coordinates: coords,
        distanceMeters: 0,
        durationSeconds: 0,
        provider: "Fallback",
      });
      expect(result.distanceMeters).toBeGreaterThan(120000);
      expect(result.distanceKm).toBeGreaterThan(120);
      expect(result.durationSeconds).toBeGreaterThan(0);
    });
  });

  describe("validateRoute (end-to-end validator)", () => {
    const { validateRoute } = require("../services/routingService");

    it("verifies a valid route visiting waypoints in correct sequence", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 }, // Bengaluru
        { lat: 12.2958, lng: 76.6394 }, // Mysuru (Stop A)
        { lat: 11.4102, lng: 76.6950 }, // Ooty (Stop B)
        { lat: 11.0168, lng: 76.9558 }, // Coimbatore (End)
      ];
      const routeResult = {
        coordinates: coords,
        distanceMeters: 350000,
        distanceKm: 350,
        legs: [
          { legIndex: 0, distanceMeters: 140000 },
          { legIndex: 1, distanceMeters: 120000 },
          { legIndex: 2, distanceMeters: 90000 },
        ],
      };
      const res = validateRoute(start, end, [stopA, stopB], routeResult, 5000);
      expect(res.valid).toBe(true);
      expect(res.reason).toBe("OK");
    });

    it("rejects route when waypoint sequence is inverted", () => {
      // Route visits Ooty before Mysuru!
      const coords = [
        { lat: 12.9716, lng: 77.5946 }, // Bengaluru
        { lat: 11.4102, lng: 76.6950 }, // Ooty (Stop B) visited first
        { lat: 12.2958, lng: 76.6394 }, // Mysuru (Stop A) visited second
        { lat: 11.0168, lng: 76.9558 }, // Coimbatore
      ];
      const routeResult = {
        coordinates: coords,
        distanceMeters: 380000,
        distanceKm: 380,
      };
      const res = validateRoute(start, end, [stopA, stopB], routeResult, 5000);
      expect(res.valid).toBe(false);
      expect(res.reason).toContain("Waypoint sequence inverted");
    });

    it("normalizes route distance to sum of legs if discrepancy exceeds threshold", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 12.2958, lng: 76.6394 },
      ];
      const routeResult = {
        coordinates: coords,
        distanceMeters: 100000, // Inconsistent distance
        distanceKm: 100,
        legs: [
          { legIndex: 0, distanceMeters: 145000 },
        ],
      };
      const res = validateRoute(start, stopA, [], routeResult, 5000);
      expect(res.valid).toBe(true);
      expect(routeResult.distanceMeters).toBe(145000);
      expect(routeResult.distanceKm).toBe(145);
    });
  });

  describe("buildItinerary scaling with authoritative distance", () => {
    const { buildItinerary } = require("../services/itineraryService");

    it("ensures total itinerary days sum up exactly to authoritative totalRouteDistanceKm", () => {
      const coords = [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 15.0000, lng: 77.0000 },
        { lat: 18.0000, lng: 76.0000 },
        { lat: 21.0000, lng: 75.0000 },
        { lat: 24.0000, lng: 74.0000 },
      ];
      // Multi-day trip (e.g. 20 hours of driving = 3 days at 7h/day)
      const durationMin = 1200; // 20 hours
      const authoritativeDistKm = 1450.5;

      const itinerary = buildItinerary(coords, durationMin, 7, authoritativeDistKm);
      expect(itinerary.length).toBeGreaterThan(1);

      // The final day toKm must match the authoritative distance
      const finalDay = itinerary[itinerary.length - 1];
      expect(finalDay.isFinal).toBe(true);
      expect(finalDay.toKm).toBe(1450.5);

      // Sum of distanceKm across all days must equal authoritative distance
      const sumKm = itinerary.reduce((acc, d) => acc + d.distanceKm, 0);
      expect(Math.abs(sumKm - authoritativeDistKm)).toBeLessThan(0.2);
    });
  });
});
