const request = require("supertest");

jest.mock("../services/routingService");
jest.mock("../services/tollService");
jest.mock("../services/placesService");

const { getRoute } = require("../services/routingService");
const { getTollEstimate } = require("../services/tollService");
const { findPlacesAlongRoute } = require("../services/placesService");

const app = require("../index");

describe("POST /api/trip/plan", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("400 when start/end are missing", async () => {
    const res = await request(app).post("/api/trip/plan").send({});
    expect(res.status).toBe(400);
  });

  test("400 when vehicle info is missing", async () => {
    const res = await request(app)
      .post("/api/trip/plan")
      .send({ start: { lat: 1, lng: 1 }, end: { lat: 2, lng: 2 } });
    expect(res.status).toBe(400);
  });

  test("200 with a full trip plan when inputs are valid", async () => {
    getRoute.mockResolvedValue({
      distanceKm: 350,
      durationMin: 360,
      coordinates: [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 13.5, lng: 78.5 },
        { lat: 14.0, lng: 79.5 },
      ],
    });
    getTollEstimate.mockResolvedValue({
      hasTolls: true,
      currency: "INR",
      minTollCost: 180,
      maxTollCost: 210,
      fuelCost: 1450,
      distanceKm: 350,
      durationMin: 360,
    });
    findPlacesAlongRoute.mockResolvedValue([{ id: 1, name: "Sample restaurant", lat: 13.5, lng: 78.5 }]);

    const res = await request(app)
      .post("/api/trip/plan")
      .send({
        start: { lat: 12.9716, lng: 77.5946 },
        end: { lat: 14.0, lng: 79.5 },
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 40, currentFuelLiters: 35 },
        includePlaces: ["restaurant"],
      });

    expect(res.status).toBe(200);
    expect(res.body.estimatedDays).toBeGreaterThanOrEqual(1);
    expect(res.body.route.distanceKm).toBe(350);
    expect(res.body.toll.hasTolls).toBe(true);
    expect(res.body.places.restaurant).toHaveLength(1);
    expect(res.body.fuel).toHaveProperty("needsRefuel");
  });

  test("trip plan still succeeds even if the toll lookup fails", async () => {
    getRoute.mockResolvedValue({
      distanceKm: 100,
      durationMin: 90,
      coordinates: [
        { lat: 12.9716, lng: 77.5946 },
        { lat: 13.0, lng: 77.7 },
      ],
    });
    getTollEstimate.mockRejectedValue(new Error("quota exceeded"));

    const res = await request(app)
      .post("/api/trip/plan")
      .send({
        start: { lat: 12.9716, lng: 77.5946 },
        end: { lat: 13.0, lng: 77.7 },
        vehicle: { type: "car", efficiencyKmPerLiter: 15, tankCapacityLiters: 40, currentFuelLiters: 35 },
      });

    expect(res.status).toBe(200);
    expect(res.body.toll).toBeNull();
  });
});
