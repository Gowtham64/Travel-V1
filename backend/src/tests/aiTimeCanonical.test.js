const { buildFallbackSmartItinerary, parseMinutes } = require("../services/aiService");

describe("AI Service Canonical Time Validation & Re-anchoring", () => {
  test("parseMinutes accurately parses 12h PM/AM and 24h formats", () => {
    // 2:00 PM must be 14:00 = 840 minutes, NOT 2:00 AM = 120 minutes
    expect(parseMinutes("2:00 PM")).toBe(14 * 60);
    expect(parseMinutes("2:00 PM")).not.toBe(2 * 60);

    // 2:00 AM must be 02:00 = 120 minutes
    expect(parseMinutes("2:00 AM")).toBe(2 * 60);

    // 12:00 AM must be 0 minutes
    expect(parseMinutes("12:00 AM")).toBe(0);

    // 12:00 PM must be 720 minutes (noon)
    expect(parseMinutes("12:00 PM")).toBe(12 * 60);

    // 24h strings
    expect(parseMinutes("14:00")).toBe(14 * 60);
    expect(parseMinutes("02:00")).toBe(2 * 60);
    expect(parseMinutes("00:00")).toBe(0);
  });

  test("buildFallbackSmartItinerary starts Day 1 at exact requested canonical time", () => {
    // User requested around trip time: 2:00 PM
    const res = buildFallbackSmartItinerary({
      destination: "Mysuru",
      startLocation: "Bengaluru",
      places: ["Chamundi Hills", "Mysore Palace", "Brindavan Gardens"],
      startTime: "14:00",
      durationDays: 2,
      travellers: 2,
    });

    expect(res).toBeDefined();
    expect(res.days).toBeDefined();
    expect(res.days.length).toBe(2);

    const day1 = res.days[0];
    expect(day1.blocks.length).toBeGreaterThan(0);

    // First block of Day 1 must start at 2:00 PM (14:00)
    const firstBlock = day1.blocks[0];
    expect(firstBlock.time).toMatch(/2:00\s*PM/i);
    expect(firstBlock.time).not.toMatch(/2:00\s*AM/i);
  });
});
