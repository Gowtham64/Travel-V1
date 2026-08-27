const { getDestinationEvents } = require("../services/eventsService");
const axios = require("axios");

jest.mock("axios");

describe("eventsService", () => {
  afterEach(() => {
    jest.resetAllMocks();
  });

  test("returns empty array when coordinates are invalid", async () => {
    const res = await getDestinationEvents("invalid", null);
    expect(res).toEqual([]);
  });

  test("fetches events from Ticketmaster API when available", async () => {
    axios.get.mockImplementation((url) => {
      if (url.includes("ticketmaster.com")) {
        return Promise.resolve({
          data: {
            _embedded: {
              events: [
                {
                  id: "ev1",
                  name: "Music Festival",
                  classifications: [{ segment: { name: "Music" } }],
                  _embedded: { venues: [{ name: "Palace Grounds" }] },
                  dates: { start: { localDate: "2026-09-15" } },
                  info: "Annual live festival",
                  url: "https://ticketmaster.com/ev1",
                },
              ],
            },
          },
        });
      }
      return Promise.reject(new Error("Network error"));
    });

    const events = await getDestinationEvents(12.9716, 77.5946, "Bengaluru");
    expect(events.length).toBe(1);
    expect(events[0].title).toBe("Music Festival");
    expect(events[0].category).toBe("Music");
  });

  test("falls back to Wikipedia spots if event API fails", async () => {
    axios.get.mockImplementation((url) => {
      if (url.includes("ticketmaster")) {
        return Promise.reject(new Error("429 Too Many Requests"));
      }
      if (url.includes("geosearch")) {
        return Promise.resolve({
          data: {
            query: {
              geosearch: [{ pageid: 501, title: "Lalbagh Botanical Garden", dist: 120 }],
            },
          },
        });
      }
      return Promise.reject(new Error("Unknown URL"));
    });

    const events = await getDestinationEvents(12.9716, 77.5946, "Bengaluru");
    expect(events.length).toBe(1);
    expect(events[0].title).toBe("Explore Lalbagh Botanical Garden");
    expect(events[0].category).toBe("Sightseeing & Culture");
  });
});
