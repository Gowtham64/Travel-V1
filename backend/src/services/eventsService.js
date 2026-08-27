const axios = require("axios");

/**
 * Fetch local events & activities near target destination coordinates.
 * Integrates open event APIs with graceful fallback.
 *
 * @param {number} lat - Latitude of destination
 * @param {number} lng - Longitude of destination
 * @param {string} [destinationName=""] - Destination city/place name
 * @returns {Promise<Array<{id: string, title: string, category: string, location: string, date: string, description: string, url: string|null}>>}
 */
async function getDestinationEvents(lat, lng, destinationName = "") {
  if (typeof lat !== "number" || typeof lng !== "number") {
    return [];
  }

  const events = [];

  // Try OpenEvent/Ticketmaster public API if search term available
  if (destinationName) {
    try {
      const query = encodeURIComponent(destinationName);
      const url = `https://app.ticketmaster.com/discovery/v2/events.json?keyword=${query}&size=4&apikey=7elgEcT9TXA8oM4PGzA20tBfaA`;
      const res = await axios.get(url, { timeout: 6000 });
      const tmEvents = res.data?._embedded?.events || [];

      for (const ev of tmEvents) {
        events.push({
          id: ev.id || String(Math.random()),
          title: ev.name,
          category: ev.classifications?.[0]?.segment?.name || "General Event",
          location: ev._embedded?.venues?.[0]?.name || destinationName,
          date: ev.dates?.start?.localDate || "Upcoming",
          description: ev.info || `Event in ${destinationName}`,
          url: ev.url || null,
        });
      }
    } catch (err) {
      // Soft fallback if Ticketmaster API limit reached or network error
    }
  }

  // Fallback: search Wikipedia events or local highlights near coordinates
  if (events.length === 0) {
    try {
      const wikiUrl = `https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=${lat}|${lng}&gsradius=10000&gslimit=5&format=json&origin=*`;
      const wikiRes = await axios.get(wikiUrl, { timeout: 6000 });
      const spots = wikiRes.data?.query?.geosearch || [];

      for (const spot of spots.slice(0, 3)) {
        events.push({
          id: `wiki-${spot.pageid}`,
          title: `Explore ${spot.title}`,
          category: "Sightseeing & Culture",
          location: destinationName || "Near Destination",
          date: "Open Daily",
          description: `Popular cultural point of interest located ${Math.round(spot.dist)}m from center.`,
          url: `https://en.wikipedia.org/?curid=${spot.pageid}`,
        });
      }
    } catch (err) {
      console.warn("Destination events fallback search failed:", err.message);
    }
  }

  return events;
}

module.exports = {
  getDestinationEvents,
};
