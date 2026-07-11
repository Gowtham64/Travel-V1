const request = require("supertest");

jest.mock("../services/geocodeService");
const { geocodeAddress } = require("../services/geocodeService");
const app = require("../index");

describe("GET /api/geocode", () => {
  test("400 when q is missing", async () => {
    const res = await request(app).get("/api/geocode");
    expect(res.status).toBe(400);
  });

  test("200 with coordinates when an address is found", async () => {
    geocodeAddress.mockResolvedValue({ lat: 12.9716, lng: 77.5946, displayName: "Bengaluru, India" });
    const res = await request(app).get("/api/geocode").query({ q: "Bengaluru" });
    expect(res.status).toBe(200);
    expect(res.body.lat).toBeCloseTo(12.9716);
  });

  test("404 when no result is found", async () => {
    geocodeAddress.mockResolvedValue(null);
    const res = await request(app).get("/api/geocode").query({ q: "asdkfjhaskldjfh" });
    expect(res.status).toBe(404);
  });
});
