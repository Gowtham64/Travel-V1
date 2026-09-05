const { FuelRangeService } = require('../services/fuelRangeService');

describe('FuelRangeService Smart Refuelling Tests', () => {
  // Test Route: Bengaluru -> Mysuru -> Ooty (~300 km)
  const sampleRoute = [
    { lat: 12.9716, lng: 77.5946 }, // Bengaluru (0 km)
    { lat: 12.7200, lng: 77.2800 }, // Ramanagara (~50 km)
    { lat: 12.5200, lng: 76.9000 }, // Mandya (~100 km)
    { lat: 12.2958, lng: 76.6394 }, // Mysuru (~150 km)
    { lat: 11.9000, lng: 76.6000 }, // Nanjangud (~180 km)
    { lat: 11.6600, lng: 76.6000 }, // Gundlupet (~220 km)
    { lat: 11.4102, lng: 76.6950 }, // Ooty (~280 km)
  ];

  const sampleStations = [
    { id: 1, name: 'HP Petrol Pump Ramanagara', lat: 12.7200, lng: 77.2800 },
    { id: 2, name: 'IndianOil Mandya', lat: 12.5200, lng: 76.9000 },
    { id: 3, name: 'Shell Mysuru Highway', lat: 12.3500, lng: 76.6600 },
    { id: 4, name: 'Bharat Petroleum Gundlupet', lat: 11.6600, lng: 76.6000 },
  ];

  test('TEST 1: One Way Trip with enough fuel requires NO refuel stops', () => {
    // Current fuel: 20 L, Mileage: 15 km/L -> Theoretical: 300 km, Safe: ~264 km. Distance: ~200 km
    const shortRoute = sampleRoute.slice(0, 4); // ~150 km
    const result = FuelRangeService.planSmartRefuelStops({
      routeCoordinates: shortRoute,
      vehicle: {
        currentFuelLiters: 20,
        tankCapacityLiters: 50,
        efficiencyKmPerLiter: 15,
        fuelType: 'petrol',
      },
    });

    expect(result.needsRefuel).toBe(false);
    expect(result.refuelStops.length).toBe(0);
    expect(result.unreachable).toBe(false);
  });

  test('TEST 2: One Way Trip with low fuel inserts fuel station BEFORE safe limit', () => {
    // Current fuel: 6 L, Mileage: 15 km/L -> Theoretical: 90 km, Safe range: ~60 km
    // Route is ~280 km -> must stop around Ramanagara/Mandya
    const result = FuelRangeService.planSmartRefuelStops({
      routeCoordinates: sampleRoute,
      stations: sampleStations,
      vehicle: {
        currentFuelLiters: 6,
        tankCapacityLiters: 45,
        efficiencyKmPerLiter: 15,
        fuelType: 'petrol',
      },
    });

    expect(result.needsRefuel).toBe(true);
    expect(result.refuelStops.length).toBeGreaterThanOrEqual(1);
    expect(result.refuelStops[0].distanceFromStartKm).toBeLessThanOrEqual(80);
    expect(result.refuelStops[0].refillLiters).toBeGreaterThan(0);
    expect(result.refuelStops[0].estimatedCost).toBeGreaterThan(0);
    expect(result.refuelStops[0].fuelType).toBe('petrol');
  });

  test('TEST 3: Long Trip dynamically generates multiple refuel stops', () => {
    // 600 km synthetic route with 14 L tank capacity and 10 km/L efficiency -> Safe range ~110 km
    const longRoute = [];
    for (let i = 0; i <= 60; i++) {
      longRoute.push({ lat: 12.0 + i * 0.1, lng: 77.0 });
    }

    const result = FuelRangeService.planSmartRefuelStops({
      routeCoordinates: longRoute,
      vehicle: {
        currentFuelLiters: 14,
        tankCapacityLiters: 14,
        efficiencyKmPerLiter: 10,
        fuelType: 'petrol',
      },
    });

    expect(result.needsRefuel).toBe(true);
    expect(result.refuelStops.length).toBeGreaterThanOrEqual(3);
    for (let i = 0; i < result.refuelStops.length; i++) {
      expect(result.refuelStops[i].refillLiters).toBeGreaterThan(0);
      expect(result.refuelStops[i].isSystemGenerated).toBe(true);
    }
  });

  test('TEST 4: Around Trip with stops identifies correct leg for insertion', () => {
    // Route: Bengaluru -> Mandya -> Mysuru -> Bengaluru (Circuit)
    const circuitRoute = [
      { lat: 12.9716, lng: 77.5946 }, // Start: Bengaluru
      { lat: 12.5200, lng: 76.9000 }, // Stop 1: Mandya (Temple)
      { lat: 12.2958, lng: 76.6394 }, // Stop 2: Mysuru (Palace)
      { lat: 12.5200, lng: 76.9000 }, // Return pass Mandya
      { lat: 12.9716, lng: 77.5946 }, // Return to Bengaluru
    ];

    const userStops = [
      { name: 'Mandya Temple', lat: 12.5200, lng: 76.9000 },
      { name: 'Mysuru Palace', lat: 12.2958, lng: 76.6394 },
    ];

    const result = FuelRangeService.planSmartRefuelStops({
      routeCoordinates: circuitRoute,
      userStops,
      stations: sampleStations,
      vehicle: {
        currentFuelLiters: 8, // ~120 km range
        tankCapacityLiters: 50,
        efficiencyKmPerLiter: 15,
        fuelType: 'diesel',
      },
    });

    expect(result.needsRefuel).toBe(true);
    expect(result.refuelStops.length).toBeGreaterThanOrEqual(1);
    expect(result.refuelStops[0].fuelType).toBe('diesel');
    expect(result.refuelStops[0].legIndex).toBeDefined();
  });

  test('TEST 5: Calculation of theoretical and safe range with reserve buffer', () => {
    const theo = FuelRangeService.calculateTheoreticalRange(14, 15);
    expect(theo).toBe(210);

    const safe = FuelRangeService.calculateSafeRange(theo, { safetyReserveKm: 30 });
    expect(safe).toBeLessThanOrEqual(180);
  });

  test('TEST 6: Calculation of remaining fuel during live navigation', () => {
    const remaining = FuelRangeService.calculateRemainingFuel({
      startingFuelLiters: 14,
      distanceTravelledKm: 60,
      efficiencyKmPerLiter: 15,
    });
    // 14 - (60 / 15) = 10 L
    expect(remaining).toBe(10);
  });
});
