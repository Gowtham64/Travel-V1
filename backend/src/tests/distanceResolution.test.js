const { buildFallbackSmartItinerary } = require("../services/aiService");

describe("Dynamic Distance Resolution & Curated Venues", () => {
  test("calculates realistic distance and drive time for Maddur to Goa (~560 km, NOT 145 km)", () => {
    const res = buildFallbackSmartItinerary({
      startLocation: { name: "Main Road 57, Maddur, 571419, India", lat: 12.5844, lng: 77.0453 },
      destination: { name: "Goa, India", lat: 15.2993, lng: 74.1240 },
      durationDays: 2,
      startTime: "06:00",
    });

    expect(res).toBeDefined();
    expect(res.days).toBeDefined();
    const day1Travel = res.days[0].blocks[0];

    expect(day1Travel.type).toBe("travel");
    expect(day1Travel.travelMode).toBe("drive");
    // Should be around 550 - 570 km, definitely NOT 145 km
    expect(day1Travel.distanceKm).toBeGreaterThan(500);
    expect(day1Travel.distanceKm).toBeLessThan(600);
    expect(day1Travel.distanceKm).not.toBe(145.0);

    // Duration should be approx ~600 mins (10 hours), NOT 145 mins
    expect(day1Travel.durationMin).toBeGreaterThan(500);
    expect(day1Travel.durationMin).not.toBe(145);
  });

  test("calculates realistic distance for Maddur to Mysuru (~70 km, NOT 145 km)", () => {
    const res = buildFallbackSmartItinerary({
      startLocation: "Maddur",
      destination: "Mysuru",
      durationDays: 1,
      startTime: "07:00",
    });

    const day1Travel = res.days[0].blocks[0];
    expect(day1Travel.distanceKm).toBeGreaterThan(55);
    expect(day1Travel.distanceKm).toBeLessThan(85);
    expect(day1Travel.distanceKm).not.toBe(145.0);
  });

  test("detects overseas destination (India to Philippines) as flight with ~4,950 km", () => {
    const res = buildFallbackSmartItinerary({
      startLocation: { name: "Main Road 57, Maddur, 571419, India", lat: 12.5844, lng: 77.0453 },
      destination: { name: "Goa, Camarines Sur, Philippines", lat: 13.6218, lng: 123.1948 },
      durationDays: 2,
      startTime: "06:00",
    });

    const day1Travel = res.days[0].blocks[0];
    expect(day1Travel.type).toBe("travel");
    expect(day1Travel.travelMode).toBe("flight");
    expect(day1Travel.title).toMatch(/Flight/i);
    expect(day1Travel.distanceKm).toBeGreaterThan(4500);
    expect(day1Travel.distanceKm).toBeLessThan(5500);
    expect(day1Travel.distanceKm).not.toBe(145.0);
  });

  test("curates authentic Goa dining and accommodation venues", () => {
    const res = buildFallbackSmartItinerary({
      startLocation: "Bengaluru",
      destination: "Goa, India",
      durationDays: 2,
      startTime: "06:00",
    });

    const day1Blocks = res.days[0].blocks;
    const lunchBlock = day1Blocks.find((b) => b.breakType === "lunch" || b.title.includes("Lunch"));
    const hotelBlock = day1Blocks.find((b) => b.type === "checkin" || b.title.includes("Hotel"));

    expect(lunchBlock).toBeDefined();
    expect(lunchBlock.title).toContain("Ritz Classic");

    expect(hotelBlock).toBeDefined();
    expect(hotelBlock.title).toContain("Taj Fort Aguada");
  });
});
