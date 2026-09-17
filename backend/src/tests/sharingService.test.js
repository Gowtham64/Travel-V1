const { createTripShare, getTripShare, sanitizeTripForShare } = require("../services/sharingService");

describe("Sharing Service", () => {
  const sampleTrip = {
    title: "Bangalore to Coorg Road Trip",
    user_id: "secret-user-12345",
    user_email: "secret@domain.com",
    origin: { name: "Bengaluru", lat: 12.9716, lng: 77.5946 },
    destination: { name: "Coorg", lat: 12.3375, lng: 75.8069 },
    distanceKm: 250,
    durationMin: 330,
    travelers: 4,
    vehicle: {
      name: "Hyundai Creta",
      type: "car",
      fuelType: "petrol",
      mileage: 16,
      tankCapacity: 50,
      currentFuel: 20,
    },
    stops: [
      { name: "Mysore Palace", lat: 12.3051, lng: 76.6551, category: "attraction" },
    ],
    budget: {
      total: 5750,
      perPerson: 1437.5,
    },
  };

  test("sanitizeTripForShare scrubs sensitive user data and retains trip details", () => {
    const sanitized = sanitizeTripForShare(sampleTrip);
    expect(sanitized.user_id).toBeUndefined();
    expect(sanitized.user_email).toBeUndefined();
    expect(sanitized.title).toBe("Bangalore to Coorg Road Trip");
    expect(sanitized.distanceKm).toBe(250);
    expect(sanitized.vehicle.name).toBe("Hyundai Creta");
    expect(sanitized.stops.length).toBe(1);
    expect(sanitized.budget.total).toBe(5750);
  });

  test("createTripShare generates unique shareId and getTripShare retrieves it", async () => {
    const result = await createTripShare(sampleTrip);
    expect(result.shareId).toBeDefined();
    expect(result.shareUrl).toContain(result.shareId);

    const retrieved = await getTripShare(result.shareId);
    expect(retrieved).toBeDefined();
    expect(retrieved.title).toBe("Bangalore to Coorg Road Trip");
    expect(retrieved.distanceKm).toBe(250);
    expect(retrieved.user_id).toBeUndefined();
  });
});
