jest.mock("axios");
const axios = require("axios");
const { findTreksNear, difficultyFromTags, lengthKmFromTags } = require("../services/treksService");

describe("difficultyFromTags", () => {
  test("maps sac_scale to a friendly label", () => {
    expect(difficultyFromTags({ sac_scale: "mountain_hiking" })).toBe("Moderate");
    expect(difficultyFromTags({ sac_scale: "alpine_hiking" })).toBe("Very hard");
  });
  test("falls back to difficulty tag, else null", () => {
    expect(difficultyFromTags({ difficulty: "easy" })).toBe("Easy");
    expect(difficultyFromTags({})).toBeNull();
  });
});

describe("lengthKmFromTags", () => {
  test("parses km values", () => {
    expect(lengthKmFromTags({ distance: "12.5" })).toBe(12.5);
    expect(lengthKmFromTags({ distance: "8 km" })).toBe(8);
  });
  test("converts metre values to km", () => {
    expect(lengthKmFromTags({ distance: "8000 m" })).toBe(8);
  });
  test("returns null when absent/invalid", () => {
    expect(lengthKmFromTags({})).toBeNull();
    expect(lengthKmFromTags({ distance: "abc" })).toBeNull();
  });
});

describe("findTreksNear", () => {
  test("parses, de-dupes by name, and sorts nearest first", async () => {
    axios.post.mockResolvedValue({
      data: {
        elements: [
          // Far trek (relation with center)
          { type: "relation", id: 1, center: { lat: 12.5, lon: 77.5 }, tags: { name: "Far Ridge Trail", route: "hiking", distance: "20 km", sac_scale: "mountain_hiking" } },
          // Near trek (way with center)
          { type: "way", id: 2, center: { lat: 12.01, lon: 77.01 }, tags: { name: "Near Loop", highway: "path", sac_scale: "hiking" } },
          // Duplicate name of the near one — should be dropped
          { type: "relation", id: 3, center: { lat: 12.02, lon: 77.02 }, tags: { name: "near loop", route: "foot" } },
          // No name — dropped
          { type: "way", id: 4, center: { lat: 12.0, lon: 77.0 }, tags: { highway: "path" } },
        ],
      },
    });

    const treks = await findTreksNear(12.0, 77.0, 30000, 20);
    expect(treks.map((t) => t.name)).toEqual(["Near Loop", "Far Ridge Trail"]); // nearest first, deduped
    expect(treks[0].difficulty).toBe("Easy");
    expect(treks[1].lengthKm).toBe(20);
    expect(treks[0].distanceFromSearchKm).toBeLessThan(treks[1].distanceFromSearchKm);
  });

  test("extracts way geometry, measures length, and simplifies the path", async () => {
    axios.post.mockResolvedValue({
      data: {
        elements: [
          {
            type: "way",
            id: 10,
            geometry: [
              { lat: 12.0, lon: 77.0 },
              { lat: 12.1, lon: 77.0 },
              { lat: 12.2, lon: 77.0 },
            ],
            tags: { name: "Ridge Way", highway: "path", sac_scale: "hiking" },
          },
        ],
      },
    });
    const treks = await findTreksNear(12.0, 77.0, 30000, 20);
    expect(treks).toHaveLength(1);
    expect(treks[0].path.length).toBe(3);
    expect(treks[0].lat).toBeCloseTo(12.0, 3); // representative = geometry start
    expect(treks[0].lengthKm).toBeGreaterThan(20); // ~22km measured from geometry
    expect(treks[0].lengthKm).toBeLessThan(24);
  });

  test("concatenates relation member geometry", async () => {
    axios.post.mockResolvedValue({
      data: {
        elements: [
          {
            type: "relation",
            id: 20,
            members: [
              { type: "way", geometry: [ { lat: 12.0, lon: 77.0 }, { lat: 12.05, lon: 77.0 } ] },
              { type: "way", geometry: [ { lat: 12.05, lon: 77.0 }, { lat: 12.1, lon: 77.0 } ] },
            ],
            tags: { name: "Grand Loop", route: "hiking" },
          },
        ],
      },
    });
    const treks = await findTreksNear(12.0, 77.0);
    expect(treks[0].path.length).toBe(4);
    expect(treks[0].type).toBe("hiking route");
  });

  test("throws on non-finite coordinates", async () => {
    await expect(findTreksNear(NaN, 77.0)).rejects.toThrow();
  });
});
