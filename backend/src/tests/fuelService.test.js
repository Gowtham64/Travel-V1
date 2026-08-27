const {
  calculateRangeKm,
  findRefuelStops,
  planStationRefuelStops,
  estimateTripDays,
} = require("../services/fuelService");

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

describe("planStationRefuelStops", () => {
  // ~655km straight line heading north (60 points ~11.1km apart).
  const longRoute = Array.from({ length: 60 }, (_, i) => ({
    lat: 12.0 + i * 0.1,
    lng: 77.0,
  }));
  // A pump sitting right on the route roughly every ~55km.
  const stations = Array.from({ length: 12 }, (_, i) => ({
    id: i + 1,
    name: `Pump ${i + 1}`,
    lat: 12.0 + i * 0.5,
    lng: 77.0,
  }));

  test("no refuel needed when current fuel covers the whole trip", () => {
    const result = planStationRefuelStops(longRoute, stations, 50, 50, 20); // ~850km buffered range
    expect(result.needsRefuel).toBe(false);
    expect(result.refuelStops).toHaveLength(0);
    expect(result.unreachable).toBe(false);
  });

  test("snaps each refuel stop to a named real station within reach", () => {
    // 5L * 15km/l = 75km real range; buffered ~64km before the first top-up.
    const result = planStationRefuelStops(longRoute, stations, 5, 40, 15);
    expect(result.needsRefuel).toBe(true);
    expect(result.refuelStops.length).toBeGreaterThan(0);
    for (const stop of result.refuelStops) {
      expect(stop.name).toMatch(/^Pump /); // real station, not a bare geometric marker
      expect(stop.stationId).toBeGreaterThan(0);
      expect(stop.fuelOnArrivalLiters).toBeGreaterThanOrEqual(0);
    }
  });

  test("never plans a stop beyond the vehicle's buffered range", () => {
    const result = planStationRefuelStops(longRoute, stations, 5, 40, 15);
    const fullBufferedRangeKm = 40 * 15 * 0.85;
    let prev = 0;
    for (const stop of result.refuelStops) {
      expect(stop.distanceFromStartKm - prev).toBeLessThanOrEqual(fullBufferedRangeKm + 0.01);
      prev = stop.distanceFromStartKm;
    }
  });

  test("stops are ordered by distance from start", () => {
    const result = planStationRefuelStops(longRoute, stations, 5, 30, 15);
    const distances = result.refuelStops.map((s) => s.distanceFromStartKm);
    expect(distances).toEqual([...distances].sort((a, b) => a - b));
  });

  test("flags unreachable when no station sits within the first leg's range", () => {
    // Only pumps far past the buffered start range (~64km) exist.
    const farStations = [
      { id: 99, name: "Far Pump", lat: 17.0, lng: 77.0 }, // ~555km in
    ];
    const result = planStationRefuelStops(longRoute, farStations, 5, 40, 15);
    expect(result.unreachable).toBe(true);
    expect(result.refuelStops).toHaveLength(0);
  });
});
