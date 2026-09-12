const axios = require("axios");
const { findPOIsAlongRoute } = require("../services/orsPoiService");

jest.mock("axios");

describe("orsPoiService - findPOIsAlongRoute corridor sorting", () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  test("sorts returned POIs progressively from route start to destination", async () => {
    // Route from Bangalore (12.97, 77.59) towards Tirupati (13.62, 79.41)
    const routeCoords = [
      { lat: 12.9716, lng: 77.5946 }, // Bangalore
      { lat: 13.1367, lng: 78.1291 }, // Kolar
      { lat: 13.2185, lng: 79.1008 }, // Chittoor
      { lat: 13.6288, lng: 79.4192 }, // Tirupati
    ];

    // Mock photon response with places scattered in reverse order
    axios.get.mockImplementation((url, config) => {
      return Promise.resolve({
        data: {
          features: [
            {
              geometry: { coordinates: [79.40, 13.62] }, // Tirupati (~210km away)
              properties: { name: "Tirupati Highway Dhaba", city: "Tirupati" },
            },
            {
              geometry: { coordinates: [78.13, 13.14] }, // Kolar (~60km away)
              properties: { name: "Kolar Woodlands Restaurant", city: "Kolar" },
            },
            {
              geometry: { coordinates: [77.60, 12.97] }, // Bangalore (~1km away)
              properties: { name: "Bangalore Cafe", city: "Bengaluru" },
            },
          ],
        },
      });
    });

    const result = await findPOIsAlongRoute(routeCoords, ["restaurant"]);

    expect(result).toHaveProperty("restaurant");
    const list = result.restaurant;
    expect(list.length).toBeGreaterThan(0);

    // Verify list is sorted in ascending order of distance from Bangalore
    for (let i = 0; i < list.length - 1; i++) {
      const distA = Math.hypot(list[i].lat - routeCoords[0].lat, list[i].lng - routeCoords[0].lng);
      const distB = Math.hypot(list[i + 1].lat - routeCoords[0].lat, list[i + 1].lng - routeCoords[0].lng);
      expect(distA).toBeLessThanOrEqual(distB);
    }

    // The first item should be the closest to the start (Bangalore Cafe)
    expect(list[0].name).toBe("Bangalore Cafe");
  });
});
