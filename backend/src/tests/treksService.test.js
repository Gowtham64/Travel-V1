jest.mock("axios");
const axios = require("axios");
const { findTreksNear, getTrekGeometry, difficultyFromTags, lengthKmFromTags } = require("../services/treksService");

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

  test("filters road-named ways unless they are graded trails", async () => {
    axios.post.mockResolvedValue({
      data: {
        elements: [
          { type: "way", id: 1, center: { lat: 12.01, lon: 77.01 }, tags: { name: "Chokramudi trail", highway: "path" } },
          { type: "way", id: 2, center: { lat: 12.02, lon: 77.02 }, tags: { name: "Mens Hostel Road", highway: "path" } },
          { type: "way", id: 3, center: { lat: 12.03, lon: 77.03 }, tags: { name: "Old Fort Road", highway: "path", sac_scale: "hiking" } },
        ],
      },
    });
    const treks = await findTreksNear(12.0, 77.0);
    const names = treks.map((t) => t.name);
    expect(names).toContain("Chokramudi trail");
    expect(names).toContain("Old Fort Road"); // graded -> kept despite the name
    expect(names).not.toContain("Mens Hostel Road"); // road-named + ungraded -> dropped
  });

  test("throws on non-finite coordinates", async () => {
    await expect(findTreksNear(NaN, 77.0)).rejects.toThrow();
  });
});

describe("getTrekGeometry", () => {
  test("extracts way geometry and measures length", async () => {
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
          },
        ],
      },
    });
    const geom = await getTrekGeometry("way/10");
    expect(geom.path.length).toBe(3);
    expect(geom.lengthKm).toBeGreaterThan(20); // ~22km
    expect(geom.lengthKm).toBeLessThan(24);
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
          },
        ],
      },
    });
    const geom = await getTrekGeometry("relation/20");
    expect(geom.path.length).toBe(4);
  });

  test("rejects a malformed id", async () => {
    await expect(getTrekGeometry("garbage")).rejects.toThrow();
  });
});
