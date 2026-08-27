const { getWikiPlaces } = require("../services/wikiService");
const axios = require("axios");

jest.mock("axios");

describe("wikiService", () => {
  afterEach(() => {
    jest.resetAllMocks();
  });

  test("returns empty array when lat/lng are missing or invalid", async () => {
    const res = await getWikiPlaces(null, undefined);
    expect(res).toEqual([]);
  });

  test("fetches Wikipedia places with summaries and thumbnails", async () => {
    axios.get.mockImplementation((url) => {
      if (url.includes("list=geosearch")) {
        return Promise.resolve({
          data: {
            query: {
              geosearch: [
                { pageid: 101, title: "Mysore Palace", lat: 12.305, lng: 76.655, dist: 350 },
              ],
            },
          },
        });
      }
      if (url.includes("prop=pageimages|extracts")) {
        return Promise.resolve({
          data: {
            query: {
              pages: {
                101: {
                  extract: "A historical palace in Mysuru.",
                  thumbnail: { source: "https://upload.wikimedia.org/mysore.jpg" },
                },
              },
            },
          },
        });
      }
      return Promise.reject(new Error("Unknown URL"));
    });

    const places = await getWikiPlaces(12.305, 76.655);
    expect(places.length).toBe(1);
    expect(places[0].title).toBe("Mysore Palace");
    expect(places[0].summary).toBe("A historical palace in Mysuru.");
    expect(places[0].thumbnailUrl).toBe("https://upload.wikimedia.org/mysore.jpg");
  });

  test("gracefully handles API errors by returning empty array", async () => {
    axios.get.mockRejectedValue(new Error("Network error"));
    const places = await getWikiPlaces(12.305, 76.655);
    expect(places).toEqual([]);
  });
});
