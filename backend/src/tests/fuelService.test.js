const { calculateRangeKm, findRefuelStops, estimateTripDays } = require("../services/fuelService");

describe("calculateRangeKm", () => {
  test("computes range as fuel x efficiency", () => {
    expect(calculateRangeKm(40, 15)).toBe(600);
  });

  test("throws on invalid efficiency", () => {
    expect(() => calculateRangeKm(40, 0)).toThrow();
  });
});

describe("estimateTripDays", () => {
  test("a 6 hour drive at 7 hours/day takes 1 day", () => {
    expect(estimateTripDays(6 * 60, 7)).toBe(1);
  });

  test("a 15 hour drive at 7 hours/day takes 3 days", () => {
    expect(estimateTripDays(15 * 60, 7)).toBe(3);
  });

  test("adding sightseeing hours can push the trip to an extra day", () => {
    const withoutStops = estimateTripDays(14 * 60, 7, 0);
    const withStops = estimateTripDays(14 * 60, 7, 4);
    expect(withStops).toBeGreaterThan(withoutStops);
  });
});

describe("findRefuelStops", () => {
  // A straight line of points heading north, ~11.1km apart in latitude
  const longRoute = Array.from({ length: 60 }, (_, i) => ({
    lat: 12.0 + i * 0.1,
    lng: 77.0,
  }));

  test("no refuel needed when current fuel covers the whole trip", () => {
    const result = findRefuelStops(longRoute, 50, 50, 20); // range = 50*20*0.8 = 800km, route is ~655km
    expect(result.needsRefuel).toBe(false);
    expect(result.refuelStops).toHaveLength(0);
  });

  test("flags a refuel stop when current fuel runs out mid-route", () => {
    // current fuel range = 5L * 15km/l * 0.8 = 60km -> will need to refuel almost immediately
    const result = findRefuelStops(longRoute, 5, 40, 15);
    expect(result.needsRefuel).toBe(true);
    expect(result.refuelStops.length).toBeGreaterThan(0);
    // first stop should be reasonably close to the 60km mark
    expect(result.refuelStops[0].distanceFromStartKm).toBeGreaterThan(40);
    expect(result.refuelStops[0].distanceFromStartKm).toBeLessThan(80);
  });

  test("refuel stops are in increasing order of distance from start", () => {
    const result = findRefuelStops(longRoute, 5, 30, 15);
    const distances = result.refuelStops.map((s) => s.distanceFromStartKm);
    const sorted = [...distances].sort((a, b) => a - b);
    expect(distances).toEqual(sorted);
  });

  test("throws if route has fewer than 2 points", () => {
    expect(() => findRefuelStops([{ lat: 12, lng: 77 }], 10, 40, 15)).toThrow();
  });
});
