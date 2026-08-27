const {
  haversineDistanceKm,
  annotateCumulativeDistance,
  nearestRouteDistanceKm,
} = require("../utils/geo");

describe("haversineDistanceKm", () => {
  test("distance between identical points is 0", () => {
    const point = { lat: 12.9716, lng: 77.5946 };
    expect(haversineDistanceKm(point, point)).toBeCloseTo(0, 5);
  });

  test("Bengaluru to Chennai is approximately 290km", () => {
    const bengaluru = { lat: 12.9716, lng: 77.5946 };
    const chennai = { lat: 13.0827, lng: 80.2707 };
    const distance = haversineDistanceKm(bengaluru, chennai);
    // Straight-line distance, not driving distance - expect ~290km, allow a margin
    expect(distance).toBeGreaterThan(270);
    expect(distance).toBeLessThan(300);
  });
});

describe("annotateCumulativeDistance", () => {
  test("accumulates distance correctly across multiple points", () => {
    // Three points roughly 0.1 degree apart in latitude (~11.1km each at the equator-ish)
    const points = [
      { lat: 12.0, lng: 77.0 },
      { lat: 12.1, lng: 77.0 },
      { lat: 12.2, lng: 77.0 },
    ];
    const annotated = annotateCumulativeDistance(points);

    expect(annotated[0].cumulativeKm).toBe(0);
    expect(annotated[1].cumulativeKm).toBeGreaterThan(0);
    expect(annotated[2].cumulativeKm).toBeGreaterThan(annotated[1].cumulativeKm);
    // Total should roughly double from point 1 to point 2 since spacing is even
    expect(annotated[2].cumulativeKm).toBeCloseTo(annotated[1].cumulativeKm * 2, 0);
  });
});

describe("nearestRouteDistanceKm", () => {
  // Straight north-bound route, ~11.1km between vertices.
  const route = annotateCumulativeDistance(
    Array.from({ length: 6 }, (_, i) => ({ lat: 12.0 + i * 0.1, lng: 77.0 }))
  );

  test("projects a point between vertices to a mid-segment distance", () => {
    // Point at lat 12.05 (halfway between vertex 0 and 1), slightly east of the line.
    const res = nearestRouteDistanceKm(route, { lat: 12.05, lng: 77.01 });
    // Halfway along the first ~11.1km segment.
    expect(res.distanceFromStartKm).toBeGreaterThan(4);
    expect(res.distanceFromStartKm).toBeLessThan(7);
    expect(res.offRouteKm).toBeGreaterThan(0);
    expect(res.offRouteKm).toBeLessThan(2);
  });

  test("a point on the route has ~0 off-route distance", () => {
    const res = nearestRouteDistanceKm(route, { lat: 12.2, lng: 77.0 });
    expect(res.offRouteKm).toBeCloseTo(0, 1);
    expect(res.distanceFromStartKm).toBeCloseTo(route[2].cumulativeKm, 0);
  });

  test("segment projection beats vertex snapping between far-apart vertices", () => {
    // Two vertices 100km apart; a point near the midpoint must project to ~50km,
    // which nearest-vertex snapping (0 or 100) could never return.
    const coarse = annotateCumulativeDistance([
      { lat: 12.0, lng: 77.0 },
      { lat: 12.9, lng: 77.0 },
    ]);
    const res = nearestRouteDistanceKm(coarse, { lat: 12.45, lng: 77.0 });
    expect(res.distanceFromStartKm).toBeGreaterThan(40);
    expect(res.distanceFromStartKm).toBeLessThan(60);
  });
});
