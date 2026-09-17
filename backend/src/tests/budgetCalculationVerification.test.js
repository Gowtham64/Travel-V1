const { estimateBudget } = require("../services/budgetService");

describe("Independent Calculation Cross-Check", () => {
  test("Budget total equals exact mathematical sum of components for single traveller 1-day trip", () => {
    const budget = estimateBudget({
      distanceKm: 250,
      estimatedDays: 1,
      vehicle: { efficiencyKmPerLiter: 15.0, fuelType: "petrol", currentFuelLiters: 5.0 },
      toll: { hasTolls: true, fastagTollCost: 240 },
      startLocation: "Bengaluru",
      options: {
        travellers: 1,
        activities: 500,
        parking: 100,
      },
    });

    const b = budget.breakdown;
    const computedSum = b.fuel + b.tolls + b.food + b.stay + b.activities + b.parking + b.miscellaneous + b.transport + b.localTransport;

    expect(budget.total).toBe(computedSum);
    expect(budget.perPerson).toBe(budget.total);
  });

  test("Budget total and per-person cost accurately scales for 4 travellers and 3 days", () => {
    const budget = estimateBudget({
      distanceKm: 600,
      estimatedDays: 3,
      vehicle: { efficiencyKmPerLiter: 12.0, fuelType: "diesel", currentFuelLiters: 10.0 },
      toll: { hasTolls: true, fastagTollCost: 650 },
      startLocation: "Bengaluru",
      options: {
        travellers: 4,
        activitiesCost: 2000,
        parkingCost: 400,
      },
    });

    const b = budget.breakdown;
    const computedSum = b.fuel + b.tolls + b.food + b.stay + b.activities + b.parking + b.miscellaneous + b.transport + b.localTransport;

    expect(budget.total).toBe(computedSum);
    expect(budget.perPerson).toBe(Math.round(budget.total / 4));
    expect(budget.perDay).toBe(Math.round(budget.total / 3));
  });
});
