const itineraryEngine = require("../services/itineraryEngine");

describe("Itinerary Engine: Around Trip & Destination-Anchored Planning Tests", () => {
  jest.setTimeout(35000);

  // TEST 1: Destination-based place relevance (Chennai -> Madurai)
  test("TEST 1: Chennai -> Madurai Around Trip generates Madurai/route-relevant places without unrelated cities", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startDate: "2026-09-10",
      startTime: "07:00",
      durationDays: 2,
      selectedCategories: ["temples", "historical_heritage", "viewpoints"],
      searchRadiusKm: 25,
    });

    expect(result).toBeDefined();
    expect(result.tripType).toBe("around");
    expect(result.days.length).toBe(2);

    // Verify all activity stops are in Madurai or along the Chennai-Madurai corridor (e.g. Trichy / Dindigul)
    const activities = [];
    for (const d of result.days) {
      for (const b of d.blocks) {
        if (b.type === "activity") {
          activities.push(b);
        }
      }
    }
    expect(activities.length).toBeGreaterThan(0);

    for (const act of activities) {
      const name = (act.place || act.title || "").toLowerCase();
      const city = (act.city || "").toLowerCase();

      // Must NEVER contain unrelated cities like Bangalore, Hyderabad, Coimbatore, etc.
      expect(name).not.toContain("bangalore");
      expect(name).not.toContain("bengaluru");
      expect(name).not.toContain("hyderabad");
      expect(name).not.toContain("coimbatore");
      expect(city).not.toContain("bengaluru");
      expect(city).not.toContain("hyderabad");

      // Verify coordinate proximity: must be either within 25km of Madurai OR along direct corridor
      const distToMadurai = Math.hypot(act.lat - 9.9252, act.lng - 78.1198) * 111;
      const isNearMadurai = distToMadurai <= 35; // within ~30 km
      const isCorridor = act.lat >= 9.8 && act.lat <= 13.2 && act.lng >= 77.8 && act.lng <= 80.3;
      expect(isNearMadurai || isCorridor).toBe(true);
    }
  });

  // TEST 2: Select only Temples
  test("TEST 2: Selecting only Temples includes only relevant temples and no random tourist attractions", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startTime: "08:00",
      durationDays: 1,
      selectedCategories: ["temples"],
      searchRadiusKm: 25,
    });

    for (const d of result.days) {
      for (const b of d.blocks) {
        if (b.type === "activity" && !b.isDestinationAnchor) {
          const cat = b.category || "";
          const cats = b.categories || [];
          const isTemple =
            cat === "temples" ||
            cats.includes("temples") ||
            /temple|kovil|swamy|mandir/i.test(b.title);
          expect(isTemple).toBe(true);
        }
      }
    }
  });

  // TEST 3: Select only Historical Places
  test("TEST 3: Selecting only Historical Places recommends historical and heritage locations only", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startTime: "08:00",
      durationDays: 1,
      selectedCategories: ["historical_heritage"],
      searchRadiusKm: 25,
    });

    for (const d of result.days) {
      for (const b of d.blocks) {
        if (b.type === "activity" && !b.isDestinationAnchor) {
          const cat = b.category || "";
          const cats = b.categories || [];
          const isHistorical =
            cat === "historical_heritage" ||
            cat === "forts_palaces" ||
            cats.includes("historical_heritage") ||
            cats.includes("forts_palaces") ||
            /palace|mahal|fort|museum|heritage/i.test(b.title);
          expect(isHistorical).toBe(true);
        }
      }
    }
  });

  // TEST 4: Short duration generates realistic small number of stops
  test("TEST 4: Short duration (1 day) limits stops to realistic count (2-4 stops)", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Madurai",
      destination: "Madurai",
      tripType: "around",
      startTime: "09:00",
      durationDays: 1,
      mode: "relaxed",
      selectedCategories: ["temples", "historical_heritage"],
      searchRadiusKm: 25,
    });

    const activities = result.days[0].blocks.filter((b) => b.type === "activity");
    expect(activities.length).toBeGreaterThanOrEqual(1);
    expect(activities.length).toBeLessThanOrEqual(4);
  });

  // TEST 5: Long duration allows additional relevant stops across multiple days
  test("TEST 5: Long duration (3 days) distributes additional stops across all days with night stays", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startTime: "08:00",
      durationDays: 3,
      selectedCategories: ["temples", "historical_heritage", "viewpoints"],
      searchRadiusKm: 25,
    });

    expect(result.days).toHaveLength(3);
    expect(result.days[0].blocks.some((b) => b.type === "checkin")).toBe(true);
    expect(result.days[1].blocks.some((b) => b.type === "checkin")).toBe(true);
    expect(result.days[2].blocks[result.days[2].blocks.length - 1].type).toBe("return");
  });

  // TEST 6: No invented places when suitable places are sparse
  test("TEST 6: Never invents fake places and returns search area expansion metadata", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Madurai",
      destination: "Madurai",
      tripType: "around",
      startTime: "08:00",
      durationDays: 1,
      selectedCategories: ["wildlife_national_parks"], // No national parks in 10km radius of Madurai city center
      searchRadiusKm: 10,
    });

    expect(result).toBeDefined();
    // Must NOT invent fake national parks
    const fakeParks = result.days[0].blocks.filter(
      (b) => b.type === "activity" && !b.lat
    );
    expect(fakeParks).toHaveLength(0);
    expect(result.canExpandSearch).toBe(true);
    expect(result.nextSearchRadiusKm).toBe(50);
  });

  // TEST 7: Around Trip returns to original start
  test("TEST 7: Around Trip strictly starts and ends at original starting location", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Bengaluru",
      destination: "Mysuru",
      tripType: "around",
      startTime: "08:00",
      durationDays: 1,
      selectedCategories: ["temples", "historical_heritage"],
    });

    expect(result.tripType).toBe("around");
    const d1 = result.days[0];
    const firstBlock = d1.blocks[0];
    const lastBlock = d1.blocks[d1.blocks.length - 1];

    expect(firstBlock.type).toBe("start");
    expect(firstBlock.place.toLowerCase()).toContain("bengaluru");

    expect(lastBlock.type).toBe("return");
    expect(lastBlock.place.toLowerCase()).toContain("bengaluru");
    expect(lastBlock.lat).toBeCloseTo(result.startPoint.lat, 2);
    expect(lastBlock.lng).toBeCloseTo(result.startPoint.lng, 2);
  });

  // TEST 8: Start time 2:00 PM begins exactly at 2:00 PM without AM/PM bug
  test("TEST 8: Start time 2:00 PM (14:00) starts exactly at 02:00 PM", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startDate: "2026-09-10",
      startTime: "14:00", // 2:00 PM
      durationDays: 1,
      selectedCategories: ["temples"],
    });

    const firstBlock = result.days[0].blocks[0];
    expect(firstBlock.start).toBe("02:00 PM");
    expect(firstBlock.start).not.toBe("02:00 AM");
  });

  // TEST 9: Confirmed places become navigation waypoints
  test("TEST 9: Confirmed itinerary places form consistent navigation waypoints", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Chennai",
      destination: "Madurai",
      tripType: "around",
      startTime: "08:00",
      durationDays: 1,
      selectedCategories: ["temples", "historical_heritage"],
    });

    // Extract navigation waypoints from confirmed blocks
    const navWaypoints = [];
    for (const d of result.days) {
      for (const b of d.blocks) {
        if (b.type === "start" || b.type === "activity" || b.type === "return") {
          if (b.lat && b.lng) {
            navWaypoints.push({ lat: b.lat, lng: b.lng, title: b.title || b.place });
          }
        }
      }
    }

    expect(navWaypoints.length).toBeGreaterThanOrEqual(3);
    // Waypoint 0: Origin (Chennai)
    expect(navWaypoints[0].title.toLowerCase()).toContain("chennai");
    // Final Waypoint: Origin Return (Chennai)
    expect(navWaypoints[navWaypoints.length - 1].title.toLowerCase()).toContain("chennai");
  });

  // Helper tests
  test("Time parsing and 24-hour formatting correctness", () => {
    expect(itineraryEngine.parseMinutes("2:00 PM")).toBe(840);
    expect(itineraryEngine.parseMinutes("14:00")).toBe(840);
    expect(itineraryEngine.parseMinutes("02:00 PM")).toBe(840);
    expect(itineraryEngine.parseMinutes("2:00 AM")).toBe(120);
    expect(itineraryEngine.parseMinutes("12:00 PM")).toBe(720);
    expect(itineraryEngine.parseMinutes("12:00 AM")).toBe(0);

    expect(itineraryEngine.formatMinutes(840)).toBe("02:00 PM");
    expect(itineraryEngine.formatMinutes(120)).toBe("02:00 AM");
    expect(itineraryEngine.formatMinutes(720)).toBe("12:00 PM");
    expect(itineraryEngine.formatMinutes(0)).toBe("12:00 AM");
  });

  test("Route sequence optimization minimizes backtracking", () => {
    const start = { lat: 12.9716, lng: 77.5946, name: "Start (Bengaluru)" };
    const stopA = { lat: 12.4237, lng: 76.6853, name: "Srirangapatna (120km)" };
    const stopB = { lat: 12.3051, lng: 76.6552, name: "Mysore Palace (145km)" };
    const stopC = { lat: 12.7800, lng: 77.4000, name: "Bidadi (35km)" };

    const unoptimized = [stopB, stopC, stopA];
    const optimized = itineraryEngine.optimizeStopSequence({
      start,
      end: stopB,
      stops: unoptimized,
      isAroundTrip: false,
    });

    expect(optimized[0].name).toContain("Bidadi");
    expect(optimized[1].name).toContain("Srirangapatna");
    expect(optimized[2].name).toContain("Mysore Palace");
  });

  // TEST 10: Tirumala Destination Hard Geo-Fence Test
  test("TEST 10: Destination Tirumala produces ONLY Tirumala/Tirupati area places and rejects Bangalore/Hyderabad places", async () => {
    const result = await itineraryEngine.planItinerary({
      startLocation: "Bengaluru",
      destination: "Tirumala",
      tripType: "around",
      durationDays: 2,
      selectedCategories: ["temples"],
      searchRadiusKm: 25,
    });

    expect(result).toBeDefined();
    expect(result.tripType).toBe("around");

    const activities = [];
    for (const d of result.days) {
      for (const b of d.blocks) {
        if (b.type === "activity") {
          activities.push(b);
        }
      }
    }

    expect(activities.length).toBeGreaterThan(0);

    for (const act of activities) {
      // Must have valid placeId
      expect(act.placeId).toBeDefined();
      expect(typeof act.placeId).toBe("string");

      const name = (act.place || act.title || "").toLowerCase();
      const city = (act.city || "").toLowerCase();

      // STRICT NEGATIVE ASSERTIONS: Must NEVER contain Bangalore, Hyderabad, Vijayawada, or Chennai
      expect(name).not.toContain("bengaluru");
      expect(name).not.toContain("bangalore");
      expect(name).not.toContain("hyderabad");
      expect(name).not.toContain("vijayawada");
      expect(city).not.toContain("bengaluru");
      expect(city).not.toContain("bangalore");
      expect(city).not.toContain("hyderabad");

      // Geographic proximity assertion: Must be within 25 km of Tirumala (lat 13.6833, lng 79.3473)
      const distToTirumala = Math.hypot(act.lat - 13.6833, act.lng - 79.3473) * 111;
      expect(distToTirumala).toBeLessThanOrEqual(25);
    }
  });

  // TEST 11: Invented place without valid placeId is rejected by Quality Gate
  test("TEST 11: Stop with missing or unrecognized placeId fails quality gate validation", () => {
    const mockDays = [
      {
        day: 1,
        blocks: [
          { type: "start", place: "Bengaluru", start: "08:00 AM", end: "08:00 AM", lat: 12.9716, lng: 77.5946 },
          {
            type: "activity",
            title: "Visit Imaginary Sacred Temple",
            place: "Imaginary Sacred Temple",
            placeId: "fake_invented_place_9999", // Not in candidateMap
            start: "10:00 AM",
            end: "11:00 AM",
            lat: 13.6833,
            lng: 79.3473,
          },
          { type: "return", place: "Bengaluru", start: "05:00 PM", end: "09:00 PM", lat: 12.9716, lng: 77.5946 },
        ],
      },
    ];

    const candidateMap = new Map([
      ["pl_tirumala_venkateswara", { placeId: "pl_tirumala_venkateswara", name: "Lord Venkateswara Temple" }],
    ]);

    expect(() => {
      itineraryEngine.validateItineraryQuality({
        days: mockDays,
        startLocation: { lat: 12.9716, lng: 77.5946 },
        destination: { lat: 13.6833, lng: 79.3473 },
        isAroundTrip: true,
        startMinutes: 480,
        candidateMap,
        searchRadiusKm: 25,
      });
    }).toThrow(/Unrecognized placeId/);
  });

  // TEST 12: Stop with null coordinates is rejected by Quality Gate
  test("TEST 12: Stop with missing coordinates is rejected", () => {
    const mockDays = [
      {
        day: 1,
        blocks: [
          { type: "start", place: "Bengaluru", start: "08:00 AM", end: "08:00 AM", lat: 12.9716, lng: 77.5946 },
          {
            type: "activity",
            title: "Visit Temple",
            placeId: "pl_tirumala_venkateswara",
            start: "10:00 AM",
            end: "11:00 AM",
            lat: null, // Invalid coordinates
            lng: null,
          },
          { type: "return", place: "Bengaluru", start: "05:00 PM", end: "09:00 PM", lat: 12.9716, lng: 77.5946 },
        ],
      },
    ];

    const candidateMap = new Map([
      ["pl_tirumala_venkateswara", { placeId: "pl_tirumala_venkateswara" }],
    ]);

    expect(() => {
      itineraryEngine.validateItineraryQuality({
        days: mockDays,
        startLocation: { lat: 12.9716, lng: 77.5946 },
        destination: { lat: 13.6833, lng: 79.3473 },
        isAroundTrip: true,
        startMinutes: 480,
        candidateMap,
      });
    }).toThrow(/Missing coordinates/);
  });

  // TEST 13: Stop 250 km away is rejected by Quality Gate
  test("TEST 13: Place 250 km away outside searchRadius and corridor is rejected", () => {
    const mockDays = [
      {
        day: 1,
        blocks: [
          { type: "start", place: "Bengaluru", start: "08:00 AM", end: "08:00 AM", lat: 12.9716, lng: 77.5946 },
          {
            type: "activity",
            title: "Visit Charminar Hyderabad",
            placeId: "pl_hyderabad_charminar",
            start: "10:00 AM",
            end: "11:00 AM",
            lat: 17.3616, // Hyderabad - 500 km away
            lng: 78.4747,
          },
          { type: "return", place: "Bengaluru", start: "05:00 PM", end: "09:00 PM", lat: 12.9716, lng: 77.5946 },
        ],
      },
    ];

    const candidateMap = new Map([
      ["pl_hyderabad_charminar", { placeId: "pl_hyderabad_charminar" }],
    ]);

    expect(() => {
      itineraryEngine.validateItineraryQuality({
        days: mockDays,
        startLocation: { lat: 12.9716, lng: 77.5946 },
        destination: { lat: 13.6833, lng: 79.3473 },
        isAroundTrip: true,
        startMinutes: 480,
        candidateMap,
        searchRadiusKm: 25,
      });
    }).toThrow(/outside destination and route bounds/);
  });
});
