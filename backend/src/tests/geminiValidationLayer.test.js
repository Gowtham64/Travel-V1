const { planItinerary } = require("../services/itineraryEngine");
const { validateItineraryWithGemini, deterministicValidate, isDeceptivePlace } = require("../services/geminiValidatorService");

describe("Smart AI Planner - Gemini Validation Layer Tests", () => {
  jest.setTimeout(40000);

  // ── TEST 1: Deceptive Place Detection ──────────────────────────────────────
  test("TEST 1: Deceptive Place Detection", () => {
    expect(isDeceptivePlace("Temple View Restaurant", "temple")).toBe(true);
    expect(isDeceptivePlace("Hill Cafe and Dhaba", "hill")).toBe(true);
    expect(isDeceptivePlace("Sri Venkateswara Temple", "temple")).toBe(false);
    expect(isDeceptivePlace("Seshachalam Hills Viewpoint", "hill")).toBe(false);
  });

  // ── TEST 2: Category = Temples ─────────────────────────────────────────────
  test("TEST 2: Category = Temples", async () => {
    const templeTrip = await planItinerary({
      startLocation: "Bengaluru",
      destination: "Tirupati",
      durationDays: 1,
      selectedCategories: ["Temples"],
    });
    const templeActivities = (templeTrip.days[0].blocks || []).filter((b) => b.type === "activity");
    expect(templeActivities.length).toBeGreaterThan(0);
    const allTemples = templeActivities.every((a) => {
      const p = (a.place || "").toLowerCase();
      return a.category === "temple" || a.category === "spiritual" || p.includes("temple") || p.includes("theertham");
    });
    expect(allTemples).toBe(true);

    const templeValidation = await validateItineraryWithGemini({
      itinerary: templeTrip,
      destination: templeTrip.destinationPoint,
      origin: templeTrip.startPoint,
      selectedCategories: ["Temples"],
      durationDays: 1,
    });
    expect(templeValidation.valid).toBe(true);
  });

  // ── TEST 3: Category = Hills ───────────────────────────────────────────────
  test("TEST 3: Category = Hills", async () => {
    const hillsTrip = await planItinerary({
      startLocation: "Bengaluru",
      destination: "Tirupati",
      durationDays: 1,
      selectedCategories: ["Hills"],
    });
    const hillsActivities = (hillsTrip.days[0].blocks || []).filter((b) => b.type === "activity");
    expect(hillsActivities.length).toBeGreaterThan(0);
    const allHills = hillsActivities.every((a) => {
      const p = (a.place || "").toLowerCase();
      return (
        a.category === "hill" ||
        a.category === "viewpoint" ||
        a.category === "nature" ||
        p.includes("hill") ||
        p.includes("viewpoint") ||
        p.includes("shilathoranam")
      );
    });
    expect(allHills).toBe(true);
  });

  // ── TEST 4: Category = Temples + Hills + Nature (Multi-Category Distribution)
  test("TEST 4: Category = Temples + Hills + Nature", async () => {
    const multiCatTrip = await planItinerary({
      startLocation: "Bengaluru",
      destination: "Tirupati",
      durationDays: 2,
      selectedCategories: ["Temples", "Hills", "Nature"],
    });
    const allMultiActivities = multiCatTrip.days.flatMap((d) => (d.blocks || []).filter((b) => b.type === "activity"));
    expect(allMultiActivities.length).toBeGreaterThan(0);

    const hasTemple = allMultiActivities.some((a) => a.category === "temple" || (a.place || "").toLowerCase().includes("temple"));
    const hasHillOrNature = allMultiActivities.some(
      (a) =>
        a.category === "hill" ||
        a.category === "nature" ||
        a.category === "viewpoint" ||
        (a.place || "").toLowerCase().includes("hill") ||
        (a.place || "").toLowerCase().includes("viewpoint") ||
        (a.place || "").toLowerCase().includes("park")
    );

    expect(hasTemple).toBe(true);
    expect(hasHillOrNature).toBe(true);
  });

  // ── TEST 5: Destination Lock (Tirumala remains Tirumala) ───────────────────
  test("TEST 5: Destination Lock (Tirumala)", async () => {
    const tirumalaTrip = await planItinerary({
      startLocation: "Mandya",
      destination: "Tirumala",
      durationDays: 3,
      selectedCategories: ["Temples"],
    });
    expect(tirumalaTrip.destinationPoint.name.toLowerCase()).toContain("tirumala");
    expect(tirumalaTrip.days.length).toBe(3);

    const tirumalaValidation = await validateItineraryWithGemini({
      itinerary: tirumalaTrip,
      destination: tirumalaTrip.destinationPoint,
      origin: tirumalaTrip.startPoint,
      selectedCategories: ["Temples"],
      durationDays: 3,
    });
    expect(tirumalaValidation.destinationValid).toBe(true);
  });

  // ── TEST 6: Correction Feedback Loop ───────────────────────────────────────
  test("TEST 6: Correction Feedback Loop", () => {
    const badItineraryMock = {
      days: [
        {
          day: 1,
          title: "Day 1",
          blocks: [
            { type: "start", title: "Start", start: "08:00", end: "08:30", lat: 12.5, lng: 77.0 },
            {
              type: "activity",
              title: "Phoenix Marketcity Mall",
              place: "Phoenix Marketcity Mall",
              placeId: "bad_mall_1",
              category: "shopping",
              start: "09:00",
              end: "10:30",
              lat: 12.9,
              lng: 77.6,
            },
            {
              type: "activity",
              title: "Wonderla Water Park",
              place: "Wonderla Water Park",
              placeId: "bad_water_park_2",
              category: "adventure",
              start: "11:00",
              end: "13:00",
              lat: 12.8,
              lng: 77.4,
            },
          ],
        },
      ],
    };

    const rejection = deterministicValidate({
      itinerary: badItineraryMock,
      destination: { name: "Tirumala" },
      origin: { name: "Mandya" },
      selectedCategories: ["Temples"],
      durationDays: 1,
    });

    expect(rejection.valid).toBe(false);
    expect(rejection.blacklistedPlaceIds).toContain("bad_mall_1");
    expect(rejection.blacklistedPlaceIds).toContain("bad_water_park_2");
  });
});
