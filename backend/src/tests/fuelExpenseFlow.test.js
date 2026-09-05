const { calculateRouteFuel, getFuelPrices } = require("../services/fuelService");
const { estimateBudget } = require("../services/budgetService");
const { calculateRouteTolls } = require("../services/tollService");

describe("Fuel & Expense Flow Verification", () => {
  test("getFuelPrices returns non-zero, formatted pricing metadata with source and status", () => {
    const res = getFuelPrices({ locationName: "Salem, Tamil Nadu", fuelType: "petrol" });
    expect(res.status).toBe("CURRENT");
    expect(res.price).toBeGreaterThan(90);
    expect(res.currencySymbol).toBe("₹");
    expect(res.source).toContain("CarDekho / OMC");
    expect(res.displayPrice).toContain("₹");
    expect(res.applicableLocation).toContain("Tamil Nadu");
  });

  test("calculateRouteFuel accurately computes fuel required, current fuel, and additional required", () => {
    // 500 km route, 15 km/L efficiency, 10 L in tank
    const fuelCalc = calculateRouteFuel({
      distanceKm: 500,
      vehicleEfficiency: 15.0,
      currentFuelLiters: 10.0,
      fuelType: "petrol",
      fuelPrice: 100.0,
      startLocation: "Chennai",
      endLocation: "Madurai",
    });

    // 500 / 15 = 33.33 L
    expect(fuelCalc.fuelRequiredLiters).toBe(33.33);
    expect(fuelCalc.currentFuelLiters).toBe(10.0);
    // Additional required: 33.33 - 10 = 23.33 L
    expect(fuelCalc.additionalFuelRequiredLiters).toBe(23.33);
    // Estimated cost: 23.33 * 100 = 2333
    expect(fuelCalc.estimatedCost).toBe(2333);
    // Total fuel cost: 33.33 * 100 = 3333
    expect(fuelCalc.totalFuelCost).toBe(3333);
  });

  test("estimateBudget separates Fuel, Tolls, Meals (Breakfast, Lunch, Tea, Dinner), and Other", () => {
    const budget = estimateBudget({
      distanceKm: 500,
      estimatedDays: 2,
      vehicle: { efficiencyKmPerLiter: 15.0, fuelType: "petrol", currentFuelLiters: 10.0 },
      toll: { hasTolls: true, fastagTollCost: 450 },
      startLocation: "Chennai",
      options: { travellers: 1 },
    });

    expect(budget.breakdown.fuel).toBeGreaterThan(0);
    expect(budget.breakdown.tolls).toBe(450);
    expect(budget.breakdown.breakfast).toBe(250 * 2); // 500
    expect(budget.breakdown.lunch).toBe(500 * 2);     // 1000
    expect(budget.breakdown.teaSnacks).toBe(200 * 2); // 400
    expect(budget.breakdown.dinner).toBe(500 * 2);    // 1000
    expect(budget.breakdown.other).toBe(300 * 2);     // 600
    expect(budget.total).toBe(
      budget.breakdown.fuel +
      budget.breakdown.tolls +
      budget.breakdown.food +
      budget.breakdown.other +
      budget.breakdown.stay
    );
  });

  test("calculateRouteTolls returns individual toll plazas encountered on the route", () => {
    // Route from Bengaluru (12.97, 77.59) to Krishnagiri (12.53, 78.21)
    const routeCoords = [
      { lat: 12.97, lng: 77.59 },
      { lat: 12.78, lng: 77.77 }, // Near Attibele Toll
      { lat: 12.56, lng: 78.22 }, // Near Krishnagiri Toll
      { lat: 12.53, lng: 78.21 },
    ];

    const tollResult = calculateRouteTolls(
      routeCoords[0],
      routeCoords[routeCoords.length - 1],
      "car",
      routeCoords
    );

    expect(tollResult.hasTolls).toBe(true);
    expect(tollResult.tollCount).toBeGreaterThanOrEqual(1);
    expect(Array.isArray(tollResult.tolls)).toBe(true);
    const firstToll = tollResult.tolls[0];
    expect(firstToll).toHaveProperty("name");
    expect(firstToll).toHaveProperty("amount");
    expect(firstToll).toHaveProperty("latitude");
    expect(firstToll).toHaveProperty("longitude");
  });
});
