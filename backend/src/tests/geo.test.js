const { haversineDistanceKm, annotateCumulativeDistance } = require("../utils/geo");

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
