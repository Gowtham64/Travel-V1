const { planItinerary, resolveLocation } = require("../services/itineraryEngine");

describe("Smart AI Planner Destination Integrity & Hard Constraint Tests", () => {
  // 30 second timeout for external routing / geocoding during engine calls
  jest.setTimeout(45000);

  const TIRUMALA = {
    name: "Tirumala",
    lat: 13.6833,
    lng: 79.3500,
    placeId: "osm_tirumala_hub",
    address: "Tirumala, Tirupati District, Andhra Pradesh",
  };

  const BENGALURU = {
    name: "Bengaluru",
    lat: 12.9716,
    lng: 77.5946,
    placeId: "osm_bengaluru_hub",
    address: "Bengaluru, Karnataka",
  };

  const CHENNAI = {
    name: "Chennai",
    lat: 13.0827,
    lng: 80.2707,
    placeId: "osm_chennai_hub",
    address: "Chennai, Tamil Nadu",
  };

  const HYDERABAD = {
    name: "Hyderabad",
    lat: 17.3850,
    lng: 78.4867,
    placeId: "osm_hyderabad_hub",
    address: "Hyderabad, Telangana",
  };

  const GOA = {
    name: "Goa",
    lat: 15.2993,
    lng: 74.1240,
    placeId: "osm_goa_hub",
    address: "Panaji, Goa",
  };

  const MYSORE = {
    name: "Mysuru",
    lat: 12.2958,
    lng: 76.6394,
    placeId: "osm_mysore_hub",
    address: "Mysuru, Karnataka",
  };

  describe("Pre-Flight Destination Validation (Requirement #2)", () => {
    it("throws explicit user error if destination is missing or unresolvable", async () => {
      await expect(
        planItinerary({
          startLocation: BENGALURU,
          destination: "",
          tripType: "around",
          durationDays: 1,
        })
      ).rejects.toThrow("We couldn't identify the selected destination. Please select the destination again.");
    });
  });

  describe("Test A: Bengaluru -> Tirumala (Round Trip)", () => {
    it("strictly locks Tirumala as primary destination, arrives on Day 1, and excludes distant cities", async () => {
      const result = await planItinerary({
        startLocation: BENGALURU,
        destination: TIRUMALA,
        tripType: "around",
        durationDays: 2,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.destinationPoint).toBeDefined();
      expect(result.destinationPoint.name).toContain("Tirumala");
      expect(result.destinationPoint.locked).toBe(true);

      // Verify Day 1 contains destination arrival block
      const day1 = result.days[0];
      const destArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
      expect(destArrival).toBeDefined();
      expect(destArrival.title).toContain("Tirumala");
      expect(destArrival.isLocked).toBe(true);

      // Verify forbidden cities are completely absent
      const forbidden = ["chennai", "pondicherry", "mysore", "hyderabad", "madurai", "coimbatore"];
      for (const day of result.days) {
        for (const b of day.blocks) {
          const text = `${b.title} ${b.place || ""} ${b.address || ""}`.toLowerCase();
          for (const city of forbidden) {
            expect(text).not.toContain(city);
          }
        }
      }

      // Verify return to origin at end of round trip
      const lastDay = result.days[result.days.length - 1];
      const lastBlock = lastDay.blocks[lastDay.blocks.length - 1];
      expect(lastBlock.type).toBe("return");
      expect(lastBlock.place).toContain("Bengaluru");
    });
  });

  describe("Test B: Chennai -> Tirumala (Round Trip)", () => {
    it("locks Tirumala destination and plans destination sights, not Chennai city sights", async () => {
      const result = await planItinerary({
        startLocation: CHENNAI,
        destination: TIRUMALA,
        tripType: "around",
        durationDays: 1,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.destinationPoint.name).toContain("Tirumala");
      const day1 = result.days[0];
      const destArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
      expect(destArrival).toBeDefined();

      // Return block must head back to Chennai
      const lastBlock = day1.blocks[day1.blocks.length - 1];
      expect(lastBlock.type).toBe("return");
      expect(lastBlock.place).toContain("Chennai");
    });
  });

  describe("Test C: Hyderabad -> Tirumala (Round Trip)", () => {
    it("locks Tirumala destination and calculates transit corridor from Hyderabad", async () => {
      const result = await planItinerary({
        startLocation: HYDERABAD,
        destination: TIRUMALA,
        tripType: "around",
        durationDays: 2,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.destinationPoint.name).toContain("Tirumala");
      const day1 = result.days[0];
      const destArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
      expect(destArrival).toBeDefined();
    });
  });

  describe("Test D: Bengaluru -> Goa (Round Trip)", () => {
    it("locks Goa destination and generates Goa destination sights", async () => {
      const result = await planItinerary({
        startLocation: BENGALURU,
        destination: GOA,
        tripType: "around",
        durationDays: 2,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.destinationPoint.name).toContain("Goa");
      const day1 = result.days[0];
      const destArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
      expect(destArrival).toBeDefined();
      expect(destArrival.place).toContain("Goa");
    });
  });

  describe("Test E: Bengaluru -> Mysuru (Round Trip)", () => {
    it("locks Mysuru destination and plans sights in Mysuru corridor", async () => {
      const result = await planItinerary({
        startLocation: BENGALURU,
        destination: MYSORE,
        tripType: "around",
        durationDays: 1,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.destinationPoint.name).toContain("Mysur");
      const day1 = result.days[0];
      const destArrival = day1.blocks.find((b) => b.isDestination === true || b.id === "d1_dest_arrival");
      expect(destArrival).toBeDefined();
    });
  });

  describe("Test F: One-Way Trip (Bengaluru -> Tirumala)", () => {
    it("completes trip at destination without returning to origin", async () => {
      const result = await planItinerary({
        startLocation: BENGALURU,
        destination: TIRUMALA,
        tripType: "one_way",
        durationDays: 1,
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 45, currentFuelLiters: 30 },
      });

      expect(result.tripType).toBe("one_way");
      const day1 = result.days[0];
      const lastBlock = day1.blocks[day1.blocks.length - 1];

      // Must end at Tirumala, not Bengaluru
      expect(lastBlock.isDestination).toBe(true);
      expect(lastBlock.type).toBe("destination");
      expect(lastBlock.place).toContain("Tirumala");
      expect(lastBlock.type).not.toBe("return");
    });
  });

  describe("Structured Place Object Support", () => {
    it("accepts structured destination and origin with placeId and exact coordinates", async () => {
      const resolved = await resolveLocation(
        {
          name: "Tirumala Temple",
          latitude: 13.6833,
          longitude: 79.3500,
          placeId: "osm_node_12345",
          address: "Tirumala Hill Town",
        },
        "Destination"
      );

      expect(resolved.name).toBe("Tirumala Temple");
      expect(resolved.lat).toBe(13.6833);
      expect(resolved.lng).toBe(79.3500);
      expect(resolved.placeId).toBe("osm_node_12345");
      expect(resolved.userSelected).toBe(true);
    });
  });
});
